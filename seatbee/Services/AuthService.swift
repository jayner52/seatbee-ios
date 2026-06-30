import Foundation
import AuthenticationServices
import Supabase

@Observable
final class AuthService {
    var currentUser: User? {
        didSet {
            // Keep the iOS metrics widget's admin token in sync with auth state:
            // mint on sign-in / restored session (best-effort — non-admins get a
            // 403 and no token), clear on sign-out. See WidgetTokenProvider.
            if currentUser != nil {
                Task { await WidgetTokenProvider.refreshIfNeeded() }
            } else if oldValue != nil {
                WidgetTokenProvider.clear()
            }
        }
    }
    var isAuthenticated: Bool { currentUser != nil }
    var isLoading = false
    var error: String?

    /// Best available display name: OAuth provider name → stored profile name → nil.
    /// Google stores `full_name` in userMetadata; Apple stores `full_name` only on
    /// first auth, so we persist it to profiles and read it back via `loadProfile`.
    var displayName: String? {
        guard let user = currentUser else { return nil }
        if case .string(let n) = user.userMetadata["full_name"], !n.isEmpty { return n }
        if case .string(let n) = user.userMetadata["name"], !n.isEmpty { return n }
        return nil
    }

    /// Google profile photo URL. Supabase normalises the Google `picture` claim
    /// to `avatar_url` in userMetadata. Returns nil for Apple / email users.
    var avatarURL: URL? {
        guard let user = currentUser else { return nil }
        if case .string(let s) = user.userMetadata["avatar_url"] { return URL(string: s) }
        if case .string(let s) = user.userMetadata["picture"]    { return URL(string: s) }
        return nil
    }
    /// True when the user just signed up on this device and the consent
    /// sheet (role multi-select + marketing toggle + TOS) hasn't been
    /// completed yet. RootView gates on this between AuthView and
    /// AppRouter so first-time iOS users see the same questions web
    /// users do.
    var needsSignupConsent = false

    private var supabase: SupabaseClient { SupabaseManager.shared.client }
    private let redirectURL = URL(string: "seatbee://auth/callback")!

    init() {
        Task {
            await restoreSession()
        }
    }

    // MARK: - Session Management

    func restoreSession() async {
        do {
            let session = try await supabase.auth.session
            currentUser = session.user
            Task { await recordPageViewPing() }
            Task { await backfillSignupPlatformIfMissing() }
        } catch {
            currentUser = nil
        }
    }

    /// Backfill `profiles.signup_platform = 'ios'` for users whose
    /// column is null. The original write in `writeIOSSignupProfileIfNew`
    /// is gated by `accountAgeSec < 60`, so users who signed up before
    /// the column was wired (or whose first-write failed transiently)
    /// stay null forever and don't get the iOS badge in the admin
    /// dashboard. This top-up runs on every session restore but only
    /// writes when the value is currently null — so a user who legit
    /// signed up on web and later signed in on iOS keeps their 'web'
    /// signup_platform. Failure (offline, RLS, column missing) is silent.
    private func backfillSignupPlatformIfMissing() async {
        guard let user = currentUser else { return }
        struct Row: Decodable {
            let signup_platform: String?
            let signup_source: String?
        }
        do {
            let row: Row = try await supabase
                .from("profiles")
                .select("signup_platform, signup_source")
                .eq("id", value: user.id.uuidString)
                .single()
                .execute()
                .value
            // Only patch null columns — a user who legit signed up on web
            // and later signed in on iOS keeps their original web platform
            // + utm-derived source.
            let patchPlatform = row.signup_platform == nil
            let patchSource = row.signup_source == nil
            guard patchPlatform || patchSource else { return }
            struct Patch: Encodable {
                let signup_platform: String?
                let signup_source: String?
            }
            let patch = Patch(
                signup_platform: patchPlatform ? "ios" : nil,
                signup_source: patchSource ? "app_store" : nil
            )
            try await supabase
                .from("profiles")
                .update(patch)
                .eq("id", value: user.id.uuidString)
                .execute()
        } catch {
            // Don't surface — backfill is best-effort, not load-bearing
            print("[Auth] signup_platform backfill skipped: \(error)")
        }
    }

    /// Fire-and-forget ping to the web's page-views endpoint. The
    /// admin dashboard joins city + country onto user records by
    /// taking the most recent page_views row per user_id; web pings
    /// it on every page load, but iOS doesn't load web pages, so
    /// iOS-only users used to show no location. Sending this ping
    /// once per session (sign-in OR app launch with a restored
    /// session) closes the gap. City + country are derived
    /// server-side from Vercel's `x-vercel-ip-city` /
    /// `x-vercel-ip-country` headers — no Core Location, no permission
    /// prompts, no Privacy Manifest changes. Failure (offline,
    /// endpoint down) is silent — location is nice-to-have, not
    /// load-bearing.
    private func recordPageViewPing() async {
        guard let userId = currentUser?.id.uuidString else { return }
        guard let url = URL(string: "https://www.seatbee.app/api/admin?resource=page-views") else { return }
        let payload: [String: Any] = [
            "events": [[
                "sessionId": UUID().uuidString,
                "pagePath": "ios:app-session",
                "userId": userId,
            ]]
        ]
        guard let body = try? JSONSerialization.data(withJSONObject: payload) else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // Endpoint's bot filter rejects UAs matching bot|crawl|spider|...
        // "Seatbee-iOS" doesn't match, but make the UA explicit so it's
        // identifiable in any future server-side filtering.
        request.setValue("Seatbee-iOS/1.0", forHTTPHeaderField: "User-Agent")
        request.httpBody = body
        _ = try? await URLSession.shared.data(for: request)
    }

    // MARK: - Profile (web parity — src/hooks/useAuth.jsx)
    //
    // After every successful auth, mirror what web writes to the profiles
    // table. The Supabase trigger on auth.users → profiles already
    // creates the row; we just .update() the columns the iOS client owns:
    //   - signup_platform: 'ios'   (replaces web's 'web' for this user)
    //   - tos_agreed_at: now       (Apple/Google/OTP imply TOS — link in
    //                                the consent sheet for #3 backs this up)
    //   - email_marketing_opt_in: true (matches the pre-checked toggle
    //     the user sees on the SignupConsentView a moment later — and
    //     web parity, which writes true at signup time. The consent
    //     sheet's Continue button overwrites with the user's actual
    //     choice; this default just covers the dismiss-without-submit
    //     edge case so the visual state never lies to the user.)
    //   - user_roles: []           (collected by the post-auth role sheet)
    //
    // Gated by `accountAgeSec < 60` so re-auth on returning sessions never
    // resets the user's later settings choices. Mirrors useAuth.jsx
    // `isNewUser` check (~60 s window).
    private func writeIOSSignupProfileIfNew(appleFullName: String? = nil, skipConsent: Bool = false) async {
        guard let user = currentUser else { return }
        let ageSec = Date().timeIntervalSince(user.createdAt)
        guard ageSec < 60 else { return }
        // For Apple sign-ins we skip the consent sheet (Guideline 4 requires
        // we never re-ask for name/email after SIWA). Google and email
        // sign-ups still see the sheet.
        if !skipConsent {
            await MainActor.run { self.needsSignupConsent = true }
        }

        // Prefer Apple credential name (first-auth only), fall back to
        // Google/OAuth metadata already in userMetadata.
        let nameToStore: String? = appleFullName ?? displayName

        // `profiles.name` is the canonical name column (not `full_name`,
        // which doesn't exist on this schema). Web's admin endpoint reads
        // it via `authNameMap[id]?.full_name || p.name` — OAuth providers
        // fill auth.users metadata, but email-magic-link users only have
        // the value we write here.
        struct ProfilePayload: Encodable {
            let signup_platform: String
            let signup_source: String
            let tos_agreed_at: String
            let email_marketing_opt_in: Bool
            let user_roles: [String]
            let name: String?
        }
        let payload = ProfilePayload(
            signup_platform: "ios",
            signup_source: "app_store",
            tos_agreed_at: ISO8601DateFormatter().string(from: Date()),
            email_marketing_opt_in: true,
            user_roles: [],
            name: nameToStore
        )
        // Race: Supabase's auth.users → profiles trigger creates the
        // initial profile row asynchronously. iOS sign-in is fast
        // enough (especially Apple) that this .update() can fire
        // before the row exists, matching zero rows and silently
        // doing nothing — no error thrown, just no write. Symptom:
        // newly-signed-up iOS users land in the admin dashboard with
        // null signup_platform / tos_agreed_at / etc. forever.
        //
        // Retry up to 4 times at 300ms intervals so the trigger has
        // a ~1.2s window to land. .select() returns the affected
        // rows so we can detect the zero-row case and retry.
        struct ResponseRow: Decodable { let id: String }
        for attempt in 0..<4 {
            do {
                let rows: [ResponseRow] = try await supabase
                    .from("profiles")
                    .update(payload)
                    .eq("id", value: user.id.uuidString)
                    .select("id")
                    .execute()
                    .value
                if !rows.isEmpty {
                    print("[Auth] iOS profile signup row written for \(user.email ?? user.id.uuidString) on attempt \(attempt + 1)")
                    return
                }
                print("[Auth] iOS profile write affected 0 rows (attempt \(attempt + 1)/4) — profiles trigger probably hasn't landed yet")
            } catch {
                print("[Auth] iOS profile write attempt \(attempt + 1) failed: \(error)")
            }
            try? await Task.sleep(nanoseconds: 300_000_000)
        }
        print("[Auth] iOS profile write failed after 4 attempts — backfillSignupPlatformIfMissing will catch it on next session")
    }

    /// Subset of profiles columns iOS reads in Settings. Mirrors the
    /// fields web's AccountSettings binds to (App.jsx ~25241–25272).
    struct UserProfile: Decodable {
        let user_roles: [String]?
        let email_marketing_opt_in: Bool?
    }

    /// Fetches the active user's profile row. Returns nil when there
    /// is no signed-in user or the row doesn't exist (legacy / pre-trigger).
    /// Intentionally omits name — fetched separately via loadFullName()
    /// so a missing column never breaks role/marketing loading.
    func loadProfile() async -> UserProfile? {
        guard let user = currentUser else { return nil }
        do {
            let p: UserProfile = try await supabase
                .from("profiles")
                .select("user_roles, email_marketing_opt_in")
                .eq("id", value: user.id.uuidString)
                .single()
                .execute()
                .value
            return p
        } catch {
            print("[Auth] loadProfile failed: \(error)")
            return nil
        }
    }

    /// Fetches `name` from the profiles table. Separate from loadProfile
    /// so a transient failure never breaks role/marketing loading.
    func loadFullName() async -> String? {
        guard let user = currentUser else { return nil }
        struct NameRow: Decodable { let name: String? }
        do {
            let row: NameRow = try await supabase
                .from("profiles")
                .select("name")
                .eq("id", value: user.id.uuidString)
                .single()
                .execute()
                .value
            return row.name
        } catch {
            // Fail silently — falls back to OAuth metadata in the UI.
            return nil
        }
    }

    func updateDisplayName(_ name: String) async {
        guard let user = currentUser, !name.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        struct Payload: Encodable { let name: String }
        do {
            try await supabase
                .from("profiles")
                .update(Payload(name: name))
                .eq("id", value: user.id.uuidString)
                .execute()
        } catch {
            print("[Auth] display name save failed: \(error)")
        }
    }

    /// Live-write the marketing opt-in toggle from Settings. Mirrors
    /// web AccountSettings line 25016.
    func updateEmailMarketingOptIn(_ value: Bool) async {
        guard let user = currentUser else { return }
        struct Payload: Encodable { let email_marketing_opt_in: Bool }
        do {
            try await supabase
                .from("profiles")
                .update(Payload(email_marketing_opt_in: value))
                .eq("id", value: user.id.uuidString)
                .execute()
        } catch {
            print("[Auth] marketing opt-in save failed: \(error)")
        }
    }

    /// Live-write the role multi-select from Settings. Mirrors web
    /// AccountSettings line 25004.
    func updateUserRoles(_ roles: [String]) async {
        guard let user = currentUser else { return }
        struct Payload: Encodable { let user_roles: [String] }
        do {
            try await supabase
                .from("profiles")
                .update(Payload(user_roles: roles))
                .eq("id", value: user.id.uuidString)
                .execute()
        } catch {
            print("[Auth] roles save failed: \(error)")
        }
    }

    /// Called by SignupConsentView's Continue button. Pushes the user's
    /// role + marketing-opt-in choices into the profiles row and clears
    /// the consent gate so the rest of the app loads.
    ///
    /// Uses the same retry-with-select pattern as writeIOSSignupProfileIfNew()
    /// because this fires within seconds of signup — the Supabase auth trigger
    /// that creates the profiles row can still be in flight, causing a silent
    /// zero-row update. Without retry, roles were silently lost for users who
    /// completed consent quickly.
    func completeSignupConsent(userRoles: [String], emailMarketingOptIn: Bool, displayName: String? = nil) async {
        guard let user = currentUser else { return }
        struct ConsentPayload: Encodable {
            let user_roles: [String]
            let email_marketing_opt_in: Bool
            let name: String?
        }
        let nameToStore = displayName.flatMap { $0.trimmingCharacters(in: .whitespaces).isEmpty ? nil : $0 }
        let payload = ConsentPayload(
            user_roles: userRoles,
            email_marketing_opt_in: emailMarketingOptIn,
            name: nameToStore
        )
        struct ResponseRow: Decodable { let id: String }
        for attempt in 0..<4 {
            do {
                let rows: [ResponseRow] = try await supabase
                    .from("profiles")
                    .update(payload)
                    .eq("id", value: user.id.uuidString)
                    .select("id")
                    .execute()
                    .value
                if !rows.isEmpty {
                    print("[Auth] consent saved for \(user.email ?? user.id.uuidString) on attempt \(attempt + 1)")
                    await MainActor.run { self.needsSignupConsent = false }
                    return
                }
                print("[Auth] consent write affected 0 rows (attempt \(attempt + 1)/4) — profiles trigger probably hasn't landed yet")
            } catch {
                print("[Auth] consent save attempt \(attempt + 1) failed: \(error)")
            }
            try? await Task.sleep(nanoseconds: 300_000_000)
        }
        // All retries exhausted — clear the gate anyway so the user
        // isn't stuck. They can edit roles from Settings later.
        print("[Auth] consent save failed after 4 attempts — clearing gate, roles editable in Settings")
        await MainActor.run { self.needsSignupConsent = false }
    }

    // MARK: - Apple Sign In

    func signInWithApple(credential: ASAuthorizationAppleIDCredential) async {
        isLoading = true
        error = nil

        guard let identityToken = credential.identityToken,
              let tokenString = String(data: identityToken, encoding: .utf8) else {
            error = "Failed to get Apple identity token"
            isLoading = false
            return
        }

        do {
            let session = try await supabase.auth.signInWithIdToken(
                credentials: .init(
                    provider: .apple,
                    idToken: tokenString
                )
            )
            currentUser = session.user
            // Apple only provides fullName on the first authentication.
            // Capture it immediately and persist to the profile row.
            let appleName: String? = {
                guard let fn = credential.fullName else { return nil }
                let parts = [fn.givenName, fn.familyName].compactMap { $0 }.filter { !$0.isEmpty }
                return parts.isEmpty ? nil : parts.joined(separator: " ")
            }()
            // App Store Guideline 4: Apple sign-in must not ask the user
            // for name or email afterwards. Skip SignupConsentView entirely
            // and auto-complete consent with defaults. The user can change
            // roles and marketing prefs from Settings later.
            await writeIOSSignupProfileIfNew(appleFullName: appleName, skipConsent: true)
            Task { await recordPageViewPing() }
        } catch is CancellationError {
            // Task cancelled — not a real error.
        } catch let e {
            self.error = e.localizedDescription
        }

        isLoading = false
    }

    // MARK: - Google Sign In (OAuth via ASWebAuthenticationSession)

    @MainActor
    func signInWithGoogle() async {
        isLoading = true
        error = nil

        do {
            // Uses ASWebAuthenticationSession — shows a native in-app browser
            // that automatically handles the redirect back to the app
            let session = try await supabase.auth.signInWithOAuth(
                provider: .google,
                redirectTo: redirectURL
            ) { session in
                // Prefer ephemeral session so user isn't auto-logged into
                // a previous Google account
                session.prefersEphemeralWebBrowserSession = true
            }
            currentUser = session.user
            await writeIOSSignupProfileIfNew()
            Task { await recordPageViewPing() }
        } catch is CancellationError {
            // Task cancelled — not a real error.
        } catch let e {
            self.error = e.localizedDescription
        }

        isLoading = false
    }

    // MARK: - Magic Link (Email)

    func sendMagicLink(email: String) async -> Bool {
        isLoading = true
        error = nil

        do {
            try await supabase.auth.signInWithOTP(
                email: email,
                redirectTo: redirectURL
            )
            isLoading = false
            return true
        } catch is CancellationError {
            isLoading = false
            return false
        } catch let e {
            self.error = e.localizedDescription
            isLoading = false
            return false
        }
    }

    // MARK: - Deep Link Handling

    func handleDeepLink(url: URL) async {
        do {
            let session = try await supabase.auth.session(from: url)
            currentUser = session.user
            await writeIOSSignupProfileIfNew()
            Task { await recordPageViewPing() }
        } catch {
            self.error = "Failed to complete sign in"
        }
    }

    // MARK: - Sign Out

    func signOut() async {
        do {
            try await supabase.auth.signOut()
            currentUser = nil
        } catch {
            self.error = "Failed to sign out"
        }
    }

    // MARK: - Account Deletion (App Store 5.1.1(v))
    //
    // Calls /api/delete-account on the web backend, which verifies the
    // bearer token, then runs the same delete sequence the admin
    // panel uses (variants → FK cleanups → master plans → auth user).
    // The endpoint is self-serve — Apple requires the user be able to
    // delete their own account in-app, not via email-support.
    //
    // On 200, signs out locally so the app returns to the auth screen.

    enum DeleteAccountError: LocalizedError {
        case unauthorized
        case server(String)
        case network(Error)

        var errorDescription: String? {
            switch self {
            case .unauthorized:    return "Please sign in again before deleting your account."
            case .server(let m):   return m
            case .network(let e):  return e.localizedDescription
            }
        }
    }

    func deleteAccount() async throws {
        guard let token = await accessToken else {
            throw DeleteAccountError.unauthorized
        }
        guard let url = URL(string: "https://www.seatbee.app/api/delete-account") else {
            throw DeleteAccountError.server("Invalid URL")
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 30

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: req)
        } catch {
            throw DeleteAccountError.network(error)
        }
        guard let http = response as? HTTPURLResponse else {
            throw DeleteAccountError.server("Invalid response")
        }
        switch http.statusCode {
        case 200:
            // Server already nuked the auth record + all the data. Just
            // clear local state so the app routes back to auth.
            currentUser = nil
            try? await supabase.auth.signOut()
        case 401:
            throw DeleteAccountError.unauthorized
        default:
            struct ErrorBody: Decodable { let error: String? }
            let msg = (try? JSONDecoder().decode(ErrorBody.self, from: data))?.error
                ?? "Server error (\(http.statusCode))"
            throw DeleteAccountError.server(msg)
        }
    }

    // MARK: - Access Token

    var accessToken: String? {
        get async {
            try? await supabase.auth.session.accessToken
        }
    }
}

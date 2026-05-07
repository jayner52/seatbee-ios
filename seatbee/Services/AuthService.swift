import Foundation
import AuthenticationServices
import Supabase

@Observable
final class AuthService {
    var currentUser: User?
    var isAuthenticated: Bool { currentUser != nil }
    var isLoading = false
    var error: String?
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
        } catch {
            currentUser = nil
        }
    }

    // MARK: - Profile (web parity — src/hooks/useAuth.jsx)
    //
    // After every successful auth, mirror what web writes to the profiles
    // table. The Supabase trigger on auth.users → profiles already
    // creates the row; we just .update() the columns the iOS client owns:
    //   - signup_platform: 'ios'   (replaces web's 'web' for this user)
    //   - tos_agreed_at: now       (Apple/Google/OTP imply TOS — link in
    //                                the consent sheet for #3 backs this up)
    //   - email_marketing_opt_in: false (default; user can flip in Settings)
    //   - user_roles: []           (collected by the post-auth role sheet)
    //
    // Gated by `accountAgeSec < 60` so re-auth on returning sessions never
    // resets the user's later settings choices. Mirrors useAuth.jsx
    // `isNewUser` check (~60 s window).
    private func writeIOSSignupProfileIfNew() async {
        guard let user = currentUser else { return }
        let ageSec = Date().timeIntervalSince(user.createdAt)
        guard ageSec < 60 else { return }
        // Detected as a brand-new signup → ungate the consent sheet so
        // the user sees role / marketing / TOS questions next.
        await MainActor.run { self.needsSignupConsent = true }

        struct ProfilePayload: Encodable {
            let signup_platform: String
            let tos_agreed_at: String
            let email_marketing_opt_in: Bool
            let user_roles: [String]
        }
        let payload = ProfilePayload(
            signup_platform: "ios",
            tos_agreed_at: ISO8601DateFormatter().string(from: Date()),
            email_marketing_opt_in: false,
            user_roles: []
        )
        do {
            try await supabase
                .from("profiles")
                .update(payload)
                .eq("id", value: user.id.uuidString)
                .execute()
            print("[Auth] iOS profile signup row written for \(user.email ?? user.id.uuidString)")
        } catch {
            // Never block sign-up on a profile write — the user is still
            // authenticated and can use the app. The Settings sheet's
            // role/marketing toggles can backfill later.
            print("[Auth] iOS profile write failed: \(error)")
        }
    }

    /// Subset of profiles columns iOS reads in Settings. Mirrors the
    /// fields web's AccountSettings binds to (App.jsx ~25241–25272).
    struct UserProfile: Decodable {
        let user_roles: [String]?
        let email_marketing_opt_in: Bool?
    }

    /// Fetches the active user's profile row. Returns nil when there
    /// is no signed-in user or the row doesn't exist (legacy / pre-trigger).
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
    func completeSignupConsent(userRoles: [String], emailMarketingOptIn: Bool) async {
        guard let user = currentUser else { return }
        struct ConsentPayload: Encodable {
            let user_roles: [String]
            let email_marketing_opt_in: Bool
        }
        let payload = ConsentPayload(
            user_roles: userRoles,
            email_marketing_opt_in: emailMarketingOptIn
        )
        do {
            try await supabase
                .from("profiles")
                .update(payload)
                .eq("id", value: user.id.uuidString)
                .execute()
        } catch {
            // Don't block onboarding on a profile write — user can still
            // edit role/marketing from Settings later.
            print("[Auth] consent save failed: \(error)")
        }
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
            await writeIOSSignupProfileIfNew()
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

    // MARK: - Access Token

    var accessToken: String? {
        get async {
            try? await supabase.auth.session.accessToken
        }
    }
}

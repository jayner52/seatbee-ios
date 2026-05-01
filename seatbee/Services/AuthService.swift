import Foundation
import AuthenticationServices
import Supabase

@Observable
final class AuthService {
    var currentUser: User?
    var isAuthenticated: Bool { currentUser != nil }
    var isLoading = false
    var error: String?

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

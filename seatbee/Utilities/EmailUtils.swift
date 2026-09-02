import Foundation

/// Email helpers. Kept deliberately small: the app had no email validation of
/// any kind before this (ShareView.sendInvite only checked non-empty and let
/// the server decide), so these two are the whole surface.
enum EmailUtils {

    /// Apple's Hide My Email forwarding domain.
    ///
    /// `SignInWithAppleButton` requests `.email`, so Apple always hands back an
    /// address — but for users who tapped "Hide My Email" it's a relay like
    /// `a1b2c3d4e5@privaterelay.appleid.com`, and Supabase stores that verbatim
    /// as `auth.users.email`. It forwards today, and stops the moment the user
    /// turns forwarding off or revokes the app, so it isn't an address we can
    /// rely on for reaching someone later.
    private static let appleRelayDomain = "@privaterelay.appleid.com"

    /// True when this is an Apple private-relay address rather than the user's
    /// own inbox. Case-insensitive: Apple lowercases these, but the value has
    /// round-tripped through auth metadata, so don't assume.
    static func isAppleRelay(_ email: String?) -> Bool {
        guard let email, !email.isEmpty else { return false }
        return email.lowercased().hasSuffix(appleRelayDomain)
    }

    /// True when we have no address we can actually reach this user at:
    /// either no email at all, or a relay forwarder.
    static func isUnreachable(_ email: String?) -> Bool {
        guard let email, !email.trimmingCharacters(in: .whitespaces).isEmpty else { return true }
        return isAppleRelay(email)
    }

    /// Shape check only, no deliverability claim. Intentionally the same
    /// expression the web capture endpoints use (`api/admin.js`
    /// blog-subscribe / lead-subscribe) so an address accepted on iOS is
    /// accepted on web and vice versa.
    static func isValidFormat(_ email: String) -> Bool {
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        return trimmed.range(of: "^[^\\s@]+@[^\\s@]+\\.[^\\s@]+$", options: .regularExpression) != nil
    }

    /// Normalised form we store: trimmed and lowercased, so admin-side
    /// dedupe against `blog_subscribers` (which compares lowercased) lines up.
    static func normalize(_ email: String) -> String {
        email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

import Foundation
import Security

// MARK: - Shared between the Seatbee app target and the SeatbeeWidget extension.
// IMPORTANT: this file must be a member of BOTH targets (app + widget).
//
// The widget can't carry the app's Supabase refresh token: Supabase rotates
// refresh tokens on use, so the app and widget refreshing the same token would
// invalidate each other and log the user out. Instead, the app mints a narrow,
// read-only "widget token" from the backend (api/admin?resource=widget-token)
// while signed in as an admin, and stashes it here — in a keychain item shared
// across the two targets via a keychain access group. The widget only reads it.

enum WidgetShared {
    /// Fully-qualified keychain access group. Must match the
    /// `keychain-access-groups` entitlement on BOTH targets, which is written
    /// as `$(AppIdentifierPrefix)com.shayan.seatbee.shared`. `$(AppIdentifierPrefix)`
    /// expands to the team id (`L67AL7FS38.`) at build time; SecItem APIs need
    /// the fully-qualified value, so we hardcode the team prefix here.
    static let keychainAccessGroup = "L67AL7FS38.com.shayan.seatbee.shared"
    static let keychainService = "com.shayan.seatbee.widget"
    static let tokenAccount = "widgetToken"

    /// Hit `www` directly. The bare `seatbee.app` 307-redirects, and URLSession
    /// strips Authorization/custom headers across a cross-origin redirect — so
    /// requests would arrive unauthenticated (see AppConfig.aiAPIBaseURL note).
    static let metricsURL = URL(string: "https://www.seatbee.app/api/admin?resource=widget-metrics")!
    static let mintTokenURL = URL(string: "https://www.seatbee.app/api/admin?resource=widget-token")!
}

/// Minimal keychain wrapper for the shared widget token.
enum WidgetKeychain {
    private static func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: WidgetShared.keychainService,
            kSecAttrAccount as String: WidgetShared.tokenAccount,
            kSecAttrAccessGroup as String: WidgetShared.keychainAccessGroup,
        ]
    }

    static func saveToken(_ token: String) {
        SecItemDelete(baseQuery() as CFDictionary)
        var add = baseQuery()
        add[kSecValueData as String] = Data(token.utf8)
        // AfterFirstUnlock so the widget can read it after a reboot+unlock,
        // including on the lock screen.
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(add as CFDictionary, nil)
    }

    static func readToken() -> String? {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess,
              let data = out as? Data,
              let token = String(data: data, encoding: .utf8) else { return nil }
        return token
    }

    static func deleteToken() {
        SecItemDelete(baseQuery() as CFDictionary)
    }
}

import Foundation
import Security
import WidgetKit

/// Mints the read-only widget token while the user is a signed-in admin,
/// stashes it in the shared keychain, and nudges WidgetKit to refresh.
/// Best-effort and silent: non-admins receive 403 from the backend and end up
/// with no token, so their widget shows a signed-out state.
///
/// Wired from `AuthService.currentUser.didSet` — minted on sign-in / launch
/// with a restored session, cleared on sign-out.
///
/// ⚠️ The keychain constants below MUST stay identical to
/// `SeatbeeWidget/WidgetSharedAuth.swift` (the widget reads from the same item).
/// They're duplicated rather than shared because Xcode's synchronized folder
/// groups make a single file awkward to compile into both targets.
enum WidgetTokenProvider {
    // MARK: - Shared constants (keep in sync with WidgetSharedAuth.swift)
    private static let keychainAccessGroup = "L67AL7FS38.com.shayan.seatbee.shared"
    private static let keychainService = "com.shayan.seatbee.widget"
    private static let tokenAccount = "widgetToken"
    private static let mintTokenURL = URL(string: "https://www.seatbee.app/api/admin?resource=widget-token")!

    private static let lastMintKey = "widgetTokenLastMintEpoch"
    /// Re-mint when the cached token is older than this. Backend TTL is 90d.
    private static let remintAfter: TimeInterval = 30 * 24 * 60 * 60

    // MARK: - API

    /// Mint only if we have no token or the cached one is getting old.
    static func refreshIfNeeded() async {
        let lastMint = UserDefaults.standard.double(forKey: lastMintKey)
        let age = Date().timeIntervalSince1970 - lastMint
        if readToken() != nil && age < remintAfter { return }
        await mint()
    }

    static func mint() async {
        guard let accessToken = await AuthService().accessToken else { return }

        var request = URLRequest(url: mintTokenURL)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            // 403 = not an admin → leave the widget signed-out, no token stored.
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return }
            struct MintResponse: Decodable { let token: String }
            let decoded = try JSONDecoder().decode(MintResponse.self, from: data)
            saveToken(decoded.token)
            UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: lastMintKey)
            WidgetCenter.shared.reloadAllTimelines()
        } catch {
            // Best-effort — retried on the next launch / auth change.
        }
    }

    /// Revoke the widget's local access. Called on sign-out.
    static func clear() {
        deleteToken()
        UserDefaults.standard.removeObject(forKey: lastMintKey)
        WidgetCenter.shared.reloadAllTimelines()
    }

    // MARK: - Keychain (writes the item the widget reads)

    private static func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: tokenAccount,
            kSecAttrAccessGroup as String: keychainAccessGroup,
        ]
    }

    private static func readToken() -> String? {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess,
              let data = out as? Data,
              let token = String(data: data, encoding: .utf8) else { return nil }
        return token
    }

    private static func saveToken(_ token: String) {
        SecItemDelete(baseQuery() as CFDictionary)
        var add = baseQuery()
        add[kSecValueData as String] = Data(token.utf8)
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(add as CFDictionary, nil)
    }

    private static func deleteToken() {
        SecItemDelete(baseQuery() as CFDictionary)
    }
}

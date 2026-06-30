import Foundation
import WidgetKit

/// Mints the read-only widget token (see `WidgetShared`) while the user is a
/// signed-in admin, stashes it in the shared keychain, and nudges WidgetKit to
/// refresh. Best-effort and silent: non-admins receive 403 from the backend and
/// simply end up with no token, so their widget shows a signed-out state.
///
/// Wired from `AuthService.currentUser.didSet` — minted on sign-in / launch
/// with a restored session, cleared on sign-out.
enum WidgetTokenProvider {
    private static let lastMintKey = "widgetTokenLastMintEpoch"
    /// Re-mint when the cached token is older than this. Backend TTL is 90d,
    /// so 30d gives a comfortable margin while keeping mints rare.
    private static let remintAfter: TimeInterval = 30 * 24 * 60 * 60

    /// Mint only if we have no token or the cached one is getting old.
    static func refreshIfNeeded() async {
        let lastMint = UserDefaults.standard.double(forKey: lastMintKey)
        let age = Date().timeIntervalSince1970 - lastMint
        if WidgetKeychain.readToken() != nil && age < remintAfter { return }
        await mint()
    }

    static func mint() async {
        guard let accessToken = await AuthService().accessToken else { return }

        var request = URLRequest(url: WidgetShared.mintTokenURL)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            // 403 = not an admin → leave the widget signed-out, no token stored.
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return }
            struct MintResponse: Decodable { let token: String }
            let decoded = try JSONDecoder().decode(MintResponse.self, from: data)
            WidgetKeychain.saveToken(decoded.token)
            UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: lastMintKey)
            WidgetCenter.shared.reloadAllTimelines()
        } catch {
            // Best-effort — the app will retry on the next launch / auth change.
        }
    }

    /// Revoke the widget's local access. Called on sign-out.
    static func clear() {
        WidgetKeychain.deleteToken()
        UserDefaults.standard.removeObject(forKey: lastMintKey)
        WidgetCenter.shared.reloadAllTimelines()
    }
}

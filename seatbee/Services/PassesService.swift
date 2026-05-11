import Foundation

// Wraps web's /api/passes endpoint:
//   GET                       — list user's passes + summary
//   POST  { planId, passId? } — redeem one pass for a plan, sets plan.tier
//
// Phase 1: read+apply only. Purchase flow (Apple IAP) is Phase 2 (Shayan).

final class PassesService {
    private let baseURL = AppConfig.passesAPIBaseURL

    private static let dateDecoder: JSONDecoder = {
        let d = JSONDecoder()
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let isoNoFrac = ISO8601DateFormatter()
        isoNoFrac.formatOptions = [.withInternetDateTime]
        d.dateDecodingStrategy = .custom { decoder in
            let c = try decoder.singleValueContainer()
            let s = try c.decode(String.self)
            if let date = iso.date(from: s) ?? isoNoFrac.date(from: s) { return date }
            throw DecodingError.dataCorruptedError(in: c, debugDescription: "Bad ISO date: \(s)")
        }
        return d
    }()

    enum PassesError: LocalizedError {
        case unauthorized
        case noAvailablePasses
        case alreadyHasPass(String)
        case planNotFound
        case planOwnerMismatch
        case server(String)
        case network(Error)

        var errorDescription: String? {
            switch self {
            case .unauthorized:           return "Please sign in to manage passes."
            case .noAvailablePasses:      return "No available passes. Purchase one to continue."
            case .alreadyHasPass(let m):  return m
            case .planNotFound:           return "Plan not found."
            case .planOwnerMismatch:      return "This plan does not belong to your account."
            case .server(let m):          return m
            case .network(let e):         return e.localizedDescription
            }
        }
    }

    // MARK: - GET passes

    func fetchPasses() async throws -> PassesResponse {
        guard let url = URL(string: baseURL) else { throw PassesError.server("Invalid passes URL") }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token = await AuthService().accessToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        } else {
            throw PassesError.unauthorized
        }

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw PassesError.network(error)
        }

        guard let http = response as? HTTPURLResponse else { throw PassesError.server("Invalid response") }
        switch http.statusCode {
        case 200:
            do {
                return try Self.dateDecoder.decode(PassesResponse.self, from: data)
            } catch {
                throw PassesError.server("Could not parse passes response: \(error.localizedDescription)")
            }
        case 401:
            throw PassesError.unauthorized
        default:
            let msg = (try? JSONDecoder().decode(ErrorBody.self, from: data))?.error
                ?? "Server error (\(http.statusCode))"
            throw PassesError.server(msg)
        }
    }

    // MARK: - POST redeem

    /// Apply a pass to a plan. If `passId` is nil, the server picks the
    /// best available pass (prefers regular Event Passes over Grand passes
    /// to avoid wasting the higher-tier one).
    func redeemPass(planId: String, passId: String? = nil) async throws -> RedeemPassResponse {
        guard let url = URL(string: baseURL) else { throw PassesError.server("Invalid passes URL") }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token = await AuthService().accessToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        } else {
            throw PassesError.unauthorized
        }

        var body: [String: Any] = ["planId": planId]
        if let passId { body["passId"] = passId }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw PassesError.network(error)
        }

        guard let http = response as? HTTPURLResponse else { throw PassesError.server("Invalid response") }

        switch http.statusCode {
        case 200:
            do {
                return try Self.dateDecoder.decode(RedeemPassResponse.self, from: data)
            } catch {
                throw PassesError.server("Could not parse redeem response: \(error.localizedDescription)")
            }
        case 400:
            let body = try? JSONDecoder().decode(ErrorBody.self, from: data)
            if body?.code == "ALREADY_HAS_PASS" {
                throw PassesError.alreadyHasPass(body?.error ?? "This event already has a pass.")
            }
            if body?.code == "NO_PASSES" {
                throw PassesError.noAvailablePasses
            }
            throw PassesError.server(body?.error ?? "Bad request")
        case 401:
            throw PassesError.unauthorized
        case 403:
            throw PassesError.planOwnerMismatch
        case 404:
            throw PassesError.planNotFound
        default:
            let msg = (try? JSONDecoder().decode(ErrorBody.self, from: data))?.error
                ?? "Server error (\(http.statusCode))"
            throw PassesError.server(msg)
        }
    }

    // MARK: - POST redeem gift code
    //
    // Web parity: POST /api/redeem-gift-code with `{code}`. Server
    // validates the SEAT-XXXX-XXXX code, transfers ownership of the
    // pass from the gifter to the signed-in user, and returns
    // metadata for the success modal (pass type, expiry, gifter
    // name). The pass lands in the recipient's available inventory —
    // it's NOT auto-applied to a plan; the user picks a plan via
    // the normal Apply flow afterwards.
    //
    // Server enforces a per-user rate limit (20 attempts/hour) plus
    // single-use semantics on the underlying row.

    struct RedeemGiftCodeResponse: Codable {
        let success: Bool
        let passType: String?       // "single" | "signature_pass" | etc
        let expiresAt: Date?
        let gifterName: String?     // "Jane S." style (nil if self-gift)
        let alreadyOwned: Bool?     // true if the user already owned this pass
        let message: String?

        enum CodingKeys: String, CodingKey {
            case success, passType, gifterName, alreadyOwned, message
            case expiresAt = "expiresAt"
        }
    }

    func redeemGiftCode(_ code: String) async throws -> RedeemGiftCodeResponse {
        // Web's redeem endpoint lives at /api/redeem-gift-code (NOT
        // /api/passes). Build the URL by swapping the trailing path.
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw PassesError.server("Code is required") }

        // Derive the host from the passes URL so it stays in sync with
        // AppConfig — same env in dev/prod.
        guard let passesURL = URL(string: baseURL),
              var components = URLComponents(url: passesURL, resolvingAgainstBaseURL: false) else {
            throw PassesError.server("Invalid passes URL")
        }
        components.path = "/api/redeem-gift-code"
        guard let url = components.url else {
            throw PassesError.server("Invalid redeem URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token = await AuthService().accessToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        } else {
            throw PassesError.unauthorized
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: ["code": trimmed])

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw PassesError.network(error)
        }

        guard let http = response as? HTTPURLResponse else { throw PassesError.server("Invalid response") }

        switch http.statusCode {
        case 200:
            do {
                return try Self.dateDecoder.decode(RedeemGiftCodeResponse.self, from: data)
            } catch {
                throw PassesError.server("Could not parse redeem response: \(error.localizedDescription)")
            }
        case 400:
            // Server returns a friendly message in `error` for the
            // common cases (invalid / used / expired). Pass it through.
            let body = try? JSONDecoder().decode(ErrorBody.self, from: data)
            throw PassesError.server(body?.error ?? "Invalid code")
        case 401:
            throw PassesError.unauthorized
        case 429:
            throw PassesError.server("Too many attempts. Please wait an hour and try again.")
        default:
            let msg = (try? JSONDecoder().decode(ErrorBody.self, from: data))?.error
                ?? "Server error (\(http.statusCode))"
            throw PassesError.server(msg)
        }
    }

    private struct ErrorBody: Codable {
        let error: String?
        let code: String?
    }

    // MARK: - Promo Code (discount codes, not gift codes)

    /// Validates a promo code with the web backend. If the code gives a
    /// 100% discount, redeems a free pass directly. Partial discounts
    /// can't be applied to StoreKit purchases — returns a message.
    func validateAndRedeemPromo(code: String, packType: String, planId: String?) async throws -> String {
        guard let passesURL = URL(string: baseURL),
              var components = URLComponents(url: passesURL, resolvingAgainstBaseURL: false) else {
            throw PassesError.server("Invalid URL")
        }

        // Step 1: Validate the promo code
        components.path = "/api/create-checkout"
        components.queryItems = [URLQueryItem(name: "action", value: "validate-promo")]
        guard let validateURL = components.url else {
            throw PassesError.server("Invalid validate URL")
        }

        var request = URLRequest(url: validateURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token = await AuthService().accessToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let body: [String: Any] = ["code": code, "packType": packType]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw PassesError.server("Invalid response")
        }

        struct ValidateResponse: Codable {
            let valid: Bool
            let discountType: String?  // "percent" | "fixed" | "free"
            let discountValue: Double?
            let code: String?
            let error: String?
        }

        let result = try JSONDecoder().decode(ValidateResponse.self, from: data)
        guard result.valid else {
            throw PassesError.server(result.error ?? "Invalid promo code")
        }

        // Step 2: If 100% free, redeem directly
        if result.discountType == "free" || (result.discountType == "percent" && result.discountValue == 100) {
            components.path = "/api/passes"
            components.queryItems = [URLQueryItem(name: "action", value: "redeem-free-pass")]
            guard let redeemURL = components.url else {
                throw PassesError.server("Invalid redeem URL")
            }

            var redeemReq = URLRequest(url: redeemURL)
            redeemReq.httpMethod = "POST"
            redeemReq.setValue("application/json", forHTTPHeaderField: "Content-Type")
            if let token = await AuthService().accessToken {
                redeemReq.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            }

            var redeemBody: [String: Any] = ["packType": packType, "promoCodeId": result.code ?? code]
            if let pid = planId { redeemBody["planId"] = pid }
            redeemReq.httpBody = try JSONSerialization.data(withJSONObject: redeemBody)

            let (redeemData, redeemResponse) = try await URLSession.shared.data(for: redeemReq)
            guard let redeemHttp = redeemResponse as? HTTPURLResponse, redeemHttp.statusCode == 200 else {
                let errBody = try? JSONDecoder().decode(ErrorBody.self, from: redeemData)
                throw PassesError.server(errBody?.error ?? "Failed to redeem free pass")
            }

            return "Pass unlocked for free! 🎉"
        }

        // Step 3: Partial discount — can't apply to StoreKit
        if result.discountType == "percent", let val = result.discountValue {
            return "Code valid for \(Int(val))% off — apply it at seatbee.app to use the discount."
        } else if result.discountType == "fixed", let val = result.discountValue {
            return "Code valid for $\(String(format: "%.2f", val / 100)) off — apply it at seatbee.app to use the discount."
        }

        return "Code validated but cannot be applied to in-app purchases."
    }
}

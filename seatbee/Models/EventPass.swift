import Foundation

// Mirror of web's `event_passes` table rows. Decoded from GET /api/passes.
// The API returns ISO strings; we decode as Date via a shared decoder.
//
// pack_type → tier mapping (matches api/passes.js:304):
//   single, duo, pro          → Event Pass tier (250 guests)
//   signature_pass            → Signature Pass tier (500 guests)
//   pro_pass_single           → Grand Event Pass tier (1,000 guests)

struct EventPass: Codable, Identifiable, Hashable {
    let id: String
    let status: String              // "available", "redeemed", "expired"
    let purchasedAt: Date?
    let expiresAt: Date?
    let packType: String
    let amountPaidCents: Int?
    let redeemedAt: Date?
    let redeemedForPlanId: String?
    let giftCode: String?
    let seatingPlans: RedeemedPlanSummary?

    struct RedeemedPlanSummary: Codable, Hashable {
        let id: String?
        let name: String?
        let deletedAt: Date?

        enum CodingKeys: String, CodingKey {
            case id, name
            case deletedAt = "deleted_at"
        }
    }

    enum CodingKeys: String, CodingKey {
        case id, status
        case purchasedAt = "purchased_at"
        case expiresAt = "expires_at"
        case packType = "pack_type"
        case amountPaidCents = "amount_paid_cents"
        case redeemedAt = "redeemed_at"
        case redeemedForPlanId = "redeemed_for_plan_id"
        case giftCode = "gift_code"
        case seatingPlans = "seating_plans"
    }

    var tier: PlanTier {
        switch packType {
        case "pro_pass_single": return .proPass
        case "signature_pass":  return .signaturePass
        // single, duo, pro and anything else are Event-Pass-tier
        default:                return .eventPass
        }
    }

    var isAvailable: Bool {
        guard status == "available" else { return false }
        if let exp = expiresAt, exp <= Date() { return false }
        return true
    }

    var isExpiringSoon: Bool {
        guard isAvailable, let exp = expiresAt else { return false }
        let thirtyDays: TimeInterval = 30 * 24 * 60 * 60
        return exp.timeIntervalSinceNow < thirtyDays
    }
}

struct PassesSummary: Codable, Hashable {
    let available: Int
    let redeemed: Int
    let expired: Int
    let total: Int

    static let empty = PassesSummary(available: 0, redeemed: 0, expired: 0, total: 0)
}

struct PassesResponse: Codable {
    let passes: [EventPass]
    /// Passes the signed-in user has GIFTED OUT — populated by the
    /// server side-query at api/passes.js line 145-150 (joins
    /// profiles on user_id to get the current owner's email/name).
    /// `giftRedeemedAt == nil` means the gift link is out there but
    /// the recipient hasn't claimed it yet; `!= nil` means claimed.
    let giftedPasses: [GiftedPass]?
    let summary: PassesSummary
    let nextExpiry: Date?

    enum CodingKeys: String, CodingKey {
        case passes, summary, giftedPasses
        case nextExpiry = "nextExpiry"
    }

    static let empty = PassesResponse(passes: [], giftedPasses: [], summary: .empty, nextExpiry: nil)

    /// Available passes grouped by tier, ordered Event → Signature → Grand.
    func availableByTier() -> [(tier: PlanTier, passes: [EventPass])] {
        let avail = passes.filter { $0.isAvailable }
        return [PlanTier.eventPass, .signaturePass, .proPass].map { tier in
            (tier, avail.filter { $0.tier == tier })
        }
    }
}

// Mirror of the `giftedPasses` array returned by GET /api/passes.
// Each row is a pass the SIGNED-IN user gifted to someone else; the
// pass's user_id has already been transferred to the recipient (via
// /api/redeem-gift-code), and `profiles` is the join showing who has
// it now. Pre-claim, gift_redeemed_at is null and profiles still
// reflects the original owner — the API response is the same shape
// either way; the iOS UI uses giftRedeemedAt to decide which copy
// to show.
struct GiftedPass: Codable, Identifiable, Hashable {
    let id: String
    let giftCode: String?
    let giftRedeemedAt: Date?
    let packType: String
    let purchasedAt: Date?
    let profiles: RecipientProfile?

    struct RecipientProfile: Codable, Hashable {
        let email: String?
        let name: String?
    }

    enum CodingKeys: String, CodingKey {
        case id, profiles
        case giftCode = "gift_code"
        case giftRedeemedAt = "gift_redeemed_at"
        case packType = "pack_type"
        case purchasedAt = "purchased_at"
    }

    var tier: PlanTier {
        switch packType {
        case "pro_pass_single": return .proPass
        case "signature_pass":  return .signaturePass
        default:                return .eventPass
        }
    }

    var isClaimed: Bool { giftRedeemedAt != nil }
}

struct RedeemPassResponse: Codable {
    let success: Bool
    let passId: String?
    let planId: String?
    let expiresAt: Date?
    let tier: String?
    let message: String?
}

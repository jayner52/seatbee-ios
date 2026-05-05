import Foundation

// Mirror of web's TIER_LIMITS in src/App.jsx (~line 152).
// Keep in sync — these are the runtime caps Seatbee enforces per tier.
//
// NOTE: web has a `variants` cap (multiple arrangements per event); iOS does
// not enforce it because iOS does not surface multi-arrangement at all.

enum PlanTier: String, CaseIterable {
    case free
    case eventPass = "event_pass"
    case signaturePass = "signature_pass"
    case proPass = "pro_pass"

    var displayName: String {
        switch self {
        case .free: return "Free"
        case .eventPass: return "Event Pass"
        case .signaturePass: return "Signature Pass"
        case .proPass: return "Grand Event Pass"
        }
    }

    var rank: Int {
        switch self {
        case .free: return 0
        case .eventPass: return 1
        case .signaturePass: return 2
        case .proPass: return 3
        }
    }

    static func from(_ raw: String?) -> PlanTier {
        guard let raw, let t = PlanTier(rawValue: raw) else { return .free }
        return t
    }
}

struct TierLimits {
    let seatedGuests: Int
    let aiGenerate: Bool
    let aiFloorPlan: Bool
    let expiryDays: Int?

    static func limits(for tier: PlanTier) -> TierLimits {
        switch tier {
        case .free:
            return .init(seatedGuests: 100, aiGenerate: false, aiFloorPlan: true, expiryDays: nil)
        case .eventPass:
            return .init(seatedGuests: 250, aiGenerate: true, aiFloorPlan: true, expiryDays: 180)
        case .signaturePass:
            return .init(seatedGuests: 500, aiGenerate: true, aiFloorPlan: true, expiryDays: 180)
        case .proPass:
            return .init(seatedGuests: 1000, aiGenerate: true, aiFloorPlan: true, expiryDays: 180)
        }
    }

    static func limits(for rawTier: String?) -> TierLimits {
        limits(for: PlanTier.from(rawTier))
    }
}

import Foundation

// Mirror of web's TIER_LIMITS in src/App.jsx (~line 152).
// Keep in sync — these are the runtime caps Seatbee enforces per tier.
//
// PRICING MIGRATION (2026-05-28): collapsing the three one-time passes
// (event_pass / signature_pass / pro_pass) into a single $9.99/mo
// auto-renewable subscription (`pro`). Legacy enum cases stay during
// the migration window so existing Supabase rows still decode and
// round-trip safely (PARITY.md cardinal rule). Free-tier guest cap
// tightened from 100 → 50 to create real conversion pressure.
//
// NOTE: web has a `variants` cap (multiple arrangements per event); iOS does
// not enforce it because iOS does not surface multi-arrangement at all.

enum PlanTier: String, CaseIterable {
    case free
    case pro                                        // NEW — subscription tier ($9.99/mo)
    case eventPass = "event_pass"                   // LEGACY — pre-2026-05-28 one-time pass
    case signaturePass = "signature_pass"           // LEGACY
    case proPass = "pro_pass"                       // LEGACY

    var displayName: String {
        switch self {
        case .free: return "Free"
        case .pro: return "Seatbee Pro"
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
        case .pro: return 3  // subscription unlocks the full feature set
        }
    }

    /// True if this tier is one of the legacy one-time pass tiers, kept
    /// in the enum so existing Supabase rows decode without error during
    /// the subscription migration window (PARITY.md line 189).
    var isLegacyPass: Bool {
        switch self {
        case .eventPass, .signaturePass, .proPass: return true
        case .free, .pro: return false
        }
    }

    /// Parse a raw tier string, preserving unknown values via a loud log
    /// instead of silent coercion to `.free`. Per PARITY.md line 189, we
    /// never silently default an enum we don't recognise — that's what
    /// caused the 2026-05-03 incident with RuleType. iOS never writes the
    /// `tier` column so unknown raw values round-trip through `SeatingPlan.tier`
    /// (String) untouched; this helper only resolves the runtime enum.
    static func from(_ raw: String?) -> PlanTier {
        guard let raw else { return .free }
        if let t = PlanTier(rawValue: raw) { return t }
        print("[Seatbee] ⚠️ Unknown PlanTier raw value: \(raw) — defaulting to .free for runtime, raw string preserved on plan")
        return .free
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
            // Tightened 100 → 50 on 2026-05-28 alongside the subscription
            // migration. Small events brush the cap and feel the upgrade
            // prompt; previously a 100-guest cap let most weddings glide
            // through without ever seeing the paywall.
            return .init(seatedGuests: 50, aiGenerate: false, aiFloorPlan: true, expiryDays: nil)
        case .pro:
            // Subscription unlocks the full feature set; no expiry —
            // entitlement lives on the user's subscription_status, not on
            // a fixed pass-expiry date.
            return .init(seatedGuests: 1000, aiGenerate: true, aiFloorPlan: true, expiryDays: nil)
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

// MARK: - User Subscription
//
// Cross-app shared shape. Web's Stripe webhook (or iOS's StoreKit /api/apple-iap)
// writes these columns onto the `profiles` table. iOS reads but never writes,
// same contract as the legacy pass columns on `seating_plans` (PARITY.md line 116).
//
// Co-located in this file (rather than a new UserSubscription.swift) to avoid
// a `project.pbxproj` edit which is a high-risk shared file per CLAUDE.md.

enum SubscriptionStatus: String, Codable {
    case active             // currently entitled
    case pastDue = "past_due"   // payment failed, in grace
    case canceled           // user canceled; still entitled until renews_at
    case none               // never subscribed, or expired with no renewal

    static func from(_ raw: String?) -> SubscriptionStatus {
        guard let raw else { return .none }
        if let s = SubscriptionStatus(rawValue: raw) { return s }
        print("[Seatbee] ⚠️ Unknown SubscriptionStatus raw value: \(raw) — treating as .none")
        return .none
    }
}

enum SubscriptionProvider: String, Codable {
    case stripe
    case apple
    case grace              // backend-seeded 30-day grace for pre-migration users

    static func from(_ raw: String?) -> SubscriptionProvider? {
        guard let raw else { return nil }
        if let p = SubscriptionProvider(rawValue: raw) { return p }
        print("[Seatbee] ⚠️ Unknown SubscriptionProvider raw value: \(raw) — preserving raw via nil")
        return nil
    }
}

struct UserSubscription: Codable, Equatable {
    let status: SubscriptionStatus
    let renewsAt: Date?
    let provider: SubscriptionProvider?
    let subscriptionId: String?

    static let none = UserSubscription(status: .none, renewsAt: nil, provider: nil, subscriptionId: nil)

    /// The user is currently entitled to Pro features. `active` is
    /// straightforward; `canceled` keeps entitlement until renews_at
    /// (Apple/Stripe both work this way — user keeps what they paid for).
    /// `past_due` keeps entitlement during the payment-retry grace window.
    var isProEntitled: Bool {
        switch status {
        case .active, .pastDue: return true
        case .canceled:
            // Canceled but paid through renews_at — still entitled until then.
            guard let renewsAt else { return false }
            return Date() < renewsAt
        case .none:
            return false
        }
    }
}

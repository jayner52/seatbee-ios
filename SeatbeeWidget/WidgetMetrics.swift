import Foundation

/// Decodes the slim payload from GET /api/admin?resource=widget-metrics.
struct WidgetMetrics: Codable, Equatable {
    let revenueTodayCents: Int
    let monthRevenueCents: Int
    let totalRevenueCents: Int
    let mrrCents: Int
    let arrCents: Int
    let activeSubs: Int
    let newSubsToday: Int
    let newUsersToday: Int
    let activeTrials: Int
    let newTrialsToday: Int
    let asOf: String?

    /// Used for the widget gallery preview / placeholder.
    static let placeholder = WidgetMetrics(
        revenueTodayCents: 2997,
        monthRevenueCents: 42897,
        totalRevenueCents: 812400,
        mrrCents: 49950,
        arrCents: 599400,
        activeSubs: 50,
        newSubsToday: 3,
        newUsersToday: 17,
        activeTrials: 8,
        newTrialsToday: 2,
        asOf: nil
    )
}

enum MetricFormat {
    /// Compact USD from cents: $0 · $42 · $1.2k · $599k · $1.4M
    static func money(_ cents: Int) -> String {
        let dollars = Double(cents) / 100.0
        let magnitude = abs(dollars)
        let sign = dollars < 0 ? "-" : ""
        switch magnitude {
        case 0:
            return "$0"
        case ..<1_000:
            return "\(sign)$\(Int(dollars.rounded()))"
        case ..<1_000_000:
            let k = magnitude / 1_000
            return k < 10 ? "\(sign)$\(trimmed(k))k" : "\(sign)$\(Int(k.rounded()))k"
        default:
            let m = magnitude / 1_000_000
            return "\(sign)$\(trimmed(m))M"
        }
    }

    /// "+3" style for today's deltas; bare "0" when none.
    static func delta(_ n: Int) -> String { n > 0 ? "+\(n)" : "\(n)" }

    static func plain(_ n: Int) -> String { "\(n)" }

    private static func trimmed(_ value: Double) -> String {
        let s = String(format: "%.1f", value)
        return s.hasSuffix(".0") ? String(s.dropLast(2)) : s
    }
}

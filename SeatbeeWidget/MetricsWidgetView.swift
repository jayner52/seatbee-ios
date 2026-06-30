import SwiftUI
import WidgetKit

enum SBWidgetStyle {
    static let gold = Color(red: 0xC9 / 255, green: 0xA9 / 255, blue: 0x61 / 255)
    static let background = Color(red: 0x14 / 255, green: 0x13 / 255, blue: 0x10 / 255)
    static let label = Color.white.opacity(0.55)
    static let value = Color.white
    static let positive = Color(red: 0x6E / 255, green: 0xD0 / 255, blue: 0x8E / 255)
    static let deepLink = URL(string: "seatbee://admin")
}

struct MetricsWidgetView: View {
    let entry: MetricsEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        if entry.signedOut {
            SignedOutView()
        } else if let metrics = entry.metrics {
            switch family {
            case .systemSmall:
                SmallMetrics(metrics: metrics, stale: entry.stale)
            case .systemLarge:
                LargeMetrics(metrics: metrics, stale: entry.stale, date: entry.date)
            default:
                MediumMetrics(metrics: metrics, stale: entry.stale)
            }
        } else {
            UnavailableView()
        }
    }
}

// MARK: - Building blocks

private struct Tile: View {
    let label: String
    let value: String
    var accent: Color = SBWidgetStyle.value

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased())
                .font(.system(size: 9, weight: .semibold))
                .tracking(0.5)
                .foregroundStyle(SBWidgetStyle.label)
                .lineLimit(1)
            Text(value)
                .font(.system(size: 21, weight: .bold, design: .rounded))
                .foregroundStyle(accent)
                .minimumScaleFactor(0.5)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct Header: View {
    var stale: Bool = false
    var body: some View {
        HStack(spacing: 6) {
            Text("SEATBEE")
                .font(.system(size: 10, weight: .bold))
                .tracking(1.5)
                .foregroundStyle(SBWidgetStyle.gold)
            Text("admin")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(SBWidgetStyle.label)
            Spacer()
            if stale { StaleBadge() }
        }
    }
}

private struct StaleBadge: View {
    var body: some View {
        HStack(spacing: 3) {
            Circle().fill(Color.orange).frame(width: 5, height: 5)
            Text("offline").font(.system(size: 8, weight: .semibold)).foregroundStyle(SBWidgetStyle.label)
        }
    }
}

// MARK: - Families

private struct SmallMetrics: View {
    let metrics: WidgetMetrics
    let stale: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Header(stale: stale)
            Spacer(minLength: 0)
            Text("Revenue today")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(SBWidgetStyle.label)
            Text(MetricFormat.money(metrics.revenueTodayCents))
                .font(.system(size: 30, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
                .minimumScaleFactor(0.5)
                .lineLimit(1)
            Spacer(minLength: 0)
            HStack(spacing: 12) {
                miniStat("MRR", MetricFormat.money(metrics.mrrCents))
                miniStat("ARR", MetricFormat.money(metrics.arrCents))
            }
        }
        .widgetURL(SBWidgetStyle.deepLink)
    }

    private func miniStat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label).font(.system(size: 8, weight: .semibold)).foregroundStyle(SBWidgetStyle.label)
            Text(value).font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(.white).minimumScaleFactor(0.6).lineLimit(1)
        }
    }
}

private struct MediumMetrics: View {
    let metrics: WidgetMetrics
    let stale: Bool
    private let columns = [GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Header(stale: stale)
            LazyVGrid(columns: columns, alignment: .leading, spacing: 10) {
                Tile(label: "Revenue today", value: MetricFormat.money(metrics.revenueTodayCents), accent: SBWidgetStyle.gold)
                Tile(label: "MRR", value: MetricFormat.money(metrics.mrrCents))
                Tile(label: "New subs today", value: MetricFormat.delta(metrics.newSubsToday),
                     accent: metrics.newSubsToday > 0 ? SBWidgetStyle.positive : SBWidgetStyle.value)
                Tile(label: "New users today", value: MetricFormat.delta(metrics.newUsersToday),
                     accent: metrics.newUsersToday > 0 ? SBWidgetStyle.positive : SBWidgetStyle.value)
            }
            Spacer(minLength: 0)
        }
        .widgetURL(SBWidgetStyle.deepLink)
    }
}

private struct LargeMetrics: View {
    let metrics: WidgetMetrics
    let stale: Bool
    let date: Date
    private let columns = [GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Header(stale: stale)
            LazyVGrid(columns: columns, alignment: .leading, spacing: 18) {
                Tile(label: "Revenue today", value: MetricFormat.money(metrics.revenueTodayCents), accent: SBWidgetStyle.gold)
                Tile(label: "MRR", value: MetricFormat.money(metrics.mrrCents))
                Tile(label: "ARR", value: MetricFormat.money(metrics.arrCents))
                Tile(label: "Active subs", value: MetricFormat.plain(metrics.activeSubs))
                Tile(label: "New subs today", value: MetricFormat.delta(metrics.newSubsToday),
                     accent: metrics.newSubsToday > 0 ? SBWidgetStyle.positive : SBWidgetStyle.value)
                Tile(label: "New users today", value: MetricFormat.delta(metrics.newUsersToday),
                     accent: metrics.newUsersToday > 0 ? SBWidgetStyle.positive : SBWidgetStyle.value)
            }
            Spacer(minLength: 0)
            Text("Updated \(date.formatted(date: .omitted, time: .shortened))")
                .font(.system(size: 9))
                .foregroundStyle(SBWidgetStyle.label)
        }
        .widgetURL(SBWidgetStyle.deepLink)
    }
}

// MARK: - Empty states

private struct SignedOutView: View {
    var body: some View {
        VStack(spacing: 6) {
            Text("SEATBEE").font(.system(size: 10, weight: .bold)).tracking(1.5).foregroundStyle(SBWidgetStyle.gold)
            Image(systemName: "lock.fill").font(.system(size: 18)).foregroundStyle(SBWidgetStyle.label)
            Text("Sign in as admin in the Seatbee app")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(SBWidgetStyle.label)
                .multilineTextAlignment(.center)
        }
        .widgetURL(SBWidgetStyle.deepLink)
    }
}

private struct UnavailableView: View {
    var body: some View {
        VStack(spacing: 6) {
            Text("SEATBEE").font(.system(size: 10, weight: .bold)).tracking(1.5).foregroundStyle(SBWidgetStyle.gold)
            Image(systemName: "wifi.slash").font(.system(size: 18)).foregroundStyle(SBWidgetStyle.label)
            Text("Couldn't load metrics").font(.system(size: 11, weight: .medium)).foregroundStyle(SBWidgetStyle.label)
        }
    }
}

#Preview(as: .systemMedium) {
    SeatbeeMetricsWidget()
} timeline: {
    MetricsEntry(date: .now, metrics: .placeholder, signedOut: false, stale: false)
}

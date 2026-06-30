import WidgetKit
import SwiftUI

struct MetricsEntry: TimelineEntry {
    let date: Date
    let metrics: WidgetMetrics?
    let signedOut: Bool
    /// True when we're showing a cached value because the live fetch failed.
    let stale: Bool
}

struct MetricsProvider: TimelineProvider {
    func placeholder(in context: Context) -> MetricsEntry {
        MetricsEntry(date: Date(), metrics: .placeholder, signedOut: false, stale: false)
    }

    func getSnapshot(in context: Context, completion: @escaping (MetricsEntry) -> Void) {
        if context.isPreview {
            completion(MetricsEntry(date: Date(), metrics: .placeholder, signedOut: false, stale: false))
            return
        }
        Task {
            completion(entry(from: await MetricsService.fetch()))
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<MetricsEntry>) -> Void) {
        Task {
            let entry = entry(from: await MetricsService.fetch())
            // Refresh roughly every 30 min. WidgetKit budgets ~40–70 refreshes
            // per day, so this stays comfortably within budget while feeling live.
            let next = Calendar.current.date(byAdding: .minute, value: 30, to: Date())
                ?? Date().addingTimeInterval(1800)
            completion(Timeline(entries: [entry], policy: .after(next)))
        }
    }

    private func entry(from result: Result<WidgetMetrics, MetricsFetchError>) -> MetricsEntry {
        switch result {
        case .success(let metrics):
            return MetricsEntry(date: Date(), metrics: metrics, signedOut: false, stale: false)
        case .failure(.noToken):
            return MetricsEntry(date: Date(), metrics: nil, signedOut: true, stale: false)
        case .failure:
            return MetricsEntry(date: Date(), metrics: nil, signedOut: false, stale: true)
        }
    }
}

struct SeatbeeMetricsWidget: Widget {
    let kind = "SeatbeeMetricsWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: MetricsProvider()) { entry in
            MetricsWidgetView(entry: entry)
                .containerBackground(SBWidgetStyle.background, for: .widget)
        }
        .configurationDisplayName("Seatbee Metrics")
        .description("Revenue, MRR, ARR, subscribers and signups at a glance.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

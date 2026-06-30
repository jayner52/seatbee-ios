import Foundation

enum MetricsFetchError: Error {
    case noToken
    case http(Int)
    case decode
}

/// Fetches the admin metrics for the widget using the shared widget token.
/// On failure it falls back to the last successful fetch (cached in the
/// widget process's own UserDefaults) so a transient outage doesn't blank
/// the widget.
enum MetricsService {
    private static let cacheKey = "lastMetricsJSON"

    static func fetch() async -> Result<WidgetMetrics, MetricsFetchError> {
        guard let token = WidgetKeychain.readToken() else { return .failure(.noToken) }

        var request = URLRequest(url: WidgetShared.metricsURL)
        request.httpMethod = "GET"
        request.setValue(token, forHTTPHeaderField: "X-Widget-Token")
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 15

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { return fallback(.decode) }
            guard http.statusCode == 200 else {
                // 401/403 → token revoked or no longer admin. Keep the cached
                // value if we have one; otherwise surface the error.
                return fallback(.http(http.statusCode))
            }
            let metrics = try JSONDecoder().decode(WidgetMetrics.self, from: data)
            UserDefaults.standard.set(data, forKey: cacheKey)
            return .success(metrics)
        } catch {
            return fallback(.decode)
        }
    }

    private static func fallback(_ error: MetricsFetchError) -> Result<WidgetMetrics, MetricsFetchError> {
        if let data = UserDefaults.standard.data(forKey: cacheKey),
           let cached = try? JSONDecoder().decode(WidgetMetrics.self, from: data) {
            return .success(cached)
        }
        return .failure(error)
    }
}

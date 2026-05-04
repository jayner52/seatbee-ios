import Foundation

// Google Places API (New) — same REST endpoints the web app uses.
// Requires VITE_GOOGLE_PLACES_API_KEY from the web app's env.

final class VenueSearchService {
    private let apiKey: String

    init(apiKey: String = AppConfig.googlePlacesAPIKey) {
        self.apiKey = apiKey
    }

    var isConfigured: Bool { !apiKey.isEmpty }

    // MARK: - Autocomplete Search

    struct VenueSuggestion: Identifiable {
        let id: String // placeId
        let name: String
        let address: String
    }

    func searchVenues(query: String) async throws -> [VenueSuggestion] {
        guard query.count >= 2, isConfigured else { return [] }

        let url = URL(string: "https://places.googleapis.com/v1/places:autocomplete")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "X-Goog-Api-Key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "input": query,
            "includedPrimaryTypes": ["establishment"]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, _) = try await URLSession.shared.data(for: request)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let suggestions = json?["suggestions"] as? [[String: Any]] ?? []

        return suggestions.compactMap { suggestion in
            guard let pred = suggestion["placePrediction"] as? [String: Any],
                  let placeId = pred["placeId"] as? String else { return nil }

            let mainText = (pred["mainText"] as? [String: Any])?["text"] as? String
            let secondaryText = (pred["secondaryText"] as? [String: Any])?["text"] as? String
            let fullText = (pred["text"] as? [String: Any])?["text"] as? String

            return VenueSuggestion(
                id: placeId,
                name: mainText ?? fullText ?? "",
                address: secondaryText ?? ""
            )
        }
    }

    // MARK: - Place Details

    struct VenueDetails {
        let placeId: String
        let name: String
        let address: String
        let city: String
        let state: String
        let country: String
        let lat: Double?
        let lng: Double?
        let website: String?
        let phone: String?
        let rating: Double?
        let photoURLs: [String]
    }

    func getPlaceDetails(placeId: String) async throws -> VenueDetails? {
        guard isConfigured else { return nil }

        let fieldMask = "displayName,formattedAddress,addressComponents,location,types,websiteUri,nationalPhoneNumber,rating,photos"
        let urlString = "https://places.googleapis.com/v1/places/\(placeId)"
        guard let url = URL(string: urlString) else { return nil }

        var request = URLRequest(url: url)
        request.setValue(apiKey, forHTTPHeaderField: "X-Goog-Api-Key")
        request.setValue(fieldMask, forHTTPHeaderField: "X-Goog-FieldMask")

        let (data, _) = try await URLSession.shared.data(for: request)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }

        // Parse address components
        var ac: [String: String] = [:]
        if let components = json["addressComponents"] as? [[String: Any]] {
            for comp in components {
                let longText = comp["longText"] as? String ?? ""
                let shortText = comp["shortText"] as? String ?? ""
                if let types = comp["types"] as? [String] {
                    for type in types {
                        ac[type] = longText
                        ac["\(type)_short"] = shortText
                    }
                }
            }
        }

        let location = json["location"] as? [String: Any]
        let displayName = (json["displayName"] as? [String: Any])?["text"] as? String ?? ""
        let photos = json["photos"] as? [[String: Any]] ?? []

        let photoURLs = photos.prefix(3).compactMap { photo -> String? in
            guard let name = photo["name"] as? String else { return nil }
            return "https://places.googleapis.com/v1/\(name)/media?maxWidthPx=800&key=\(apiKey)"
        }

        return VenueDetails(
            placeId: placeId,
            name: displayName,
            address: json["formattedAddress"] as? String ?? "",
            city: ac["locality"] ?? ac["administrative_area_level_2"] ?? "",
            state: ac["administrative_area_level_1_short"] ?? "",
            country: ac["country"] ?? "",
            lat: location?["latitude"] as? Double,
            lng: location?["longitude"] as? Double,
            website: json["websiteUri"] as? String,
            phone: json["nationalPhoneNumber"] as? String,
            rating: json["rating"] as? Double,
            photoURLs: photoURLs
        )
    }
}

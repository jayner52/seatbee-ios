import SwiftUI

struct SBVenueSearch: View {
    @Binding var venueName: String
    var onSelect: ((VenueSearchService.VenueDetails) -> Void)?

    @State private var query = ""
    @State private var suggestions: [VenueSearchService.VenueSuggestion] = []
    @State private var isSearching = false
    @State private var showResults = false
    @State private var searchTask: Task<Void, Never>?

    private let service = VenueSearchService()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Search field
            HStack(spacing: 10) {
                Image(systemName: "mappin.and.ellipse")
                    .font(.system(size: 16))
                    .foregroundStyle(Color.sbGold)

                TextField("Search for your venue...", text: $query)
                    .font(SBFont.body)
                    .textInputAutocapitalization(.words)
                    .onChange(of: query) { _, newValue in
                        handleQueryChange(newValue)
                    }

                if isSearching {
                    ProgressView()
                        .scaleEffect(0.8)
                }

                if !query.isEmpty {
                    Button {
                        query = ""
                        venueName = ""
                        suggestions = []
                        showResults = false
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(Color.sbWarm2)
                    }
                }
            }
            .padding(14)
            .background(Color.sbIvory2)
            .clipShape(RoundedRectangle(cornerRadius: SBRadius.button))
            .overlay(
                RoundedRectangle(cornerRadius: SBRadius.button)
                    .strokeBorder(Color.sbLine2, lineWidth: 1)
            )

            // Results dropdown
            if showResults && !suggestions.isEmpty {
                VStack(spacing: 0) {
                    ForEach(suggestions) { venue in
                        Button {
                            selectVenue(venue)
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "mappin.circle.fill")
                                    .font(.system(size: 18))
                                    .foregroundStyle(Color.sbGold)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(venue.name)
                                        .font(SBFont.bodySmallBold)
                                        .foregroundStyle(Color.sbCharcoal)
                                        .lineLimit(1)
                                    Text(venue.address)
                                        .font(SBFont.caption)
                                        .foregroundStyle(Color.sbWarm)
                                        .lineLimit(1)
                                }

                                Spacer()
                            }
                            .padding(.vertical, 10)
                            .padding(.horizontal, 14)
                        }
                        .buttonStyle(.plain)

                        if venue.id != suggestions.last?.id {
                            Divider().padding(.leading, 42)
                        }
                    }
                }
                .background(Color.sbIvory)
                .clipShape(RoundedRectangle(cornerRadius: SBRadius.small))
                .overlay(
                    RoundedRectangle(cornerRadius: SBRadius.small)
                        .strokeBorder(Color.sbLine, lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.08), radius: 8, x: 0, y: 4)
                .padding(.top, 4)
            }

            // No Google API fallback
            if !service.isConfigured && !query.isEmpty {
                Text("Venue search requires a Google Places API key")
                    .font(SBFont.caption)
                    .foregroundStyle(Color.sbWarm)
                    .padding(.top, 4)
            }
        }
        .onAppear {
            query = venueName
        }
    }

    private func handleQueryChange(_ newValue: String) {
        venueName = newValue
        searchTask?.cancel()

        guard newValue.count >= 2, service.isConfigured else {
            suggestions = []
            showResults = false
            return
        }

        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(300)) // debounce
            guard !Task.isCancelled else { return }

            isSearching = true
            do {
                let results = try await service.searchVenues(query: newValue)
                if !Task.isCancelled {
                    suggestions = results
                    showResults = !results.isEmpty
                }
            } catch {
                if !Task.isCancelled {
                    suggestions = []
                    showResults = false
                }
            }
            isSearching = false
        }
    }

    private func selectVenue(_ venue: VenueSearchService.VenueSuggestion) {
        query = venue.name
        venueName = venue.name
        showResults = false
        HapticEngine.selection()

        Task {
            if let details = try? await service.getPlaceDetails(placeId: venue.id) {
                onSelect?(details)
            }
        }
    }
}

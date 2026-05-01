import SwiftUI

struct DayOfView: View {
    @Environment(AppState.self) private var appState
    @State private var searchText = ""
    @State private var foundGuest: Guest?

    private var guests: [Guest] { appState.activePlan?.guests ?? [] }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                SBNavHeader(title: "Find a seat", backLabel: "Back", backAction: {
                    appState.selectedTab = .plans
                })

                ScrollView {
                    VStack(spacing: SBSpacing.sectionGapLarge) {
                        Spacer().frame(height: 20)

                        // Hero text
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Looking for")
                                .font(SBFont.fraunces(30, weight: .medium))
                                .foregroundStyle(Color.sbCharcoal)
                            Text("a guest?")
                                .font(SBFont.fraunces(30, weight: .medium))
                                .foregroundStyle(Color.sbGoldDk)
                                .italic()
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        // Search field
                        HStack(spacing: 12) {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 18))
                                .foregroundStyle(Color.sbWarm)
                            TextField("Aunt Linda", text: $searchText)
                                .font(SBFont.body)
                                .textInputAutocapitalization(.words)
                        }
                        .padding(14)
                        .frame(height: 48)
                        .background(Color.sbIvory2)
                        .clipShape(Capsule())
                        .onChange(of: searchText) { _, newValue in
                            searchGuest(query: newValue)
                        }

                        // Results
                        if let guest = foundGuest {
                            foundCard(guest)
                            seatedAtCard(guest)
                        }

                        Spacer(minLength: 100)
                    }
                    .padding(.horizontal, SBSpacing.screenMargin)
                }
            }
            .background(Color.sbIvory)
        }
    }

    // MARK: - Found Card

    private func foundCard(_ guest: Guest) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("FOUND")
                .font(SBFont.capsLabel)
                .foregroundStyle(Color.sbGoldDk)
                .letterSpacing(1.5)

            HStack(spacing: 12) {
                SBAvatar(name: guest.displayName, size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text(guest.displayName)
                        .font(SBFont.fraunces(18, weight: .medium))
                        .foregroundStyle(Color.sbCharcoal)
                    if !guest.categories.isEmpty {
                        Text(guest.categories.first ?? "")
                            .font(SBFont.small)
                            .foregroundStyle(Color.sbWarm)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .transition(.opacity.combined(with: .move(edge: .bottom)))
    }

    // MARK: - Seated At Card

    private func seatedAtCard(_ guest: Guest) -> some View {
        let assignment = findAssignment(for: guest)

        return SBCard(backgroundColor: .sbChampagne) {
            HStack {
                VStack(alignment: .leading, spacing: 8) {
                    Text("SEATED AT")
                        .font(SBFont.capsLabel)
                        .foregroundStyle(Color.sbGoldDk)
                        .letterSpacing(1.5)

                    if let (table, seatIndex) = assignment {
                        Text("\(table.name) · seat \(seatIndex + 1)")
                            .font(SBFont.displayMedium)
                            .foregroundStyle(Color.sbGoldDk)
                    } else {
                        Text("Not yet seated")
                            .font(SBFont.displayMedium)
                            .foregroundStyle(Color.sbWarm)
                    }
                }

                Spacer()

                if let (table, _) = assignment {
                    SBTableGraphic(totalSeats: table.seats, filledSeats: table.filledCount, size: 56)
                }
            }
        }
        .transition(.opacity.combined(with: .move(edge: .bottom)))
    }

    // MARK: - Helpers

    private func searchGuest(query: String) {
        guard query.count >= 2 else {
            foundGuest = nil
            return
        }
        withAnimation(.seatbee) {
            foundGuest = guests.first {
                $0.displayName.localizedCaseInsensitiveContains(query)
            }
        }
    }

    private func findAssignment(for guest: Guest) -> (SeatTable, Int)? {
        guard let plan = appState.activePlan else { return nil }
        for table in plan.tables {
            if let seatIndex = table.assignments[guest.id] {
                return (table, seatIndex)
            }
        }
        return nil
    }
}

#Preview {
    DayOfView()
        .environment(AppState())
}

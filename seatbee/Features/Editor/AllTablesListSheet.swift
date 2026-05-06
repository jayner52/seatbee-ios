import SwiftUI

// All-Tables list — expandable view of every table in the active plan
// with the guests seated at each. Lets users scan the whole arrangement
// without tapping each table individually on the canvas.
//
// Tables are listed in their canvas order. Each row is collapsed by
// default; tap to expand and see seated guests in seat order.

struct AllTablesListSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var expandedTableIds: Set<String> = []

    private var tables: [SeatTable] {
        appState.activePlan?.tables ?? []
    }

    private var guestById: [String: Guest] {
        Dictionary(uniqueKeysWithValues: (appState.activePlan?.guests ?? []).map { ($0.id, $0) })
    }

    private var totalSeated: Int {
        tables.reduce(0) { $0 + $1.assignments.count }
    }

    var body: some View {
        NavigationStack {
            List {
                summarySection
                if tables.isEmpty {
                    emptyStateSection
                } else {
                    tablesSection
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Color.sbIvory)
            .navigationTitle("All Tables")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Color.sbGoldDk)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if !tables.isEmpty {
                        Button(allExpanded ? "Collapse all" : "Expand all") {
                            if allExpanded {
                                expandedTableIds.removeAll()
                            } else {
                                expandedTableIds = Set(tables.map(\.id))
                            }
                        }
                        .font(SBFont.caption)
                        .foregroundStyle(Color.sbGoldDk)
                    }
                }
            }
        }
    }

    private var allExpanded: Bool {
        !tables.isEmpty && expandedTableIds.count == tables.count
    }

    // MARK: - Summary

    private var summarySection: some View {
        Section {
            HStack(spacing: 16) {
                summaryStat(value: tables.count, label: "Tables")
                Divider()
                summaryStat(value: totalSeated, label: "Seated")
                Divider()
                summaryStat(value: max(0, (appState.activePlan?.guests.count ?? 0) - totalSeated), label: "Unseated")
            }
            .padding(.vertical, 4)
        }
    }

    private func summaryStat(value: Int, label: String) -> some View {
        VStack(spacing: 2) {
            Text("\(value)")
                .font(SBFont.statNumberSmall)
                .foregroundStyle(Color.sbGoldDk)
            Text(label.uppercased())
                .font(SBFont.capsLabel)
                .foregroundStyle(Color.sbWarm)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Tables

    @ViewBuilder
    private var tablesSection: some View {
        Section {
            ForEach(tables) { table in
                tableRow(table)
            }
        } header: {
            Text("Tables")
        } footer: {
            Text("Tap a table to see who's seated there. Tap a guest to open their details.")
                .font(SBFont.caption)
        }
    }

    private func tableRow(_ table: SeatTable) -> some View {
        let isExpanded = expandedTableIds.contains(table.id)
        let seated = table.assignments.count
        let capacity = table.seats

        return DisclosureGroup(
            isExpanded: Binding(
                get: { isExpanded },
                set: { newValue in
                    if newValue { expandedTableIds.insert(table.id) }
                    else { expandedTableIds.remove(table.id) }
                }
            )
        ) {
            if seated == 0 {
                Text("No guests seated yet")
                    .font(SBFont.caption)
                    .foregroundStyle(Color.sbWarm)
                    .padding(.vertical, 6)
            } else {
                ForEach(seatedGuests(at: table), id: \.guest.id) { entry in
                    guestRow(entry.guest, seatNumber: entry.seatNumber)
                }
            }
        } label: {
            HStack(spacing: 10) {
                tableIcon(for: table)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(table.name.isEmpty ? "Untitled table" : table.name)
                            .font(SBFont.bodySmallBold)
                            .foregroundStyle(Color.sbCharcoal)
                        if table.locked == true {
                            Image(systemName: "lock.fill")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(Color.sbGoldDk)
                        }
                    }
                    Text("\(seated)/\(capacity) seats filled\(table.locked == true ? " · locked" : "")")
                        .font(SBFont.caption)
                        .foregroundStyle(seated == 0 ? Color.sbWarm : Color.sbGoldDk)
                }
                Spacer()
            }
        }
    }

    private func tableIcon(for table: SeatTable) -> some View {
        let symbol: String
        switch table.type {
        case .head:       symbol = "crown"
        case .sweetheart: symbol = "heart"
        case .rect:       symbol = "rectangle"
        case .round:      symbol = "circle"
        case .oval:       symbol = "oval"
        }
        return Image(systemName: symbol)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(Color.sbGoldDk)
            .frame(width: 26, height: 26)
            .background(Color.sbChampagne.opacity(0.5))
            .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func guestRow(_ guest: Guest, seatNumber: Int) -> some View {
        HStack(spacing: 10) {
            Text("#\(seatNumber)")
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(Color.sbWarm)
                .frame(width: 28, alignment: .leading)
            Text(guest.displayName)
                .font(SBFont.bodySmall)
                .foregroundStyle(Color.sbCharcoal)
                .lineLimit(1)
            if let meal = guest.mealDisplay {
                Text(meal.icon).font(.system(size: 11))
            }
            Spacer()
            if guest.side != .none {
                Text(guest.side.rawValue.prefix(1).uppercased())
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.sbGoldDk)
                    .frame(width: 18, height: 18)
                    .background(Color.sbChampagne.opacity(0.6))
                    .clipShape(Circle())
            }
            if let tags = guest.dietaryTags, !tags.isEmpty {
                // Show specific dietary emoji per tag (vegan 🌱, halal ☪️,
                // etc.) instead of a generic plate. Matches web behaviour.
                HStack(spacing: 1) {
                    ForEach(tags.prefix(3), id: \.self) { tag in
                        if let emoji = DietaryTag.emoji(for: tag) {
                            Text(emoji).font(.system(size: 11))
                        }
                    }
                }
            }
        }
        .padding(.vertical, 2)
    }

    /// Returns guests at the table sorted by seat index (1-based for display).
    private func seatedGuests(at table: SeatTable) -> [(guest: Guest, seatNumber: Int)] {
        table.assignments
            .compactMap { (guestId, seatIndex) -> (Guest, Int)? in
                guard let guest = guestById[guestId] else { return nil }
                return (guest, seatIndex + 1)
            }
            .sorted { $0.1 < $1.1 }
            .map { (guest: $0.0, seatNumber: $0.1) }
    }

    // MARK: - Empty state

    private var emptyStateSection: some View {
        Section {
            VStack(spacing: 8) {
                Image(systemName: "table.furniture")
                    .font(.system(size: 32))
                    .foregroundStyle(Color.sbWarm2)
                Text("No tables yet")
                    .font(SBFont.bodySmallBold)
                    .foregroundStyle(Color.sbCharcoal)
                Text("Add tables in the canvas to see them listed here.")
                    .font(SBFont.caption)
                    .foregroundStyle(Color.sbWarm)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
        }
    }
}

#Preview {
    AllTablesListSheet()
        .environment(AppState())
}

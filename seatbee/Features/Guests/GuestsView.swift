import SwiftUI

struct GuestsView: View {
    @Environment(AppState.self) private var appState
    @State private var searchText = ""
    @State private var selectedFilter = "All"
    @State private var showAddGuest = false
    @State private var showCSVImport = false
    @State private var showCategories = false
    @State private var showRules = false
    @State private var editingGuest: Guest?

    private var plan: SeatingPlan? { appState.activePlan }
    private var guests: [Guest] { plan?.guests ?? [] }

    private let filters = ["All", "Unseated", "Family", "Friends", "+1s", "Dietary"]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                SBNavHeader(
                    title: "Guests",
                    rightContent: AnyView(
                        Button {
                            showAddGuest = true
                        } label: {
                            Image(systemName: "plus")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(Color.sbGoldDk)
                        }
                    )
                )

                ScrollView {
                    VStack(alignment: .leading, spacing: SBSpacing.sectionGap) {
                        // Stats row
                        statsRow

                        // AI CTA
                        if unseatedCount > 0 {
                            SBButton(
                                title: "AI seat the remaining \(unseatedCount)",
                                icon: "sparkles",
                                variant: .gold,
                                fullWidth: true
                            ) {
                                appState.selectedTab = .ai
                            }
                        }

                        // Action buttons
                        HStack(spacing: 8) {
                            SBButton(title: "Import", icon: "square.and.arrow.down", variant: .default, size: .small) {
                                showCSVImport = true
                            }
                            SBButton(title: "Categories", icon: "tag", variant: .default, size: .small) {
                                showCategories = true
                            }
                            SBButton(title: "Rules", icon: "list.bullet", variant: .default, size: .small) {
                                showRules = true
                            }
                        }

                        // Filter chips
                        filterChips

                        // Search
                        searchField

                        // Guest list
                        guestList

                        Spacer(minLength: 100)
                    }
                    .padding(.horizontal, SBSpacing.screenMargin)
                    .padding(.top, SBSpacing.screenMargin)
                }
            }
            .background(Color.sbIvory)
            .sheet(isPresented: $showAddGuest) {
                GuestDetailSheet(guest: nil)
                    .environment(appState)
            }
            .sheet(isPresented: $showCSVImport) {
                CSVImportSheet()
                    .environment(appState)
            }
            .sheet(isPresented: $showCategories) {
                CategoriesSheet()
                    .environment(appState)
            }
            .sheet(isPresented: $showRules) {
                RulesView()
                    .environment(appState)
            }
            .sheet(item: $editingGuest) { guest in
                GuestDetailSheet(guest: guest)
                    .environment(appState)
            }
        }
    }

    // MARK: - Stats

    private var statsRow: some View {
        HStack(spacing: 0) {
            SBStat(value: "\(guests.count)", label: "Total")
            Spacer()
            SBStat(value: "\(unseatedCount)", label: "Unseated", color: .sbGoldDk)
            Spacer()
            SBStat(value: "\(rsvpCount)", label: "RSVP'd", color: .sbSage)
        }
    }

    // MARK: - Filters

    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(filters, id: \.self) { filter in
                    Button {
                        withAnimation(.seatbee) { selectedFilter = filter }
                        HapticEngine.selection()
                    } label: {
                        SBChip(
                            text: filter,
                            variant: selectedFilter == filter ? .gold : .default
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Search

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15))
                .foregroundStyle(Color.sbWarm)
            TextField("Search guests...", text: $searchText)
                .font(SBFont.body)
                .textInputAutocapitalization(.never)
        }
        .padding(12)
        .background(Color.sbIvory2)
        .clipShape(Capsule())
    }

    // MARK: - Guest List

    private var guestList: some View {
        LazyVStack(spacing: 0) {
            ForEach(filteredGuests) { guest in
                guestRow(guest)
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            deleteGuest(guest)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                if guest.id != filteredGuests.last?.id {
                    Divider()
                        .foregroundStyle(Color.sbLine)
                }
            }
        }
    }

    private func guestRow(_ guest: Guest) -> some View {
        Button {
            navigateToGuest(guest)
        } label: {
            HStack(spacing: 12) {
                SBAvatar(name: guest.displayName, size: 36)

                VStack(alignment: .leading, spacing: 2) {
                    Text(guest.displayName)
                        .font(SBFont.bodySmallBold)
                        .foregroundStyle(Color.sbCharcoal)

                    HStack(spacing: 4) {
                        if !guest.categories.isEmpty {
                            Text(guest.categories.first ?? "")
                                .font(SBFont.small)
                                .foregroundStyle(Color.sbWarm)
                        }
                    }
                }

                Spacer()

                // RSVP indicator
                Circle()
                    .fill(rsvpColor(guest.rsvp))
                    .frame(width: 8, height: 8)

                // Chips
                HStack(spacing: 4) {
                    if guest.plusOne == true {
                        SBChip(text: "+1", variant: .default)
                    }
                    if guest.dietary != nil {
                        SBChip(text: "Diet", variant: .default)
                    }
                }

                // Table assignment
                tableAssignment(for: guest)
            }
            .padding(.vertical, 10)
        }
        .buttonStyle(.plain)
    }

    private func navigateToGuest(_ guest: Guest) {
        editingGuest = guest
    }

    private func deleteGuest(_ guest: Guest) {
        guard var plan = appState.activePlan else { return }
        plan.guests.removeAll { $0.id == guest.id }
        for i in plan.tables.indices {
            plan.tables[i].assignments.removeValue(forKey: guest.id)
        }
        appState.activePlan = plan
        HapticEngine.medium()
        Task { try? await appState.database.savePlanData(plan: plan) }
    }

    private func tableAssignment(for guest: Guest) -> some View {
        Group {
            if let table = assignedTable(for: guest) {
                Text(table.name)
                    .font(SBFont.capsLabel)
                    .foregroundStyle(Color.sbGoldDk)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.sbChampagne)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            } else {
                Text("Unseated")
                    .font(SBFont.capsLabel)
                    .foregroundStyle(Color.sbWarm2)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(Color.sbWarm2, style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
                    )
            }
        }
    }

    // MARK: - Helpers

    private var filteredGuests: [Guest] {
        var result = guests

        if !searchText.isEmpty {
            result = result.filter { $0.displayName.localizedCaseInsensitiveContains(searchText) }
        }

        switch selectedFilter {
        case "Unseated":
            result = result.filter { assignedTable(for: $0) == nil }
        case "Family":
            result = result.filter { $0.categories.contains("family") || $0.categories.contains("Family") }
        case "Friends":
            result = result.filter { $0.categories.contains("friends") || $0.categories.contains("Friends") }
        case "+1s":
            result = result.filter { $0.plusOne == true }
        case "Dietary":
            result = result.filter { $0.dietary != nil }
        default:
            break
        }

        return result
    }

    private func assignedTable(for guest: Guest) -> SeatTable? {
        plan?.tables.first { $0.assignments.keys.contains(guest.id) }
    }

    private func rsvpColor(_ status: Guest.RSVPStatus) -> Color {
        switch status {
        case .yes: return .sbSage
        case .pending: return .sbBlush
        case .no: return .sbError
        case .unknown: return .sbWarm2
        }
    }

    private var unseatedCount: Int {
        guard let plan else { return 0 }
        let seated = Set(plan.tables.flatMap { $0.assignments.keys })
        return plan.guests.filter { !seated.contains($0.id) }.count
    }

    private var rsvpCount: Int {
        guests.filter { $0.rsvp == .yes }.count
    }
}

#Preview {
    GuestsView()
        .environment(AppState())
}

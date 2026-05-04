import SwiftUI

// Web parity (src/App.jsx:3378-3386 + 12107-12117). The 8 canonical dietary
// tags shared between iOS and web. iOS stores selected tag IDs in
// `Guest.dietaryTags`; web does the same. Emoji + label match web exactly.
enum DietaryTag {
    static let all: [(id: String, label: String, emoji: String)] = [
        ("vegetarian",        "Vegetarian",        "🌿"),
        ("vegan",             "Vegan",             "🌱"),
        ("halal",             "Halal",             "☪️"),
        ("gluten-free",       "Gluten-Free",       "🌾"),
        ("dairy-free",        "Dairy-Free",        "🥛"),
        ("nut-allergy",       "Nut Allergy",       "🥜"),
        ("shellfish-allergy", "Shellfish Allergy", "🦐"),
        ("kosher",            "Kosher",            "✡️"),
    ]

    static func emoji(for id: String) -> String? {
        all.first { $0.id == id }?.emoji
    }

    static func label(for id: String) -> String? {
        all.first { $0.id == id }?.label
    }
}

enum GuestSortMode: String, CaseIterable {
    case byTable = "By Table"
    case alphabetical = "A–Z"
}

struct GuestsView: View {
    @Environment(AppState.self) private var appState
    @State private var searchText = ""
    @State private var selectedFilter = "All"
    @State private var sortMode: GuestSortMode = .byTable
    @State private var showAddGuest = false
    @State private var showCSVImport = false
    @State private var showCategories = false
    @State private var showRules = false
    @State private var showParties = false
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
                    if plan == nil {
                        noPlanState
                    } else if guests.isEmpty {
                        emptyGuestsState
                    } else {
                        guestsContent
                    }
                }
            }
            .background(Color.sbIvory)
            .task {
                // Auto-load active plan if not set
                if appState.activePlan == nil {
                    do {
                        let plans = try await appState.database.fetchPlans()
                        if let first = plans.first {
                            appState.activePlan = first
                        }
                    } catch {}
                }
            }
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
            .sheet(isPresented: $showParties) {
                PartiesSheet()
                    .environment(appState)
            }
            .sheet(item: $editingGuest) { guest in
                GuestDetailSheet(guest: guest)
                    .environment(appState)
            }
        }
    }

    // MARK: - States

    private var noPlanState: some View {
        VStack(spacing: 16) {
            Spacer().frame(height: 80)
            Image(systemName: "person.2.slash")
                .font(.system(size: 44))
                .foregroundStyle(Color.sbWarm2)
            Text("No plan selected")
                .font(SBFont.displaySmall)
                .foregroundStyle(Color.sbCharcoal)
            Text("Go to Plans tab to select or create a plan")
                .font(SBFont.body)
                .foregroundStyle(Color.sbWarm)
                .multilineTextAlignment(.center)
            SBButton(title: "Go to Plans", icon: "square.grid.2x2", variant: .gold) {
                appState.selectedTab = .plans
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, SBSpacing.screenMargin)
        .transition(.opacity)
    }

    private var emptyGuestsState: some View {
        VStack(spacing: 20) {
            Spacer().frame(height: 60)
            Image(systemName: "person.badge.plus")
                .font(.system(size: 44))
                .foregroundStyle(Color.sbGold)
            Text("No guests yet")
                .font(SBFont.displaySmall)
                .foregroundStyle(Color.sbCharcoal)
            Text("Add guests to start planning your seating")
                .font(SBFont.body)
                .foregroundStyle(Color.sbWarm)
                .multilineTextAlignment(.center)
            VStack(spacing: 10) {
                SBButton(title: "Add Guest", icon: "plus", variant: .gold, fullWidth: true) {
                    showAddGuest = true
                }
                SBButton(title: "Import CSV", icon: "square.and.arrow.down", variant: .primary, fullWidth: true) {
                    showCSVImport = true
                }
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, SBSpacing.screenMargin)
        .transition(.opacity)
    }

    // MARK: - Main Content

    private var guestsContent: some View {
        VStack(alignment: .leading, spacing: SBSpacing.sectionGap) {
            statsRow
                .animation(.seatbee, value: guests.count)

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

            ScrollView(.horizontal, showsIndicators: false) {
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
                    SBButton(title: "Parties", icon: "person.3", variant: .default, size: .small) {
                        showParties = true
                    }
                }
            }

            filterChips
            sortToggle
            searchField
            guestList

            Spacer(minLength: 100)
        }
        .padding(.horizontal, SBSpacing.screenMargin)
        .padding(.top, SBSpacing.screenMargin)
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

    // MARK: - Sort toggle

    private var sortToggle: some View {
        HStack(spacing: 6) {
            ForEach(GuestSortMode.allCases, id: \.self) { mode in
                Button {
                    withAnimation(.seatbee) { sortMode = mode }
                    HapticEngine.selection()
                } label: {
                    let active = sortMode == mode
                    HStack(spacing: 4) {
                        Image(systemName: mode == .byTable ? "rectangle.3.group" : "textformat.abc")
                            .font(.system(size: 11, weight: .semibold))
                        Text(mode.rawValue).font(SBFont.inter(12, weight: .semibold))
                    }
                    .foregroundStyle(active ? Color.sbGoldDk : Color.sbWarm)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(active ? Color.sbChampagne : Color.sbIvory2)
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            Spacer()
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

    @ViewBuilder
    private var guestList: some View {
        switch sortMode {
        case .alphabetical:
            alphabeticalList
        case .byTable:
            byTableList
        }
    }

    private var alphabeticalList: some View {
        let sorted = filteredGuests.sorted {
            $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }
        return LazyVStack(spacing: 0) {
            ForEach(sorted) { guest in
                guestRowWithSwipe(guest)
                if guest.id != sorted.last?.id {
                    Divider().foregroundStyle(Color.sbLine)
                }
            }
        }
    }

    private var byTableList: some View {
        let sections = guestSections
        return LazyVStack(spacing: 16) {
            ForEach(sections, id: \.id) { section in
                VStack(spacing: 0) {
                    sectionHeader(section)
                    ForEach(section.guests) { guest in
                        guestRowWithSwipe(guest)
                        if guest.id != section.guests.last?.id {
                            Divider().foregroundStyle(Color.sbLine)
                        }
                    }
                }
                .padding(.horizontal, section.isUnseated ? 12 : 0)
                .padding(.vertical, section.isUnseated ? 8 : 0)
                .background(section.isUnseated ? Color.sbGold.opacity(0.06) : Color.clear)
                .overlay(
                    Group {
                        if section.isUnseated {
                            RoundedRectangle(cornerRadius: SBRadius.small)
                                .strokeBorder(Color.sbGold.opacity(0.25), lineWidth: 1)
                        }
                    }
                )
                .clipShape(RoundedRectangle(cornerRadius: SBRadius.small))
            }
        }
    }

    private func guestRowWithSwipe(_ guest: Guest) -> some View {
        guestRow(guest)
            .swipeActions(edge: .trailing) {
                Button(role: .destructive) {
                    deleteGuest(guest)
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
    }

    private func sectionHeader(_ section: GuestSection) -> some View {
        HStack(spacing: 8) {
            if section.isUnseated {
                Text("NEEDS SEATING")
                    .font(SBFont.capsLabel)
                    .foregroundStyle(Color.sbGoldDk)
            } else {
                if let color = section.colorHex.flatMap({ Color(hex: $0) }) {
                    Circle().fill(color).frame(width: 8, height: 8)
                }
                Text(section.title.uppercased())
                    .font(SBFont.capsLabel)
                    .foregroundStyle(Color.sbCharcoal)
                Text("(\(section.guests.count)/\(section.capacity ?? section.guests.count))")
                    .font(SBFont.small)
                    .foregroundStyle(Color.sbWarm)
                if let cap = section.capacity, section.guests.count >= cap {
                    Text("FULL")
                        .font(SBFont.inter(8, weight: .bold))
                        .foregroundStyle(Color.sbSage)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(Color.sbSage.opacity(0.2))
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                }
            }
            Spacer()
            Text("\(section.guests.count)")
                .font(SBFont.bodySmallBold)
                .foregroundStyle(Color.sbWarm)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.sbIvory2)
                .clipShape(Capsule())
        }
        .padding(.vertical, 6)
        .padding(.horizontal, section.isUnseated ? 0 : 4)
    }

    // Web parity (src/App.jsx:7632): per-table groups, head/sweet first then
    // alpha-numeric by name; alpha-by-displayName within each group;
    // unseated guests in their own "NEEDS SEATING" section at the top
    // (insertion order, matches web's `unassigned` ordering).
    private struct GuestSection {
        let id: String
        let title: String
        let guests: [Guest]
        let isUnseated: Bool
        let capacity: Int?
        let colorHex: String?
    }

    private var guestSections: [GuestSection] {
        guard let plan else { return [] }
        let assignmentByGuest: [String: SeatTable] = {
            var dict: [String: SeatTable] = [:]
            for table in plan.tables {
                for guestId in table.assignments.keys {
                    dict[guestId] = table
                }
            }
            return dict
        }()

        var sections: [GuestSection] = []

        // Unseated section (no rsvp filter — show even declined so users see them)
        let unseated = filteredGuests.filter { assignmentByGuest[$0.id] == nil }
        if !unseated.isEmpty {
            sections.append(.init(
                id: "__unseated",
                title: "Needs Seating",
                guests: unseated,
                isUnseated: true,
                capacity: nil,
                colorHex: nil
            ))
        }

        // Per-table groups, mirroring web's sort:
        // head/sweet first, then alpha-numeric by table name.
        let sortedTables = plan.tables.sorted { a, b in
            func priority(_ t: SeatTable) -> Int {
                switch t.type {
                case .head, .sweetheart: return 0
                default: return 1
                }
            }
            let pa = priority(a), pb = priority(b)
            if pa != pb { return pa < pb }
            return a.name.localizedStandardCompare(b.name) == .orderedAscending
        }

        for table in sortedTables {
            let tableGuests = filteredGuests
                .filter { assignmentByGuest[$0.id]?.id == table.id }
                .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
            guard !tableGuests.isEmpty else { continue }
            sections.append(.init(
                id: table.id,
                title: table.name,
                guests: tableGuests,
                isUnseated: false,
                capacity: table.seats,
                colorHex: table.color
            ))
        }

        return sections
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

                    if let categoryLabel = primaryCategoryLabel(for: guest) {
                        Text(categoryLabel)
                            .font(SBFont.small)
                            .foregroundStyle(Color.sbWarm)
                    }
                }

                Spacer()

                // RSVP indicator
                Circle()
                    .fill(rsvpColor(guest.rsvp))
                    .frame(width: 8, height: 8)

                // Per-guest indicators (web parity).
                HStack(spacing: 4) {
                    if guest.vip {
                        Text("VIP")
                            .font(SBFont.inter(8, weight: .bold))
                            .foregroundStyle(Color.sbGoldDk)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .background(Color.sbGold.opacity(0.2))
                            .clipShape(RoundedRectangle(cornerRadius: 3))
                    }
                    if guest.isChild == true {
                        Text("🧒").font(.system(size: 12))
                    }
                    if guest.highChair == true {
                        Text("🪑").font(.system(size: 12))
                    }
                    if guest.plusOne == true {
                        SBChip(text: "+1", variant: .default)
                    }
                    dietaryEmojis(for: guest)
                }

                // Table assignment
                tableAssignment(for: guest)
            }
            .padding(.vertical, 10)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func dietaryEmojis(for guest: Guest) -> some View {
        // Web parity (src/App.jsx:12107-12117): one emoji per tag in
        // dietaryTags[]; if no tags but `dietary` free text exists, fall
        // back to a single 🍽 chip so the row still signals "has dietary
        // info." If neither, show nothing — no generic emoji on every row.
        if let tags = guest.dietaryTags, !tags.isEmpty {
            HStack(spacing: 2) {
                ForEach(tags, id: \.self) { tag in
                    if let emoji = DietaryTag.emoji(for: tag) {
                        Text(emoji).font(.system(size: 12))
                    }
                }
            }
        } else if let dietary = guest.dietary, !dietary.isEmpty {
            Text("🍽").font(.system(size: 11))
                .foregroundStyle(Color.sbWarm.opacity(0.6))
        }
    }

    // Web stores categories as IDs; iOS preserves the raw category objects
    // via `SeatingPlan.rawCategories` (array of [String: AnyCodable]). Look
    // up the first category's name for display so we don't render raw IDs
    // like "y0b4xyih6". Falls back to the raw string if no match.
    // Pick a human-readable category label for the row. Web stores
    // categories as random IDs (e.g. "a5gb6pp2n") and looks up the name
    // in rawCategories. Some plans have orphan IDs — guest references
    // a category that was later deleted from the canonical list. In
    // that case fall back to the next category that DOES resolve, or
    // any plain-text category (no digits — random IDs always contain
    // digits, real names rarely do). If nothing qualifies, hide the
    // subtitle rather than show a raw ID.
    private func primaryCategoryLabel(for guest: Guest) -> String? {
        for cat in guest.categories where !cat.isEmpty {
            if let name = categoryName(forId: cat), !name.isEmpty { return name }
        }
        for cat in guest.categories where !cat.isEmpty {
            if !cat.contains(where: { $0.isNumber }) { return cat }
        }
        return nil
    }

    private func categoryName(forId id: String) -> String? {
        guard let raw = plan?.rawCategories else { return nil }
        for entry in raw {
            if let entryId = entry["id"]?.value as? String, entryId == id,
               let name = entry["name"]?.value as? String, !name.isEmpty {
                return name
            }
        }
        return nil
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
            result = result.filter { g in
                (g.dietaryTags?.isEmpty == false) ||
                (g.dietary?.isEmpty == false)
            }
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

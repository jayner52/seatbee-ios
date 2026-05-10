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
    @State private var selectedFilter = "__all"
    @State private var sortMode: GuestSortMode = .byTable
    @State private var showAddGuest = false
    @State private var showCSVImport = false
    @State private var showCategories = false
    @State private var showRules = false
    @State private var showParties = false
    @State private var showMeals = false
    @State private var showRSVP = false
    @State private var editingGuest: Guest?
    @FocusState private var searchFocused: Bool

    // Paste-list fallback on the empty state. Mirrors the onboarding
    // step-2 paste experience so a planner who lands on a fresh event
    // can drop a list straight in without going through CSV import.
    @State private var pasteText = ""
    @State private var pasteParsed: [Guest] = []

    private var plan: SeatingPlan? { appState.activePlan }
    private var guests: [Guest] { plan?.guests ?? [] }

    // Filter chip identity: stable string token. Built-in filters use
    // reserved tokens prefixed with `__` so they can't collide with a
    // user-named category. Category filters use the canonical category
    // ID — looked up via `rawCategories` for the display name. This
    // replaces the old hardcoded `["All","Unseated","Family",...]` list
    // which only worked when web's category IDs happened to match those
    // literal strings (default iOS-created categories did, web-created
    // ones with random IDs didn't, so they never appeared in the row).
    private static let filterAll = "__all"
    private static let filterUnseated = "__unseated"
    private static let filterDietary = "__dietary"
    // RSVP-state filters. Web parity: "Pending" covers both .pending
    // and .unknown — web treats null/maybe/unknown as the same bucket.
    private static let filterRSVPYes = "__rsvp_yes"
    private static let filterRSVPPending = "__rsvp_pending"
    private static let filterRSVPNo = "__rsvp_no"
    // "Missing data" filters — surface the stragglers without
    // scrolling. Helpful for catering prep ("who hasn't given me a
    // meal?"), dietary follow-up, or category cleanup.
    private static let filterNoMeal = "__no_meal"
    private static let filterNoDietary = "__no_dietary"
    private static let filterNoCategory = "__no_category"

    /// Canonical id → name list, sorted alphabetically by name. Same
    /// pattern as RulesView.canonicalCategories / CategoriesSheet so
    /// add/delete in the Categories sheet shows up here immediately.
    private var canonicalCategories: [(id: String, name: String, color: String?)] {
        guard let raw = plan?.rawCategories else { return [] }
        return raw.compactMap { entry -> (String, String, String?)? in
            guard let id = entry["id"]?.value as? String else { return nil }
            let name = (entry["name"]?.value as? String) ?? id
            let color = entry["color"]?.value as? String
            return (id, name, color)
        }
        .sorted { $0.1.localizedCaseInsensitiveCompare($1.1) == .orderedAscending }
    }

    /// `[(token, displayLabel)]` chip set: All + Unseated + every
    /// canonical category + Dietary (only when guests exist with
    /// dietary tags or free-text). Always the same order so chips
    /// don't shuffle as users seat people.
    private var filterChipsData: [(token: String, label: String)] {
        var out: [(String, String)] = [
            (Self.filterAll, "All"),
            (Self.filterUnseated, "Unseated"),
        ]
        // RSVP filters surface only when the relevant bucket has guests
        // — keeps the chip row tight on plans with all yes/all pending.
        if guests.contains(where: { $0.rsvp == .yes }) {
            out.append((Self.filterRSVPYes, "RSVP Yes"))
        }
        if guests.contains(where: { $0.rsvp == .pending || $0.rsvp == .unknown }) {
            out.append((Self.filterRSVPPending, "RSVP Pending"))
        }
        if guests.contains(where: { $0.rsvp == .no }) {
            out.append((Self.filterRSVPNo, "RSVP No"))
        }
        for cat in canonicalCategories {
            out.append((cat.id, cat.name))
        }
        let hasDietary = guests.contains { ($0.dietaryTags?.isEmpty == false) || ($0.dietary?.isEmpty == false) }
        if hasDietary {
            out.append((Self.filterDietary, "Dietary"))
        }
        // "Missing data" chips — only surface when at least one guest
        // qualifies (so a fully-finished plan doesn't carry permanent
        // empty filters). Counts on the chips would clutter; users
        // can read the filtered list count instead.
        let missingMealCount = guests.filter {
            ($0.meal?.trimmingCharacters(in: .whitespaces).isEmpty ?? true)
        }.count
        if missingMealCount > 0 && missingMealCount < guests.count {
            out.append((Self.filterNoMeal, "No meal"))
        }
        let missingDietaryCount = guests.filter {
            ($0.dietaryTags?.isEmpty ?? true) &&
            ($0.dietary?.isEmpty ?? true)
        }.count
        if missingDietaryCount > 0 && missingDietaryCount < guests.count {
            out.append((Self.filterNoDietary, "No dietary"))
        }
        let missingCategoryCount = guests.filter { $0.categories.isEmpty }.count
        if missingCategoryCount > 0 && missingCategoryCount < guests.count {
            out.append((Self.filterNoCategory, "No category"))
        }
        return out
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                SBNavHeader(
                    title: "Guests",
                    rightContent: plan?.isDemo == true
                        ? AnyView(EmptyView())
                        : AnyView(
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
                // Swipe-down on the list dismisses the search keyboard
                // — without this users had no way out except tapping
                // the tiny return key on the keyboard. Interactive
                // mode tracks the gesture so the keyboard slides
                // smoothly with the finger.
                .scrollDismissesKeyboard(.interactively)
            }
            .background(
                // Tap-to-dismiss: when the search returns no matches,
                // the scroll view has no draggable content, so swipe-
                // down can't dismiss the keyboard. A clear tap target
                // on the background gives users a reliable escape.
                Color.sbIvory
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture { searchFocused = false }
            )
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { searchFocused = false }
                        .foregroundStyle(Color.sbGoldDk)
                        .fontWeight(.semibold)
                }
            }
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

                // If we landed here via the Plans-tab "Rules" quick action,
                // open the Rules sheet now and clear the hint.
                if appState.pendingShowRules {
                    showRules = true
                    appState.pendingShowRules = false
                }
            }
            .onChange(of: appState.pendingShowRules) { _, newValue in
                // Catches the case where GuestsView is already on screen
                // when the hint is set (i.e. user re-taps Rules quick action
                // after we've already loaded the tab once).
                if newValue {
                    showRules = true
                    appState.pendingShowRules = false
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
            .sheet(isPresented: $showMeals) {
                MealsSheet()
                    .environment(appState)
            }
            .sheet(isPresented: $showRSVP) {
                RSVPSheet()
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
            Spacer().frame(height: 40)
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

            // OR PASTE divider
            HStack {
                Rectangle().fill(Color.sbLine2).frame(height: 1)
                Text("OR PASTE")
                    .font(SBFont.capsLabel)
                    .foregroundStyle(Color.sbWarm)
                Rectangle().fill(Color.sbLine2).frame(height: 1)
            }
            .padding(.top, 4)

            // Paste-list fallback. Same parser as onboarding step 2 so
            // header-row CSV pastes detect headers, while "Name, diet"
            // lines come through as one guest per line.
            ZStack(alignment: .topLeading) {
                TextEditor(text: $pasteText)
                    .font(SBFont.body)
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .focused($searchFocused)
                    .onChange(of: pasteText) { _, _ in parsePasteText() }
                if pasteText.isEmpty {
                    Text("Sarah Chen, vegetarian\nJon Park\nAmir Patel, gluten-free\n…")
                        .font(SBFont.body)
                        .foregroundStyle(Color.sbWarm2)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 16)
                        .allowsHitTesting(false)
                }
            }
            .frame(height: 140)
            .background(Color.sbIvory2)
            .clipShape(RoundedRectangle(cornerRadius: SBRadius.button))

            HStack(spacing: 4) {
                Image(systemName: "lightbulb")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.sbGoldDk)
                Text("Tip: add a comma + dietary note (e.g. \"Sarah Chen, vegetarian\"). Add meals + parties after.")
                    .font(SBFont.caption)
                    .foregroundStyle(Color.sbWarm)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.leading)
            }

            if !pasteParsed.isEmpty {
                SBButton(
                    title: "Add \(pasteParsed.count) guest\(pasteParsed.count == 1 ? "" : "s")",
                    icon: "checkmark",
                    variant: .gold,
                    fullWidth: true
                ) {
                    commitPasteParsed()
                }
            }

            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, SBSpacing.screenMargin)
        .transition(.opacity)
    }

    // MARK: - Paste-list fallback

    /// Re-parse the paste field on every keystroke. Synchronous and
    /// cheap — same path the onboarding paste field uses.
    private func parsePasteText() {
        guard !pasteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            pasteParsed = []
            return
        }
        pasteParsed = GuestCSVParser.parseFlexible(pasteText).guests
    }

    /// Commit parsed guests to the active plan, preserving all the
    /// fields the parser populated (name, firstName, lastName,
    /// dietary, etc.). Doesn't dedupe — paste twice and you get
    /// duplicates, same as web.
    private func commitPasteParsed() {
        guard var plan = appState.activePlan, !pasteParsed.isEmpty else { return }
        plan.guests.append(contentsOf: pasteParsed)
        appState.activePlan = plan
        let snap = plan
        Task { try? await appState.database.savePlanData(plan: snap) }
        HapticEngine.success()
        pasteText = ""
        pasteParsed = []
    }

    // MARK: - Main Content

    private var guestsContent: some View {
        VStack(alignment: .leading, spacing: SBSpacing.sectionGap) {
            // Sample event — soft banner so users know guests are read-only
            // before they go looking for the missing Add / Import buttons.
            if plan?.isDemo == true {
                sampleEventBanner
            }

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
                    // Add / Import are hidden for the sample plan — guest
                    // list is curated and locked in the demo.
                    if plan?.isDemo != true {
                        SBButton(title: "Import", icon: "square.and.arrow.down", variant: .default, size: .small) {
                            showCSVImport = true
                        }
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
                    SBButton(title: "Meals", icon: "fork.knife", variant: .default, size: .small) {
                        showMeals = true
                    }
                    SBButton(title: "RSVP", icon: "envelope", variant: .default, size: .small) {
                        showRSVP = true
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
                ForEach(filterChipsData, id: \.token) { chip in
                    Button {
                        withAnimation(.seatbee) {
                            // Tap-to-toggle: re-tapping the active chip
                            // clears back to All (same gesture as deselect
                            // on the chip itself, no separate clear button
                            // needed).
                            selectedFilter = (selectedFilter == chip.token)
                                ? Self.filterAll
                                : chip.token
                        }
                        HapticEngine.selection()
                    } label: {
                        SBChip(
                            text: chip.label,
                            variant: selectedFilter == chip.token ? .gold : .default
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        // If the selected category gets deleted (e.g. via the Categories
        // sheet) while we're filtering on it, the chip row would keep
        // the highlight on a missing token. Snap back to All.
        .onChange(of: filterChipsData.map(\.token)) { _, tokens in
            if !tokens.contains(selectedFilter) {
                selectedFilter = Self.filterAll
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

    // MARK: - Sample event banner
    //
    // Shown only on the bundled demo plan. Tells users why Add / Import /
    // delete are missing without making them guess.

    private var sampleEventBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "sparkles")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.sbGoldDk)
            VStack(alignment: .leading, spacing: 2) {
                Text("Sample event")
                    .font(SBFont.bodySmallBold)
                    .foregroundStyle(Color.sbCharcoal)
                Text("Guest list is read-only. Tap AI to see seating in action.")
                    .font(SBFont.caption)
                    .foregroundStyle(Color.sbWarm)
            }
            Spacer()
        }
        .padding(12)
        .background(Color.sbChampagne2)
        .clipShape(RoundedRectangle(cornerRadius: SBRadius.button))
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
                .focused($searchFocused)
                .submitLabel(.done)
                .onSubmit { searchFocused = false }
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                    searchFocused = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(Color.sbWarm)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
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
                .padding(.horizontal, sectionPadHoriz(section))
                .padding(.vertical, sectionPadVert(section))
                .background(sectionBackground(section))
                .overlay(sectionBorder(section))
                .clipShape(RoundedRectangle(cornerRadius: SBRadius.small))
                // Web parity: declined section dimmed (App.jsx ~10582
                // uses opacity-60). Sets the whole section, including
                // the header, so the visual "this is past tense"
                // reads at a glance.
                .opacity(section.isDeclined ? 0.6 : 1)
            }
        }
    }

    private func sectionPadHoriz(_ s: GuestSection) -> CGFloat {
        s.isUnseated || s.isDeclined ? 12 : 0
    }
    private func sectionPadVert(_ s: GuestSection) -> CGFloat {
        s.isUnseated || s.isDeclined ? 8 : 0
    }
    private func sectionBackground(_ s: GuestSection) -> Color {
        if s.isUnseated { return Color.sbGold.opacity(0.06) }
        if s.isDeclined { return Color.sbError.opacity(0.05) }
        return .clear
    }
    @ViewBuilder
    private func sectionBorder(_ s: GuestSection) -> some View {
        if s.isUnseated {
            RoundedRectangle(cornerRadius: SBRadius.small)
                .strokeBorder(Color.sbGold.opacity(0.25), lineWidth: 1)
        } else if s.isDeclined {
            RoundedRectangle(cornerRadius: SBRadius.small)
                .strokeBorder(Color.sbError.opacity(0.25), lineWidth: 1)
        }
    }

    private func guestRowWithSwipe(_ guest: Guest) -> some View {
        // Sample plan: no destructive swipe — guests are part of the
        // curated demo and can't be removed.
        if plan?.isDemo == true {
            return AnyView(guestRow(guest))
        }
        return AnyView(
            guestRow(guest)
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) {
                        deleteGuest(guest)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
        )
    }

    private func sectionHeader(_ section: GuestSection) -> some View {
        HStack(spacing: 8) {
            if section.isUnseated {
                Text("NEEDS SEATING")
                    .font(SBFont.capsLabel)
                    .foregroundStyle(Color.sbGoldDk)
            } else if section.isDeclined {
                Text("DECLINED")
                    .font(SBFont.capsLabel)
                    .foregroundStyle(Color.sbError)
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
        let isDeclined: Bool
        let capacity: Int?
        let colorHex: String?

        init(id: String, title: String, guests: [Guest],
             isUnseated: Bool = false, isDeclined: Bool = false,
             capacity: Int? = nil, colorHex: String? = nil) {
            self.id = id
            self.title = title
            self.guests = guests
            self.isUnseated = isUnseated
            self.isDeclined = isDeclined
            self.capacity = capacity
            self.colorHex = colorHex
        }
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

        // Web parity (App.jsx:10438): "Needs Seating" excludes
        // rsvp == .no — declined guests don't need to be seated, so
        // they get their own section at the bottom (see end of method).
        let unseatedAttending = filteredGuests.filter {
            assignmentByGuest[$0.id] == nil && $0.rsvp != .no
        }
        if !unseatedAttending.isEmpty {
            sections.append(.init(
                id: "__unseated",
                title: "Needs Seating",
                guests: unseatedAttending,
                isUnseated: true
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

        // Web parity (App.jsx ~10582): declined guests render in
        // their own section at the very bottom, dimmed so they
        // visually fall away from the active list.
        let declined = filteredGuests.filter { $0.rsvp == .no }
            .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
        if !declined.isEmpty {
            sections.append(.init(
                id: "__declined",
                title: "Declined",
                guests: declined,
                isDeclined: true
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

                    categoryChips(for: guest)
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
                    dietaryEmojis(for: guest)
                }

                // Table assignment
                tableAssignment(for: guest)
            }
            .padding(.vertical, 10)
            // Make the entire row a single tap target. Without this,
            // .buttonStyle(.plain) only registers taps over visible
            // content (text, avatar, dots) — the wide Spacer in the
            // middle was dead, forcing users to aim for the small RSVP
            // circle to open the editor.
            .contentShape(Rectangle())
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

    // Resolve a guest's categories into displayable chips. Web stores
    // category IDs (random alphanumeric like "a5gb6pp2n"); iOS preserves
    // the canonical list via `rawCategories`. Drop orphan IDs (no entry
    // in rawCategories AND value contains digits — web's genId() output);
    // keep entries that resolve to a name OR are plain-text strings (iOS-
    // CSV style). Render up to 2 chips inline; if more, show "+N".
    private func resolvedCategories(for guest: Guest) -> [(label: String, color: Color?)] {
        var out: [(String, Color?)] = []
        for cat in guest.categories where !cat.isEmpty {
            if let entry = categoryEntry(forId: cat) {
                let name = (entry["name"]?.value as? String) ?? cat
                let color = (entry["color"]?.value as? String).flatMap { Color(hex: $0) }
                out.append((name, color))
            } else if !cat.contains(where: { $0.isNumber }) {
                out.append((cat, nil))
            }
        }
        return out
    }

    @ViewBuilder
    private func categoryChips(for guest: Guest) -> some View {
        let cats = resolvedCategories(for: guest)
        if !cats.isEmpty {
            let visible = Array(cats.prefix(2))
            let overflow = cats.count - visible.count
            HStack(spacing: 4) {
                ForEach(Array(visible.enumerated()), id: \.offset) { _, item in
                    Text(item.label)
                        .font(SBFont.inter(9, weight: .semibold))
                        .foregroundStyle(item.color.map { foregroundForChip($0) } ?? Color.sbWarm)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background((item.color ?? Color.sbIvory2).opacity(item.color == nil ? 1 : 0.25))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
                if overflow > 0 {
                    Text("+\(overflow)")
                        .font(SBFont.inter(9, weight: .semibold))
                        .foregroundStyle(Color.sbWarm)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.sbIvory2)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
            }
        }
    }

    // Tinted-chip foreground: dark colors get rendered text (sage/blue)
    // become readable, light colors fall back to charcoal.
    private func foregroundForChip(_ color: Color) -> Color {
        Color.sbCharcoal
    }

    private func categoryName(forId id: String) -> String? {
        (categoryEntry(forId: id)?["name"]?.value as? String).flatMap { $0.isEmpty ? nil : $0 }
    }

    private func categoryEntry(forId id: String) -> [String: AnyCodable]? {
        guard let raw = plan?.rawCategories else { return nil }
        return raw.first { ($0["id"]?.value as? String) == id }
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
        case Self.filterAll:
            break
        case Self.filterUnseated:
            result = result.filter { assignedTable(for: $0) == nil }
        case Self.filterDietary:
            result = result.filter { g in
                (g.dietaryTags?.isEmpty == false) ||
                (g.dietary?.isEmpty == false)
            }
        case Self.filterRSVPYes:
            result = result.filter { $0.rsvp == .yes }
        case Self.filterRSVPPending:
            result = result.filter { $0.rsvp == .pending || $0.rsvp == .unknown }
        case Self.filterRSVPNo:
            result = result.filter { $0.rsvp == .no }
        case Self.filterNoMeal:
            result = result.filter {
                ($0.meal?.trimmingCharacters(in: .whitespaces).isEmpty ?? true)
            }
        case Self.filterNoDietary:
            result = result.filter {
                ($0.dietaryTags?.isEmpty ?? true) && ($0.dietary?.isEmpty ?? true)
            }
        case Self.filterNoCategory:
            result = result.filter { $0.categories.isEmpty }
        default:
            // Category filter: match by canonical ID (selectedFilter holds
            // the rawCategories entry's id, not the displayed name). This
            // means renaming a category in the sheet doesn't break the
            // filter, and web-created categories with random IDs work too.
            result = result.filter { $0.categories.contains(selectedFilter) }
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

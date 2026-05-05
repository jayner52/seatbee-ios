import SwiftUI

struct RulesView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var showAddRule = false
    @State private var showAddParty = false
    @State private var pendingAddType: SeatingRule.RuleType = .mustTogether
    @State private var collapsedSections: Set<String> = []

    private var rules: [SeatingRule] { appState.activePlan?.rules ?? [] }
    private var guests: [Guest] { appState.activePlan?.guests ?? [] }
    private var tables: [SeatTable] { appState.activePlan?.tables ?? [] }

    // Section ordering mirrors web's Rules tab (src/App.jsx:13667-13939):
    // Seat Together, Keep Apart, Assign to Table, Near Venue, Near Table,
    // Category Rules. We add Couples (seat_adjacent) and a read-only Auto
    // Rules bucket (vip_priority + side_together) which web auto-generates
    // and doesn't surface a creation form for.
    private struct RuleSectionDef: Identifiable {
        let id: String
        let title: String
        let icon: String
        let color: Color
        let createType: SeatingRule.RuleType?  // nil → no "+" button (display-only)
        // Predicate now takes the full rule so sections can exclude e.g.
        // rules with a partyId (those belong to the Parties section, not
        // Seat Together — matching web's behavior).
        let matches: (SeatingRule) -> Bool
    }

    // Web's Rules tab shows 6 user-managed sections (plus Parties, which
    // is a separate concept tracked under PR B). iOS mirrors those 6 in
    // the same order. Auto-synthesized types (vip_priority, side_together,
    // and seat_adjacent — created at onboarding time) are intentionally
    // hidden, matching web's behavior.
    private var sectionDefs: [RuleSectionDef] {
        [
            RuleSectionDef(id: "seat-together", title: "Seat Together",
                icon: "person.2.fill", color: .sbSage,
                createType: .mustTogether,
                matches: { r in
                    // Exclude party-linked rules — those render in Parties.
                    if r.partyId != nil { return false }
                    if case .mustTogether = r.type { return true }
                    if case .preferTogether = r.type { return true }
                    return false
                }),
            RuleSectionDef(id: "keep-apart", title: "Keep Apart",
                icon: "arrow.left.and.right", color: .sbError,
                createType: .mustNot,
                matches: { r in if case .mustNot = r.type { return true }; return false }),
            RuleSectionDef(id: "assign-table", title: "Assign to Table",
                icon: "tablecells", color: .sbGold,
                createType: .mustTable,
                matches: { r in if case .mustTable = r.type { return true }; return false }),
            RuleSectionDef(id: "near-venue", title: "Near Venue",
                icon: "mappin.and.ellipse", color: .sbBlush,
                createType: .nearObject,
                matches: { r in if case .nearObject = r.type { return true }; return false }),
            RuleSectionDef(id: "near-table", title: "Near Table",
                icon: "rectangle.expand.vertical", color: .sbBlush,
                createType: .nearTable,
                matches: { r in if case .nearTable = r.type { return true }; return false }),
            RuleSectionDef(id: "category", title: "Category Rules",
                icon: "tag.fill", color: .sbBlush,
                createType: .categoryTogether,
                matches: { r in if case .categoryTogether = r.type { return true }; return false }),
        ]
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    headerSummary

                    partiesSection

                    ForEach(sectionDefs) { section in
                        sectionView(section)
                    }

                    Spacer(minLength: 40)
                }
                .padding(.horizontal, SBSpacing.screenMargin)
                .padding(.top, 16)
            }
            .background(Color.sbIvory)
            .navigationTitle("Seating Rules")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Color.sbGoldDk)
                }
            }
            .sheet(isPresented: $showAddRule) {
                AddRuleSheet(initialType: pendingAddType)
                    .environment(appState)
            }
            .sheet(isPresented: $showAddParty) {
                AddPartySheet().environment(appState)
            }
        }
    }

    // MARK: - Parties section
    //
    // Web's "Parties" tab section iterates state.parties[] and renders a
    // UnitCard per entry (src/App.jsx:13667-13709). iOS preserves the same
    // shape via plan.rawParties — array of {id, name, guestIds, ...}.
    // Each party has a linked must_together (or prefer_together if "soft")
    // rule with partyId back-reference; toggling Required flips the rule
    // type, mirroring web's createParty + UnitCard lock-toggle behavior.

    private var rawParties: [[String: AnyCodable]] {
        appState.activePlan?.rawParties ?? []
    }

    @ViewBuilder
    private var partiesSection: some View {
        let parties = rawParties
        let isCollapsed = collapsedSections.contains("parties")

        VStack(alignment: .leading, spacing: 8) {
            Button {
                if isCollapsed { collapsedSections.remove("parties") }
                else { collapsedSections.insert("parties") }
                HapticEngine.selection()
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "person.3.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.sbGoldDk)
                        .frame(width: 28, height: 28)
                        .background(Color.sbGold.opacity(0.15))
                        .clipShape(Circle())
                    Text("Parties")
                        .font(SBFont.bodySemibold)
                        .foregroundStyle(Color.sbCharcoal)
                    Text("(\(parties.count))")
                        .font(SBFont.caption)
                        .foregroundStyle(Color.sbWarm)
                    Spacer()
                    Image(systemName: isCollapsed ? "chevron.down" : "chevron.up")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.sbWarm)
                }
                .padding(12)
                .background(Color.sbIvory2)
                .clipShape(RoundedRectangle(cornerRadius: SBRadius.small))
            }
            .buttonStyle(.plain)

            if !isCollapsed {
                Button {
                    showAddParty = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "plus.circle")
                            .font(.system(size: 14))
                        Text("Create a Party")
                            .font(SBFont.bodySmallBold)
                    }
                    .foregroundStyle(Color.sbGoldDk)
                    .frame(maxWidth: .infinity)
                    .padding(10)
                    .overlay(
                        RoundedRectangle(cornerRadius: SBRadius.small)
                            .strokeBorder(Color.sbGold.opacity(0.4), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    )
                }
                .buttonStyle(.plain)

                if parties.isEmpty {
                    Text("Parties are guests who came together (couples, families). Locked into the same table.")
                        .font(SBFont.caption)
                        .foregroundStyle(Color.sbWarm.opacity(0.7))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                } else {
                    ForEach(parties.indices, id: \.self) { idx in
                        partyCard(parties[idx])
                    }
                }
            }
        }
    }


    private func partyCard(_ party: [String: AnyCodable]) -> some View {
        let partyId = (party["id"]?.value as? String) ?? ""
        let name = (party["name"]?.value as? String) ?? "Party"
        let guestIds = (party["guestIds"]?.value as? [String])
            ?? (party["guestIds"]?.value as? [Any])?.compactMap { $0 as? String }
            ?? []
        let memberNames = guestIds.compactMap { id in
            guests.first(where: { $0.id == id })?.displayName
        }
        let linkedRule = rules.first { $0.partyId == partyId }
        let isRequired = linkedRule?.hard ?? true

        return HStack(spacing: 12) {
            Image(systemName: "person.3.fill")
                .font(.system(size: 16))
                .foregroundStyle(Color.sbGoldDk)
                .frame(width: 36, height: 36)
                .background(Color.sbGold.opacity(0.15))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text(name)
                    .font(SBFont.bodySmallBold)
                    .foregroundStyle(Color.sbCharcoal)
                Text(memberNames.joined(separator: ", "))
                    .font(SBFont.caption)
                    .foregroundStyle(Color.sbWarm)
                    .lineLimit(2)
                if isRequired {
                    SBChip(text: "Required", variant: .gold)
                }
            }
            Spacer()

            Toggle("", isOn: Binding(
                get: { isRequired },
                set: { setPartyHard(partyId: partyId, hard: $0) }
            ))
            .tint(Color.sbGold)
            .labelsHidden()

            Button {
                deleteParty(partyId: partyId, guestIds: guestIds)
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.sbWarm2)
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .background(Color.sbIvory2)
        .clipShape(RoundedRectangle(cornerRadius: SBRadius.card))
    }

    // Web's UnitCard lock toggle (src/App.jsx around line 13442) flips the
    // linked rule's type and hard flag together. Mirror that exactly.
    private func setPartyHard(partyId: String, hard: Bool) {
        guard var plan = appState.activePlan else { return }
        guard let idx = plan.rules.firstIndex(where: { $0.partyId == partyId }) else { return }
        plan.rules[idx].hard = hard
        plan.rules[idx].type = hard ? .mustTogether : .preferTogether
        plan.rules[idx].weight = hard ? 100 : (plan.rules[idx].weight)
        appState.activePlan = plan
        Task { try? await appState.database.savePlanData(plan: plan) }
        HapticEngine.selection()
    }

    private func deleteParty(partyId: String, guestIds: [String]) {
        guard var plan = appState.activePlan else { return }
        // 1) Remove the party entry from rawParties
        var parties = plan.rawParties ?? []
        parties.removeAll { ($0["id"]?.value as? String) == partyId }
        plan.rawParties = parties.isEmpty ? nil : parties
        // 2) Remove any rules linked to this party
        plan.rules.removeAll { $0.partyId == partyId }
        // 3) Clear guest.party for the members (web sets partyId nil; iOS uses guest.party)
        for i in plan.guests.indices where guestIds.contains(plan.guests[i].id) {
            if plan.guests[i].party == partyId { plan.guests[i].party = nil }
        }
        appState.activePlan = plan
        HapticEngine.medium()
        Task { try? await appState.database.savePlanData(plan: plan) }
    }

    private var headerSummary: some View {
        HStack(spacing: 12) {
            Text("\(rules.count)")
                .font(SBFont.statNumberSmall)
                .foregroundStyle(Color.sbCharcoal)
            Text("rules total")
                .font(SBFont.bodySmall)
                .foregroundStyle(Color.sbWarm)
            Spacer()
        }
        .padding(.bottom, 4)
    }

    @ViewBuilder
    private func sectionView(_ section: RuleSectionDef) -> some View {
        let sectionRules = rules.filter { section.matches($0) }
        let isCollapsed = collapsedSections.contains(section.id)

        VStack(alignment: .leading, spacing: 8) {
            // Header (tap to collapse / expand)
            Button {
                if isCollapsed { collapsedSections.remove(section.id) }
                else { collapsedSections.insert(section.id) }
                HapticEngine.selection()
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: section.icon)
                        .font(.system(size: 14))
                        .foregroundStyle(section.color)
                        .frame(width: 28, height: 28)
                        .background(section.color.opacity(0.15))
                        .clipShape(Circle())
                    Text(section.title)
                        .font(SBFont.bodySemibold)
                        .foregroundStyle(Color.sbCharcoal)
                    Text("(\(sectionRules.count))")
                        .font(SBFont.caption)
                        .foregroundStyle(Color.sbWarm)
                    Spacer()
                    Image(systemName: isCollapsed ? "chevron.down" : "chevron.up")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.sbWarm)
                }
                .padding(12)
                .background(Color.sbIvory2)
                .clipShape(RoundedRectangle(cornerRadius: SBRadius.small))
            }
            .buttonStyle(.plain)

            if !isCollapsed {
                // Add button sits at the top so users with many rules in a
                // section don't have to scroll past the whole list to create
                // a new one.
                if let createType = section.createType {
                    Button {
                        pendingAddType = createType
                        showAddRule = true
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "plus.circle")
                                .font(.system(size: 14))
                            Text("Add \(section.title) rule")
                                .font(SBFont.bodySmallBold)
                        }
                        .foregroundStyle(Color.sbGoldDk)
                        .frame(maxWidth: .infinity)
                        .padding(10)
                        .overlay(
                            RoundedRectangle(cornerRadius: SBRadius.small)
                                .strokeBorder(Color.sbGold.opacity(0.4), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                        )
                    }
                    .buttonStyle(.plain)
                }

                if sectionRules.isEmpty && section.createType == nil {
                    // Read-only section with no rules → small placeholder so
                    // users know the section exists for web-authored content.
                    Text("None yet")
                        .font(SBFont.caption)
                        .foregroundStyle(Color.sbWarm.opacity(0.6))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                }
                ForEach(sectionRules) { rule in
                    ruleCard(rule)
                }
            }
        }
    }

    private func ruleCard(_ rule: SeatingRule) -> some View {
        HStack(spacing: 12) {
            // Icon
            Image(systemName: ruleIcon(rule.type))
                .font(.system(size: 18))
                .foregroundStyle(ruleColor(rule.type))
                .frame(width: 36, height: 36)
                .background(ruleColor(rule.type).opacity(0.15))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text(ruleLabel(rule.type))
                    .font(SBFont.bodySmallBold)
                    .foregroundStyle(Color.sbCharcoal)

                // Guest names
                let names = rule.guests.compactMap { gId in guests.first { $0.id == gId }?.displayName }
                Text(names.joined(separator: ", "))
                    .font(SBFont.caption)
                    .foregroundStyle(Color.sbWarm)
                    .lineLimit(1)

                if rule.hard {
                    SBChip(text: "Required", variant: .gold)
                }
            }

            Spacer()

            // Toggle
            Toggle("", isOn: Binding(
                get: { rule.enabled },
                set: { toggleRule(rule, enabled: $0) }
            ))
            .tint(Color.sbGold)
            .labelsHidden()

            // Delete
            Button {
                deleteRule(rule)
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.sbWarm2)
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .background(Color.sbIvory2)
        .clipShape(RoundedRectangle(cornerRadius: SBRadius.card))
    }

    private func ruleIcon(_ type: SeatingRule.RuleType) -> String {
        switch type {
        case .mustTogether:     return "person.2.fill"
        case .preferTogether:   return "person.2"
        case .mustNot:          return "arrow.left.and.right"
        case .mustTable:        return "tablecells"
        case .nearTable:        return "arrow.right.arrow.left"
        case .nearObject:       return "scope"
        case .categoryTogether: return "tag"
        case .vipPriority:      return "star.fill"
        case .sideTogether:     return "rectangle.split.2x1"
        case .seatAdjacent:     return "rectangle.connected.to.line.below"
        case .unknown:          return "questionmark.circle"
        }
    }

    private func ruleLabel(_ type: SeatingRule.RuleType) -> String {
        switch type {
        case .mustTogether:        return "Seat Together"
        case .preferTogether:      return "Prefer Together"
        case .mustNot:             return "Keep Apart"
        case .mustTable:           return "Assign to Table"
        case .nearTable:           return "Seat Near Table"
        case .nearObject:          return "Seat Near Object"
        case .categoryTogether:    return "Category Together"
        case .vipPriority:         return "VIP Priority"
        case .sideTogether:        return "Same Side Together"
        case .seatAdjacent:        return "Seat Adjacent"
        case .unknown(let raw):    return "Unknown (\(raw))"
        }
    }

    private func ruleColor(_ type: SeatingRule.RuleType) -> Color {
        switch type {
        case .mustTogether, .preferTogether:                                              return .sbSage
        case .mustNot:                                                                    return .sbError
        case .mustTable, .vipPriority:                                                    return .sbGold
        case .nearTable, .nearObject, .categoryTogether, .sideTogether, .seatAdjacent:    return .sbBlush
        case .unknown:                                                                    return .sbBlush
        }
    }

    private func toggleRule(_ rule: SeatingRule, enabled: Bool) {
        guard var plan = appState.activePlan,
              let idx = plan.rules.firstIndex(where: { $0.id == rule.id }) else { return }
        plan.rules[idx].enabled = enabled
        appState.activePlan = plan
        Task { try? await appState.database.savePlanData(plan: plan) }
    }

    private func deleteRule(_ rule: SeatingRule) {
        guard var plan = appState.activePlan else { return }
        plan.rules.removeAll { $0.id == rule.id }
        appState.activePlan = plan
        HapticEngine.medium()
        Task { try? await appState.database.savePlanData(plan: plan) }
    }
}

// MARK: - Add Rule Sheet

struct AddRuleSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    // The per-section "+" buttons in RulesView preselect a rule type. The
    // type picker still renders so users can change their mind, but the
    // sheet opens with the contextually-correct default selected.
    var initialType: SeatingRule.RuleType = .mustTogether

    @State private var ruleType: SeatingRule.RuleType = .mustTogether
    @State private var selectedGuestIds: Set<String> = []
    @State private var selectedTableId: String?
    @State private var selectedObjectId: String?
    @State private var selectedCategoryId: String?
    @State private var nameText: String = ""
    @State private var weight: Double = 50
    @State private var isHard = false
    @State private var searchText = ""

    private var guests: [Guest] { appState.activePlan?.guests ?? [] }
    private var tables: [SeatTable] { appState.activePlan?.tables ?? [] }
    private var objects: [RoomObject] { appState.activePlan?.objects ?? [] }

    private var filteredGuests: [Guest] {
        if searchText.isEmpty { return guests }
        return guests.filter { $0.displayName.localizedCaseInsensitiveContains(searchText) }
    }

    private var canonicalCategories: [(id: String, name: String, color: String?)] {
        guard let raw = appState.activePlan?.rawCategories, !raw.isEmpty else { return [] }
        return raw.compactMap { entry in
            guard let id = entry["id"]?.value as? String else { return nil }
            let name = (entry["name"]?.value as? String) ?? id
            let color = entry["color"]?.value as? String
            return (id, name, color)
        }
    }

    // Per-type minimum guest counts (matches web's RULE_TYPES.minGuests).
    private var minGuestsForType: Int {
        switch ruleType {
        case .mustTogether, .preferTogether, .mustNot, .seatAdjacent: return 2
        case .mustTable, .nearTable, .nearObject: return 1
        case .categoryTogether, .vipPriority, .sideTogether, .unknown: return 0
        }
    }

    private var canSubmit: Bool {
        switch ruleType {
        case .mustTable, .nearTable:
            return selectedGuestIds.count >= minGuestsForType && selectedTableId != nil
        case .nearObject:
            return selectedGuestIds.count >= minGuestsForType && selectedObjectId != nil
        case .categoryTogether:
            return selectedCategoryId != nil
        case .seatAdjacent:
            return selectedGuestIds.count == 2  // exactly 2
        default:
            return selectedGuestIds.count >= minGuestsForType
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    typeHeader

                    // Type-specific form bodies. Layout below matches web's
                    // per-type create modals (src/App.jsx around line 13100+).
                    switch ruleType {
                    case .mustTogether, .preferTogether:
                        seatTogetherForm
                    case .mustNot:
                        keepApartForm
                    case .mustTable:
                        assignToTableForm
                    case .nearTable:
                        nearTableForm
                    case .nearObject:
                        nearVenueForm
                    case .categoryTogether:
                        categoryRuleForm
                    default:
                        Text("This rule type is not authored on iOS.")
                            .font(SBFont.body)
                            .foregroundStyle(Color.sbWarm)
                    }

                    Spacer(minLength: 40)
                }
                .padding(.horizontal, SBSpacing.screenMargin)
                .padding(.top, 16)
            }
            .background(Color.sbIvory)
            .navigationTitle("Add Rule")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Color.sbWarm)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { addRule() }
                        .font(SBFont.bodySemibold)
                        .foregroundStyle(Color.sbGoldDk)
                        .disabled(!canSubmit)
                }
            }
            .onAppear {
                ruleType = initialType
                // For Keep Apart, web auto-derives hard from weight ≥ 90.
                // Default to a soft 75 so users start in the soft zone.
                if case .mustNot = initialType { weight = 75 }
                // Near rules default to weight 80 (matches web defaults).
                if case .nearTable = initialType { weight = 80 }
                if case .nearObject = initialType { weight = 80 }
                // Category rules default to 40 (matches web's createCategoryRule).
                if case .categoryTogether = initialType { weight = 40 }
            }
        }
    }

    private var typeHeader: some View {
        HStack(spacing: 12) {
            Image(systemName: typeIconName)
                .font(.system(size: 16))
                .foregroundStyle(typeColor)
                .frame(width: 32, height: 32)
                .background(typeColor.opacity(0.15))
                .clipShape(Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(typeTitle)
                    .font(SBFont.bodySemibold)
                    .foregroundStyle(Color.sbCharcoal)
                Text(typeSubtitle)
                    .font(SBFont.caption)
                    .foregroundStyle(Color.sbWarm)
            }
            Spacer()
        }
    }

    // MARK: - Per-type forms

    private var seatTogetherForm: some View {
        VStack(alignment: .leading, spacing: 20) {
            formSection("GROUP NAME (OPTIONAL)") {
                TextField("e.g. Smith Family", text: $nameText)
                    .font(SBFont.body)
                    .padding(12)
                    .background(Color.sbIvory2)
                    .clipShape(RoundedRectangle(cornerRadius: SBRadius.small))
            }
            // Importance + Required come BEFORE guests so users see them
            // without scrolling past the (long) guest list.
            requiredToggleSection
            if !isHard {
                weightSliderSection(label: weightImportanceLabel)
            }
            guestPickerSection
        }
    }

    // Web-style label: "50% - Important" / "75% - Strong preference" / etc.
    private var weightImportanceLabel: String {
        let pct = Int(weight)
        switch pct {
        case 90...100: return "\(pct)% - Required-strength"
        case 75..<90:  return "\(pct)% - Strong preference"
        case 50..<75:  return "\(pct)% - Important"
        case 25..<50:  return "\(pct)% - Mild preference"
        default:       return "\(pct)% - Optional"
        }
    }

    private var keepApartForm: some View {
        VStack(alignment: .leading, spacing: 20) {
            guestPickerSection
            // Web's createKeepApartRule sets hard = (weight >= 90) implicitly,
            // so iOS surfaces a single weight slider with a contextual label.
            weightSliderSection(label: weight >= 90 ? "Required (high priority)" : "Importance (preferred)")
        }
    }

    private var assignToTableForm: some View {
        VStack(alignment: .leading, spacing: 20) {
            guestPickerSection
            formSection("ASSIGN TO TABLE") { tableChips }
        }
    }

    private var nearTableForm: some View {
        VStack(alignment: .leading, spacing: 20) {
            guestPickerSection
            formSection("NEAR WHICH TABLE") { tableChips }
            weightSliderSection(label: "Importance")
        }
    }

    private var nearVenueForm: some View {
        VStack(alignment: .leading, spacing: 20) {
            guestPickerSection
            formSection("NEAR WHICH VENUE OBJECT") {
                if objects.isEmpty {
                    Text("No venue objects in this plan yet. Add one from the Edit tab.")
                        .font(SBFont.caption)
                        .foregroundStyle(Color.sbWarm)
                } else {
                    objectChips
                }
            }
            weightSliderSection(label: "Importance")
        }
    }

    private var categoryRuleForm: some View {
        VStack(alignment: .leading, spacing: 20) {
            formSection("CATEGORY") {
                if canonicalCategories.isEmpty {
                    Text("No categories in this plan yet. Add categories from the Guests tab first.")
                        .font(SBFont.caption)
                        .foregroundStyle(Color.sbWarm)
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(canonicalCategories, id: \.id) { cat in
                                Button {
                                    selectedCategoryId = cat.id
                                    HapticEngine.selection()
                                } label: {
                                    SBChip(
                                        text: cat.name,
                                        variant: selectedCategoryId == cat.id ? .gold : .default
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
            weightSliderSection(label: "How strongly to keep this category together")
        }
    }

    // MARK: - Reusable form pieces

    private var guestPickerSection: some View {
        formSection("SELECT GUESTS") {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(Color.sbWarm)
                TextField("Search guests...", text: $searchText)
                    .font(SBFont.body)
            }
            .padding(10)
            .background(Color.sbIvory2)
            .clipShape(RoundedRectangle(cornerRadius: SBRadius.small))

            VStack(spacing: 4) {
                ForEach(filteredGuests.prefix(50)) { guest in
                    Button {
                        if selectedGuestIds.contains(guest.id) {
                            selectedGuestIds.remove(guest.id)
                        } else {
                            // Seat Adjacent caps at 2 guests.
                            if case .seatAdjacent = ruleType,
                               selectedGuestIds.count >= 2 { return }
                            selectedGuestIds.insert(guest.id)
                        }
                        HapticEngine.selection()
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: selectedGuestIds.contains(guest.id) ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(selectedGuestIds.contains(guest.id) ? Color.sbGold : Color.sbWarm2)
                            Text(guest.displayName)
                                .font(SBFont.bodySmall)
                                .foregroundStyle(Color.sbCharcoal)
                            Spacer()
                        }
                        .padding(.vertical, 6)
                    }
                    .buttonStyle(.plain)
                }
            }

            Text("\(selectedGuestIds.count) selected")
                .font(SBFont.caption)
                .foregroundStyle(Color.sbWarm)
        }
    }

    private var requiredToggleSection: some View {
        Toggle(isOn: $isHard) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Required").font(SBFont.bodySmallBold)
                Text(isHard
                     ? "Must sit at the same table"
                     : "Try to seat together if possible")
                    .font(SBFont.caption)
                    .foregroundStyle(Color.sbWarm)
            }
        }
        .tint(Color.sbGold)
        .padding(12)
        .background(Color.sbIvory2)
        .clipShape(RoundedRectangle(cornerRadius: SBRadius.small))
    }

    private func weightSliderSection(label: String) -> some View {
        formSection("IMPORTANCE") {
            VStack(alignment: .leading, spacing: 8) {
                Text(label)
                    .font(SBFont.bodySmallBold)
                    .foregroundStyle(Color.sbGoldDk)
                Slider(value: $weight, in: 1...100, step: 1).tint(Color.sbGold)
                HStack {
                    Text("Optional").font(SBFont.caption).foregroundStyle(Color.sbWarm)
                    Spacer()
                    Text("Required").font(SBFont.caption).foregroundStyle(Color.sbWarm)
                }
            }
            .padding(12)
            .background(Color.sbIvory2)
            .clipShape(RoundedRectangle(cornerRadius: SBRadius.small))
        }
    }

    private var tableChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(tables) { table in
                    Button {
                        selectedTableId = table.id
                        HapticEngine.selection()
                    } label: {
                        SBChip(text: table.name, variant: selectedTableId == table.id ? .gold : .default)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var objectChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(objects) { obj in
                    Button {
                        selectedObjectId = obj.id
                        HapticEngine.selection()
                    } label: {
                        SBChip(text: obj.name, variant: selectedObjectId == obj.id ? .gold : .default)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Type header metadata

    private var typeIconName: String {
        switch ruleType {
        case .mustTogether, .preferTogether: return "person.2.fill"
        case .mustNot: return "arrow.left.and.right"
        case .mustTable: return "tablecells"
        case .nearTable: return "rectangle.expand.vertical"
        case .nearObject: return "mappin.and.ellipse"
        case .categoryTogether: return "tag.fill"
        case .seatAdjacent: return "heart.fill"
        case .vipPriority: return "star.fill"
        case .sideTogether: return "rectangle.split.2x1"
        case .unknown: return "questionmark.circle"
        }
    }

    private var typeColor: Color {
        switch ruleType {
        case .mustTogether, .preferTogether: return .sbSage
        case .mustNot: return .sbError
        case .mustTable: return .sbGold
        case .nearTable, .nearObject, .categoryTogether, .seatAdjacent: return .sbBlush
        case .vipPriority: return .sbGold
        case .sideTogether: return .sbBlush
        case .unknown: return .sbWarm
        }
    }

    private var typeTitle: String {
        switch ruleType {
        case .mustTogether, .preferTogether: return "Seat Together"
        case .mustNot: return "Keep Apart"
        case .mustTable: return "Assign to Table"
        case .nearTable: return "Near Table"
        case .nearObject: return "Near Venue"
        case .categoryTogether: return "Category Rule"
        case .seatAdjacent: return "Seat Adjacent"
        case .vipPriority: return "VIP Priority"
        case .sideTogether: return "Same Side Together"
        case .unknown(let raw): return "Unknown (\(raw))"
        }
    }

    private var typeSubtitle: String {
        switch ruleType {
        case .mustTogether, .preferTogether:
            return "These guests should be at the same table"
        case .mustNot:
            return "These guests should NOT be at the same table"
        case .mustTable:
            return "These guests must sit at this table"
        case .nearTable:
            return "Seat these guests close to the chosen table"
        case .nearObject:
            return "Seat these guests close to the chosen venue object"
        case .categoryTogether:
            return "Try to keep guests in this category at the same table"
        case .seatAdjacent:
            return "Couples: sit literally next to each other"
        case .vipPriority:
            return "Auto-applied to all VIP guests"
        case .sideTogether:
            return "Auto-applied to bride/groom side guests"
        case .unknown:
            return "This type is preserved on round-trip but not editable on iOS"
        }
    }

    private func formSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(SBFont.capsLabel)
                .foregroundStyle(Color.sbWarm)
                .letterSpacing(1.5)
            content()
        }
    }

    // MARK: - Write path
    //
    // Each branch below mirrors the corresponding web `createX` function so
    // the rule shapes round-trip cleanly with web (parity verification table
    // in the PR description). Critical: Seat Together rules ALSO write a
    // group entry into rawGroups so they appear in web's Seat Together
    // section, which iterates state.groups[] (not rules of type
    // prefer_together).
    private func addRule() {
        guard var plan = appState.activePlan, canSubmit else { return }
        let ruleId = UUID().uuidString

        switch ruleType {
        case .mustTogether, .preferTogether:
            let groupId = UUID().uuidString
            let groupName = computedGroupName()
            let groupEntry: [String: AnyCodable] = [
                "id": AnyCodable(groupId),
                "name": AnyCodable(groupName),
                // NOTE: groups use 'members' (not 'guestIds' — that's parties).
                "members": AnyCodable(Array(selectedGuestIds)),
                "priority": AnyCodable(Int(weight)),
                "fallbackGroupId": AnyCodable(NSNull()),
                "color": AnyCodable("#9CAF88")
            ]
            var groups = plan.rawGroups ?? []
            groups.append(groupEntry)
            plan.rawGroups = groups

            let rule = SeatingRule(
                id: ruleId,
                type: isHard ? .mustTogether : .preferTogether,
                guests: Array(selectedGuestIds),
                tableId: nil,
                weight: isHard ? 100 : Int(weight),
                hard: isHard,
                enabled: true,
                categoryId: nil, objectId: nil, sideValue: nil,
                desc: groupName,
                auto: nil, source: "manual",
                partyId: nil, groupId: groupId
            )
            plan.rules.append(rule)

        case .mustNot:
            let names = selectedGuestIds.compactMap { id in
                guests.first(where: { $0.id == id })?.displayName
            }.joined(separator: " & ")
            let rule = SeatingRule(
                id: ruleId,
                type: .mustNot,
                guests: Array(selectedGuestIds),
                tableId: nil,
                weight: Int(weight),
                hard: weight >= 90,
                enabled: true,
                categoryId: nil, objectId: nil, sideValue: nil,
                desc: names,
                auto: nil, source: "manual",
                partyId: nil, groupId: nil
            )
            plan.rules.append(rule)

        case .mustTable:
            guard let tableId = selectedTableId else { return }
            let rule = SeatingRule(
                id: ruleId,
                type: .mustTable,
                guests: Array(selectedGuestIds),
                tableId: tableId,
                weight: 100,
                hard: true,
                enabled: true,
                categoryId: nil, objectId: nil, sideValue: nil,
                desc: nil,
                auto: nil, source: "manual",
                partyId: nil, groupId: nil
            )
            plan.rules.append(rule)

        case .nearTable:
            guard let tableId = selectedTableId else { return }
            let table = tables.first { $0.id == tableId }
            let names = selectedGuestIds.compactMap { id in
                guests.first(where: { $0.id == id })?.displayName
            }.joined(separator: ", ")
            let rule = SeatingRule(
                id: ruleId,
                type: .nearTable,
                guests: Array(selectedGuestIds),
                tableId: tableId,
                weight: Int(weight),
                hard: false,
                enabled: true,
                categoryId: nil, objectId: nil, sideValue: nil,
                desc: "\(names) near \(table?.name ?? "Table")",
                auto: nil, source: "manual",
                partyId: nil, groupId: nil
            )
            plan.rules.append(rule)

        case .nearObject:
            guard let objId = selectedObjectId else { return }
            let obj = objects.first { $0.id == objId }
            let names = selectedGuestIds.compactMap { id in
                guests.first(where: { $0.id == id })?.displayName
            }.joined(separator: ", ")
            let rule = SeatingRule(
                id: ruleId,
                type: .nearObject,
                guests: Array(selectedGuestIds),
                tableId: nil,
                weight: Int(weight),
                hard: false,
                enabled: true,
                categoryId: nil, objectId: objId, sideValue: nil,
                desc: "\(names) near \(obj?.name ?? "Venue object")",
                auto: nil, source: "manual",
                partyId: nil, groupId: nil
            )
            plan.rules.append(rule)

        case .categoryTogether:
            guard let catId = selectedCategoryId else { return }
            let catName = canonicalCategories.first { $0.id == catId }?.name ?? "Category"
            let rule = SeatingRule(
                id: ruleId,
                type: .categoryTogether,
                guests: [],  // intentionally empty — resolved at eval from categoryId
                tableId: nil,
                weight: Int(weight),
                hard: false,
                enabled: true,
                categoryId: catId, objectId: nil, sideValue: nil,
                desc: "\(catName) together at \(Int(weight))%",
                auto: nil, source: "manual",
                partyId: nil, groupId: nil
            )
            plan.rules.append(rule)

        default:
            return
        }

        appState.activePlan = plan
        HapticEngine.success()
        Task { try? await appState.database.savePlanData(plan: plan) }
        dismiss()
    }

    // Web's createSeatTogetherGroup builds a default name by joining first
    // names with " & " when no explicit name is set. Mirror that exactly.
    private func computedGroupName() -> String {
        let trimmed = nameText.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty { return trimmed }
        let names = selectedGuestIds.compactMap { id in
            guests.first(where: { $0.id == id })?.displayName.split(separator: " ").first.map(String.init)
        }
        return names.joined(separator: " & ")
    }
}

// MARK: - Add Party Sheet
//
// Mirrors web's createParty (src/App.jsx:13094-13125):
// - Generate partyId
// - Append entry to state.parties: {id, name, guestIds}  (Note: parties use
//   guestIds, NOT members — that distinction was the 2026-05-03 incident)
// - Update each member's guest.partyId = partyId
// - Create a HARD must_together rule with partyId back-ref, source: "party",
//   auto: true, weight: 100, hard: true

struct AddPartySheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var nameText: String = ""
    @State private var selectedGuestIds: Set<String> = []
    @State private var searchText: String = ""

    private var guests: [Guest] { appState.activePlan?.guests ?? [] }

    private var filteredGuests: [Guest] {
        if searchText.isEmpty { return guests }
        return guests.filter { $0.displayName.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    formSection("PARTY NAME (OPTIONAL)") {
                        TextField("e.g. Smith Family", text: $nameText)
                            .font(SBFont.body)
                            .padding(12)
                            .background(Color.sbIvory2)
                            .clipShape(RoundedRectangle(cornerRadius: SBRadius.small))
                    }

                    formSection("MEMBERS") {
                        HStack(spacing: 8) {
                            Image(systemName: "magnifyingglass")
                                .foregroundStyle(Color.sbWarm)
                            TextField("Search guests...", text: $searchText)
                                .font(SBFont.body)
                        }
                        .padding(10)
                        .background(Color.sbIvory2)
                        .clipShape(RoundedRectangle(cornerRadius: SBRadius.small))

                        VStack(spacing: 4) {
                            ForEach(filteredGuests.prefix(50)) { guest in
                                Button {
                                    if selectedGuestIds.contains(guest.id) {
                                        selectedGuestIds.remove(guest.id)
                                    } else {
                                        selectedGuestIds.insert(guest.id)
                                    }
                                    HapticEngine.selection()
                                } label: {
                                    HStack(spacing: 10) {
                                        Image(systemName: selectedGuestIds.contains(guest.id) ? "checkmark.circle.fill" : "circle")
                                            .foregroundStyle(selectedGuestIds.contains(guest.id) ? Color.sbGold : Color.sbWarm2)
                                        Text(guest.displayName)
                                            .font(SBFont.bodySmall)
                                            .foregroundStyle(Color.sbCharcoal)
                                        Spacer()
                                    }
                                    .padding(.vertical, 6)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        Text("\(selectedGuestIds.count) selected (need at least 2)")
                            .font(SBFont.caption)
                            .foregroundStyle(Color.sbWarm)
                    }

                    Text("Parties are locked into the same table. Use Seat Together for softer preferences.")
                        .font(SBFont.caption)
                        .foregroundStyle(Color.sbWarm.opacity(0.7))
                        .padding(.horizontal, 4)

                    Spacer(minLength: 40)
                }
                .padding(.horizontal, SBSpacing.screenMargin)
                .padding(.top, 16)
            }
            .background(Color.sbIvory)
            .navigationTitle("Create a Party")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Color.sbWarm)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") { createParty() }
                        .font(SBFont.bodySemibold)
                        .foregroundStyle(Color.sbGoldDk)
                        .disabled(selectedGuestIds.count < 2)
                }
            }
        }
    }

    private func formSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(SBFont.capsLabel)
                .foregroundStyle(Color.sbWarm)
                .letterSpacing(1.5)
            content()
        }
    }

    private func createParty() {
        guard var plan = appState.activePlan, selectedGuestIds.count >= 2 else { return }
        let partyId = UUID().uuidString

        // Compute a default name from member first-names if user left it blank.
        let trimmed = nameText.trimmingCharacters(in: .whitespaces)
        let partyName: String = {
            if !trimmed.isEmpty { return trimmed }
            let firsts = selectedGuestIds.compactMap { id in
                guests.first(where: { $0.id == id })?.displayName.split(separator: " ").first.map(String.init)
            }
            return firsts.joined(separator: " & ")
        }()

        // 1) Append entry to rawParties
        let entry: [String: AnyCodable] = [
            "id": AnyCodable(partyId),
            "name": AnyCodable(partyName),
            "guestIds": AnyCodable(Array(selectedGuestIds)),
            "priority": AnyCodable(100),
            "color": AnyCodable("#C9A961"),
        ]
        var parties = plan.rawParties ?? []
        parties.append(entry)
        plan.rawParties = parties

        // 2) Set guest.party = partyId for each member
        for i in plan.guests.indices where selectedGuestIds.contains(plan.guests[i].id) {
            plan.guests[i].party = partyId
        }

        // 3) Create the linked must_together rule (hard, weight 100,
        //    source 'party', auto: true, partyId back-ref). Matches web's
        //    createParty exactly.
        let rule = SeatingRule(
            id: UUID().uuidString,
            type: .mustTogether,
            guests: Array(selectedGuestIds),
            tableId: nil,
            weight: 100,
            hard: true,
            enabled: true,
            categoryId: nil, objectId: nil, sideValue: nil,
            desc: partyName,
            auto: true, source: "party",
            partyId: partyId, groupId: nil
        )
        plan.rules.append(rule)

        appState.activePlan = plan
        HapticEngine.success()
        Task { try? await appState.database.savePlanData(plan: plan) }
        dismiss()
    }
}

#Preview {
    RulesView()
        .environment(AppState())
}

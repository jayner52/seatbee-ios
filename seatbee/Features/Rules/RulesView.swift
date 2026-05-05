import SwiftUI

struct RulesView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var showAddRule = false
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
        let matches: (SeatingRule.RuleType) -> Bool
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
                matches: { t in
                    if case .mustTogether = t { return true }
                    if case .preferTogether = t { return true }
                    return false
                }),
            RuleSectionDef(id: "keep-apart", title: "Keep Apart",
                icon: "arrow.left.and.right", color: .sbError,
                createType: .mustNot,
                matches: { t in if case .mustNot = t { return true }; return false }),
            RuleSectionDef(id: "assign-table", title: "Assign to Table",
                icon: "tablecells", color: .sbGold,
                createType: .mustTable,
                matches: { t in if case .mustTable = t { return true }; return false }),
            RuleSectionDef(id: "near-venue", title: "Near Venue",
                icon: "mappin.and.ellipse", color: .sbBlush,
                createType: nil,  // PR A2
                matches: { t in if case .nearObject = t { return true }; return false }),
            RuleSectionDef(id: "near-table", title: "Near Table",
                icon: "rectangle.expand.vertical", color: .sbBlush,
                createType: nil,  // PR A2
                matches: { t in if case .nearTable = t { return true }; return false }),
            RuleSectionDef(id: "category", title: "Category Rules",
                icon: "tag.fill", color: .sbBlush,
                createType: nil,  // PR A2
                matches: { t in if case .categoryTogether = t { return true }; return false }),
        ]
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    headerSummary

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
        }
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
        let sectionRules = rules.filter { section.matches($0.type) }
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
    @State private var weight: Double = 50
    @State private var isHard = false
    @State private var searchText = ""

    private var guests: [Guest] { appState.activePlan?.guests ?? [] }
    private var tables: [SeatTable] { appState.activePlan?.tables ?? [] }

    private var filteredGuests: [Guest] {
        if searchText.isEmpty { return guests }
        return guests.filter { $0.displayName.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Rule type
                    formSection("RULE TYPE") {
                        VStack(spacing: 8) {
                            ruleTypeButton("Seat Together", type: .mustTogether, icon: "person.2.fill")
                            ruleTypeButton("Keep Apart", type: .mustNot, icon: "arrow.left.and.right")
                            ruleTypeButton("Assign to Table", type: .mustTable, icon: "tablecells")
                        }
                    }

                    // Select guests
                    formSection("SELECT GUESTS") {
                        // Search
                        HStack(spacing: 8) {
                            Image(systemName: "magnifyingglass")
                                .foregroundStyle(Color.sbWarm)
                            TextField("Search guests...", text: $searchText)
                                .font(SBFont.body)
                        }
                        .padding(10)
                        .background(Color.sbIvory2)
                        .clipShape(RoundedRectangle(cornerRadius: SBRadius.small))

                        // Guest list
                        VStack(spacing: 4) {
                            ForEach(filteredGuests.prefix(20)) { guest in
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

                        Text("\(selectedGuestIds.count) selected")
                            .font(SBFont.caption)
                            .foregroundStyle(Color.sbWarm)
                    }

                    // Table selection (for .mustTable rules)
                    if ruleType == .mustTable {
                        formSection("ASSIGN TO TABLE") {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(tables) { table in
                                        Button {
                                            selectedTableId = table.id
                                        } label: {
                                            SBChip(
                                                text: table.name,
                                                variant: selectedTableId == table.id ? .gold : .default
                                            )
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                        }
                    }

                    // Weight
                    formSection("IMPORTANCE") {
                        VStack(spacing: 4) {
                            Slider(value: $weight, in: 1...100, step: 1)
                                .tint(Color.sbGold)
                            HStack {
                                Text("Low")
                                    .font(SBFont.caption)
                                    .foregroundStyle(Color.sbWarm)
                                Spacer()
                                Text("\(Int(weight))")
                                    .font(SBFont.bodySmallBold)
                                    .foregroundStyle(Color.sbGoldDk)
                                Spacer()
                                Text("High")
                                    .font(SBFont.caption)
                                    .foregroundStyle(Color.sbWarm)
                            }
                        }

                        Toggle(isOn: $isHard) {
                            Text("Required (must be satisfied)")
                                .font(SBFont.bodySmall)
                        }
                        .tint(Color.sbGold)
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
                        .disabled(selectedGuestIds.count < 2 && ruleType != .mustTable)
                }
            }
            .onAppear { ruleType = initialType }
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

    private func ruleTypeButton(_ label: String, type: SeatingRule.RuleType, icon: String) -> some View {
        Button {
            ruleType = type
            HapticEngine.selection()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 16))
                    .frame(width: 24)
                Text(label)
                    .font(SBFont.bodySemibold)
                Spacer()
                if ruleType == type {
                    Image(systemName: "checkmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Color.sbGold)
                }
            }
            .foregroundStyle(ruleType == type ? Color.sbCharcoal : Color.sbWarm)
            .padding(12)
            .background(ruleType == type ? Color.sbChampagne : Color.sbIvory2)
            .clipShape(RoundedRectangle(cornerRadius: SBRadius.small))
        }
        .buttonStyle(.plain)
    }

    private func addRule() {
        guard var plan = appState.activePlan else { return }

        let rule = SeatingRule(
            id: UUID().uuidString,
            type: ruleType,
            guests: Array(selectedGuestIds),
            tableId: ruleType == .mustTable ? selectedTableId : nil,
            weight: Int(weight),
            hard: isHard,
            enabled: true,
            categoryId: nil,
            objectId: nil,
            sideValue: nil,
            desc: nil,
            auto: nil,
            source: "manual",
            partyId: nil,
            groupId: nil
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

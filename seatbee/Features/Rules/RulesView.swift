import SwiftUI

struct RulesView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var showAddRule = false

    private var rules: [SeatingRule] { appState.activePlan?.rules ?? [] }
    private var guests: [Guest] { appState.activePlan?.guests ?? [] }
    private var tables: [SeatTable] { appState.activePlan?.tables ?? [] }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if rules.isEmpty {
                        // Empty state
                        VStack(spacing: 16) {
                            Spacer().frame(height: 40)
                            Image(systemName: "list.bullet.rectangle")
                                .font(.system(size: 40))
                                .foregroundStyle(Color.sbWarm2)
                            Text("No rules yet")
                                .font(SBFont.displaySmall)
                                .foregroundStyle(Color.sbCharcoal)
                            Text("Add rules to control who sits together or apart")
                                .font(SBFont.body)
                                .foregroundStyle(Color.sbWarm)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                    } else {
                        ForEach(rules) { rule in
                            ruleCard(rule)
                        }
                    }

                    SBButton(title: "Add Rule", icon: "plus", variant: .gold, fullWidth: true) {
                        showAddRule = true
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
                AddRuleSheet()
                    .environment(appState)
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
        case .seatTogether: return "person.2.fill"
        case .keepApart: return "arrow.left.and.right"
        case .assignTable: return "tablecells"
        case .seatNear: return "arrow.right.arrow.left"
        }
    }

    private func ruleLabel(_ type: SeatingRule.RuleType) -> String {
        switch type {
        case .seatTogether: return "Seat Together"
        case .keepApart: return "Keep Apart"
        case .assignTable: return "Assign to Table"
        case .seatNear: return "Seat Nearby"
        }
    }

    private func ruleColor(_ type: SeatingRule.RuleType) -> Color {
        switch type {
        case .seatTogether: return .sbSage
        case .keepApart: return .sbError
        case .assignTable: return .sbGold
        case .seatNear: return .sbBlush
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

    @State private var ruleType: SeatingRule.RuleType = .seatTogether
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
                            ruleTypeButton("Seat Together", type: .seatTogether, icon: "person.2.fill")
                            ruleTypeButton("Keep Apart", type: .keepApart, icon: "arrow.left.and.right")
                            ruleTypeButton("Assign to Table", type: .assignTable, icon: "tablecells")
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

                    // Table selection (for assignTable)
                    if ruleType == .assignTable {
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
                        .disabled(selectedGuestIds.count < 2 && ruleType != .assignTable)
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
            tableId: ruleType == .assignTable ? selectedTableId : nil,
            weight: Int(weight),
            hard: isHard,
            enabled: true
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

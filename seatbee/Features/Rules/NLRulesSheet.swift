import SwiftUI

/// Natural-language AI rules — iOS port of web's "Describe your rules" box
/// on the Rules tab (src/App.jsx:13699-13760 + src/lib/ai.js parseRulesFromText).
///
/// Flow: type wishes → AI drafts structured rules → review checklist (uncheck
/// any) + "Couldn't add" reasons for unmatched wishes → confirm appends to
/// plan.rules and saves. All rule VALUES mirror web's validateProposed exactly
/// (see AIService.validateProposedRules) — rules persist to the shared plan
/// JSONB, so shape/value parity with web is load-bearing (PARITY.md).
struct NLRulesSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    enum Phase { case input, loading, review }

    @State private var phase: Phase = .input
    @State private var wishText = ""
    @State private var proposed: [SeatingRule] = []
    @State private var picked: Set<String> = []
    @State private var skipped: [String] = []
    @State private var errorMessage: String?

    private let ai = AIService()

    // Web's textarea placeholder, verbatim.
    private let placeholder = "e.g. Keep Uncle Bob away from the Hendersons, seat Grandma near the entrance, put the college friends together"

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    switch phase {
                    case .input: inputPhase
                    case .loading: loadingPhase
                    case .review: reviewPhase
                    }
                }
                .padding(.horizontal, SBSpacing.screenMargin)
                .padding(.top, 16)
            }
            .background(Color.sbIvory)
            .navigationTitle("Describe Your Rules")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Color.sbWarm)
                }
            }
        }
    }

    // MARK: - Input

    private var inputPhase: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.sbGold)
                Text("Type your wishes — AI drafts the rules")
                    .font(SBFont.caption)
                    .foregroundStyle(Color.sbWarm)
            }

            ZStack(alignment: .topLeading) {
                if wishText.isEmpty {
                    Text(placeholder)
                        .font(SBFont.body)
                        .foregroundStyle(Color.sbWarm2)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 14)
                        .allowsHitTesting(false)
                }
                TextEditor(text: $wishText)
                    .font(SBFont.body)
                    .foregroundStyle(Color.sbCharcoal)
                    .scrollContentBackground(.hidden)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .frame(minHeight: 120)
            }
            .background(Color.sbIvory2)
            .clipShape(RoundedRectangle(cornerRadius: SBRadius.small))
            .overlay(
                RoundedRectangle(cornerRadius: SBRadius.small)
                    .strokeBorder(Color.sbGold.opacity(0.25), lineWidth: 1)
            )

            if let errorMessage {
                Text(errorMessage)
                    .font(SBFont.caption)
                    .foregroundStyle(Color.sbError)
            }

            SBButton(
                title: "Draft rules from text",
                icon: "sparkles",
                variant: .gold,
                fullWidth: true
            ) {
                draftRules()
            }
            .disabled(wishText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .opacity(wishText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.5 : 1)
        }
    }

    // MARK: - Loading

    private var loadingPhase: some View {
        VStack(spacing: 16) {
            HoneycombLoader()
                .frame(width: 180, height: 180)
            Text("Reading your wishes…")
                .font(SBFont.bodySemibold)
                .foregroundStyle(Color.sbCharcoal)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }

    // MARK: - Review

    private var reviewPhase: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !proposed.isEmpty {
                // Web copy: "Drafted N rule(s) — uncheck any you don't want:"
                Text("Drafted \(proposed.count) rule\(proposed.count == 1 ? "" : "s") — uncheck any you don't want:")
                    .font(SBFont.caption)
                    .foregroundStyle(Color.sbWarm)

                VStack(spacing: 8) {
                    ForEach(proposed) { rule in
                        proposedRow(rule)
                    }
                }
            }

            if !skipped.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    // Web copy: "Couldn't add N:"
                    Text("Couldn't add \(skipped.count):")
                        .font(SBFont.bodySmallBold)
                        .foregroundStyle(Color.sbGoldDk)
                    Text(skipped.joined(separator: " · "))
                        .font(SBFont.caption)
                        .foregroundStyle(Color.sbWarm)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.sbGold.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: SBRadius.small))
            }

            if !proposed.isEmpty {
                SBButton(
                    title: "Add \(picked.count) rule\(picked.count == 1 ? "" : "s")",
                    icon: "checkmark",
                    variant: .gold,
                    fullWidth: true
                ) {
                    addPickedRules()
                }
                .disabled(picked.isEmpty)
                .opacity(picked.isEmpty ? 0.5 : 1)
            }

            SBButton(title: "Back", variant: .ghost, fullWidth: true) {
                proposed = []
                picked = []
                skipped = []
                phase = .input
            }
        }
    }

    private func proposedRow(_ rule: SeatingRule) -> some View {
        let isPicked = picked.contains(rule.id)
        return Button {
            if isPicked { picked.remove(rule.id) } else { picked.insert(rule.id) }
            HapticEngine.selection()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: isPicked ? "checkmark.square.fill" : "square")
                    .font(.system(size: 18))
                    .foregroundStyle(isPicked ? Color.sbGold : Color.sbWarm2)

                Image(systemName: ruleIcon(rule.type))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(ruleColor(rule.type))
                    .frame(width: 26, height: 26)
                    .background(ruleColor(rule.type).opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 6))

                VStack(alignment: .leading, spacing: 2) {
                    Text(describe(rule))
                        .font(SBFont.bodySmallBold)
                        .foregroundStyle(Color.sbCharcoal)
                        .multilineTextAlignment(.leading)
                    Text(typeLabel(rule.type) + (rule.hard ? " · Must" : ""))
                        .font(SBFont.caption)
                        .foregroundStyle(Color.sbWarm)
                }
                Spacer()
            }
            .padding(10)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: SBRadius.small))
            .overlay(
                RoundedRectangle(cornerRadius: SBRadius.small)
                    .strokeBorder(isPicked ? Color.sbGold.opacity(0.4) : Color.sbWarm2.opacity(0.3), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Actions

    private func draftRules() {
        // Pro gate — mirrors web checkTierLimit('ai_generate') before any call.
        guard appState.activePlanLimits.aiGenerate else {
            HapticEngine.error()
            appState.upgradeTrigger = "ai_rules"
            appState.showUpgrade = true
            return
        }
        guard let plan = appState.activePlan else { return }
        let text = wishText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        errorMessage = nil
        phase = .loading

        let context = AIService.NLRulesContext(
            guests: plan.guests.map { .init(id: $0.id, name: $0.name.trimmingCharacters(in: .whitespaces)) },
            tables: plan.tables.map { .init(id: $0.id, name: $0.name) },
            objects: plan.objects.map { .init(id: $0.id, name: $0.name) },
            categories: canonicalCategories.map { .init(id: $0.id, name: $0.name) }
        )

        Task {
            do {
                let result = try await ai.parseRulesFromText(text, context: context)
                let validated = AIService.validateProposedRules(
                    result.rules,
                    guestIds: Set(plan.guests.map(\.id)),
                    tableIds: Set(plan.tables.map(\.id)),
                    objectIds: Set(plan.objects.map(\.id)),
                    categoryIds: Set(canonicalCategories.map(\.id))
                )
                await MainActor.run {
                    if validated.isEmpty && result.skipped.isEmpty {
                        // Web copy, verbatim.
                        errorMessage = "Couldn't turn that into rules — try naming specific guests, e.g. \"keep Bob and Sue apart\"."
                        phase = .input
                    } else {
                        proposed = validated
                        picked = Set(validated.map(\.id))
                        skipped = result.skipped
                        phase = .review
                    }
                }
            } catch let err as AIService.AIError {
                await MainActor.run {
                    switch err {
                    case .rateLimited:
                        errorMessage = err.errorDescription
                    default:
                        // Web copy, verbatim.
                        errorMessage = "AI is unavailable right now — please try again in a moment."
                    }
                    phase = .input
                }
            } catch {
                await MainActor.run {
                    errorMessage = "AI is unavailable right now — please try again in a moment."
                    phase = .input
                }
            }
        }
    }

    private func addPickedRules() {
        guard var plan = appState.activePlan else { return }
        let toAdd = proposed.filter { picked.contains($0.id) }
        guard !toAdd.isEmpty else { return }
        plan.rules.append(contentsOf: toAdd)
        // didSet on activePlan pushes the undo snapshot automatically —
        // do NOT push again here (RulesView mutation pattern).
        appState.activePlan = plan
        Task { try? await appState.database.savePlanData(plan: plan) }
        HapticEngine.success()
        dismiss()
    }

    // MARK: - Helpers

    private var canonicalCategories: [(id: String, name: String)] {
        guard let raw = appState.activePlan?.rawCategories else { return [] }
        return raw.compactMap { entry in
            guard let id = entry["id"]?.value as? String else { return nil }
            let name = (entry["name"]?.value as? String) ?? id
            return (id, name)
        }
    }

    private func firstName(_ id: String) -> String {
        guard let g = appState.activePlan?.guests.first(where: { $0.id == id }) else { return "?" }
        return g.name.split(separator: " ").first.map(String.init) ?? g.name
    }

    /// Human description mirroring web's drafted-rule labels.
    private func describe(_ rule: SeatingRule) -> String {
        let names = { (ids: [String]) in ids.map(self.firstName).joined(separator: ", ") }
        switch rule.type {
        case .mustTogether, .preferTogether:
            return names(rule.guests) + " — together"
        case .mustNot:
            if let a = rule.sideA, let b = rule.sideB, !a.isEmpty, !b.isEmpty {
                return names(a) + " vs " + names(b) + " — keep apart"
            }
            return names(rule.guests) + " — keep apart"
        case .mustTable:
            let t = appState.activePlan?.tables.first(where: { $0.id == rule.tableId })?.name ?? "table"
            return names(rule.guests) + " → " + t
        case .nearTable:
            let t = appState.activePlan?.tables.first(where: { $0.id == rule.tableId })?.name ?? "table"
            return names(rule.guests) + " → near " + t
        case .nearObject:
            let o = appState.activePlan?.objects.first(where: { $0.id == rule.objectId })?.name ?? "venue element"
            return names(rule.guests) + " → near " + o
        case .categoryTogether:
            let c = canonicalCategories.first(where: { $0.id == rule.categoryId })?.name ?? "category"
            return c + " — keep together"
        default:
            return rule.desc ?? rule.type.rawValue
        }
    }

    private func typeLabel(_ type: SeatingRule.RuleType) -> String {
        switch type {
        case .mustTogether: return "Seat Together"
        case .preferTogether: return "Prefer Together"
        case .mustNot: return "Keep Apart"
        case .mustTable: return "Assign to Table"
        case .nearTable: return "Seat Near Table"
        case .nearObject: return "Near Venue Element"
        case .categoryTogether: return "Category Together"
        default: return type.rawValue
        }
    }

    private func ruleIcon(_ type: SeatingRule.RuleType) -> String {
        switch type {
        case .mustTogether: return "person.2.fill"
        case .preferTogether: return "person.2"
        case .mustNot: return "arrow.left.and.right"
        case .mustTable: return "tablecells"
        case .nearTable: return "arrow.right.arrow.left"
        case .nearObject: return "scope"
        case .categoryTogether: return "tag"
        default: return "questionmark.circle"
        }
    }

    private func ruleColor(_ type: SeatingRule.RuleType) -> Color {
        switch type {
        case .mustTogether, .preferTogether: return .sbSage
        case .mustNot: return .sbError
        case .mustTable: return .sbGold
        default: return .sbBlush
        }
    }
}

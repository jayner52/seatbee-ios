import SwiftUI

// AI Seating screen — calls the web's /api/seat endpoint (which runs the
// SAME `generateSeating()` function the web client uses, src/lib/solve.js)
// and applies the resulting assignments + seat orders to the active plan.
// True parity with web: identical inputs always produce identical outputs.

struct AIGenerateView: View {
    @Environment(AppState.self) private var appState

    @State private var phase: Phase = .ready
    @State private var resultMessage: String?
    @State private var lastResult: SeatService.GenerateResult?
    @State private var fellBackToRoundRobin = false
    @State private var tierGateAlert: TierGateAlert?
    @State private var clearConfirm: ClearAction?
    @State private var showResetSheet = false
    @State private var showLastRunDetail = false

    enum Phase { case ready, generating, complete, error }

    private struct TierGateAlert: Identifiable {
        let id = UUID()
        let title: String
        let message: String
    }

    private enum ClearAction: Identifiable {
        case unlockedOnly, all
        var id: Int { self == .unlockedOnly ? 0 : 1 }
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ZStack {
                Color.sbIvory.ignoresSafeArea()
                if appState.activePlan == nil {
                    noPlanState
                } else {
                    switch phase {
                    case .ready:      readyState
                    case .generating: generatingState
                    case .complete:   completeState
                    case .error:      errorState
                    }
                }
            }
            .animation(.easeInOut(duration: 0.25), value: phase)
        }
        .task {
            if appState.activePlan == nil {
                let plans = (try? await appState.database.fetchPlans()) ?? []
                if let first = plans.first { appState.activePlan = first }
            }
            // Make sure userPasses is populated so the tier gate can see
            // passes redeemed on web. Cheap if already loaded recently.
            if appState.userPasses.passes.isEmpty {
                await appState.refreshPasses()
            }
        }
        .alert(
            tierGateAlert?.title ?? "",
            isPresented: Binding(
                get: { tierGateAlert != nil },
                set: { if !$0 { tierGateAlert = nil } }
            ),
            presenting: tierGateAlert
        ) { _ in
            Button("OK", role: .cancel) {}
        } message: { gate in
            Text(gate.message)
        }
        .alert(
            clearConfirm == .unlockedOnly ? "Clear Unlocked Tables?" : "Clear All Assignments?",
            isPresented: Binding(
                get: { clearConfirm != nil },
                set: { if !$0 { clearConfirm = nil } }
            ),
            presenting: clearConfirm
        ) { action in
            Button("Clear", role: .destructive) { performClear(action) }
            Button("Cancel", role: .cancel) {}
        } message: { action in
            Text(action == .unlockedOnly
                 ? "Clears assignments on every table that isn't locked. Locked tables keep their guests."
                 : "Clears every guest from every table, including locked ones. This can't be undone from this screen.")
        }
    }

    // MARK: - States

    private var noPlanState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "sparkles")
                .font(.system(size: 44))
                .foregroundStyle(Color.sbWarm2)
            Text("No plan selected")
                .font(SBFont.displaySmall)
                .foregroundStyle(Color.sbCharcoal)
            Text("Create or select a plan first")
                .font(SBFont.body)
                .foregroundStyle(Color.sbWarm)
            SBButton(title: "Go to Plans", icon: "square.grid.2x2", variant: .gold) {
                appState.selectedTab = .plans
            }
            Spacer()
        }
    }

    /// Ready: stats + active rules + Generate. Reset is conditional on
    /// having seated guests. Web parity in concepts; iOS-native in feel.
    private var readyState: some View {
        ScrollView {
            VStack(spacing: 18) {
                header
                statsRow
                activeRulesCard
                if lockedTablesCount > 0 {
                    lockedTablesHint
                }
                if let gen = appState.lastGenResult,
                   gen.planId == appState.activePlan?.id,
                   let scorecard = gen.result.scorecard {
                    lastRunCard(scorecard)
                }
                generateButton
                if guestsSeated > 0 {
                    resetButton
                }
                tipText
                Spacer(minLength: 60)
            }
            .padding(.horizontal, SBSpacing.screenMargin)
            .padding(.top, 8)
        }
        .confirmationDialog(
            "Reset seating",
            isPresented: $showResetSheet,
            titleVisibility: .visible
        ) {
            Button("Clear unlocked tables") {
                clearConfirm = .unlockedOnly
            }
            Button("Clear all assignments", role: .destructive) {
                clearConfirm = .all
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(lockedTablesCount > 0
                 ? "Clearing unlocked tables keeps your \(lockedTablesCount) locked table\(lockedTablesCount == 1 ? "" : "s") intact."
                 : "Clearing assignments removes every guest from every table.")
        }
    }

    private var generatingState: some View {
        VStack(spacing: 24) {
            Spacer()
            HoneycombLoader()
                .frame(width: 220, height: 220)
            VStack(spacing: 4) {
                Text("Generating seating…")
                    .font(SBFont.bodySemibold)
                    .foregroundStyle(Color.sbCharcoal)
                Text("Placing guests, balancing rules, choosing tables.")
                    .font(SBFont.caption)
                    .foregroundStyle(Color.sbWarm)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
            Spacer()
        }
    }

    private var completeState: some View {
        ScrollView {
            VStack(spacing: 16) {
                completeHeader
                if let scorecard = lastResult?.scorecard {
                    scorecardPanel(scorecard)
                    if scorecard.hardConstraints.total > 0 {
                        rulesSection(
                            title: "Required Rules",
                            bucket: scorecard.hardConstraints,
                            accent: Color.sbGoldDk
                        )
                    }
                    if scorecard.softPreferences.total > 0 {
                        rulesSection(
                            title: "Preferences",
                            bucket: scorecard.softPreferences,
                            accent: Color.sbSage
                        )
                    }
                }
                if fellBackToRoundRobin {
                    Text("Solver returned 0 — used round-robin fallback. Check your rules for conflicts.")
                        .font(SBFont.caption)
                        .foregroundStyle(Color.sbError)
                        .multilineTextAlignment(.center)
                        .padding(12)
                        .frame(maxWidth: .infinity)
                        .background(Color.sbError.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                actionStackComplete
                Spacer(minLength: 100)
            }
            .padding(.horizontal, SBSpacing.screenMargin)
            .padding(.top, 12)
        }
    }

    private var completeHeader: some View {
        VStack(spacing: 6) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 40))
                .foregroundStyle(Color.sbSage)
            Text("Seating generated")
                .font(SBFont.displaySmall)
                .foregroundStyle(Color.sbCharcoal)
            if let msg = resultMessage {
                Text(msg)
                    .font(SBFont.caption)
                    .foregroundStyle(Color.sbWarm)
            }
        }
        .padding(.top, 4)
    }

    private func scorecardPanel(_ s: SeatService.GenerateResult.Scorecard) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("\(s.overallPercent)%")
                        .font(SBFont.fraunces(36, weight: .medium))
                        .foregroundStyle(Color.sbCharcoal)
                    if !s.overallLabel.isEmpty {
                        Text(s.overallLabel)
                            .font(SBFont.bodySemibold)
                            .foregroundStyle(Color.sbSage)
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(s.totalSatisfied)/\(s.totalRules)")
                        .font(SBFont.statNumberSmall)
                        .foregroundStyle(Color.sbCharcoal)
                    Text("rules satisfied")
                        .font(SBFont.caption)
                        .foregroundStyle(Color.sbWarm)
                }
            }
            // Progress bar — fill width = overallPercent / 100.
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.sbWarm2.opacity(0.25))
                    Capsule()
                        .fill(Color.sbSage)
                        .frame(width: geo.size.width * (CGFloat(max(0, min(100, s.overallPercent))) / 100))
                }
            }
            .frame(height: 8)
        }
        .padding(14)
        .background(Color.sbChampagne.opacity(0.4))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func rulesSection(
        title: String,
        bucket: SeatService.GenerateResult.RuleBucket,
        accent: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Circle()
                    .fill(accent)
                    .frame(width: 8, height: 8)
                Text(title.uppercased())
                    .font(SBFont.label)
                    .foregroundStyle(Color.sbCharcoal)
                Spacer()
                let suffix = title.lowercased().contains("preference") ? "met" : "✓"
                Text("\(bucket.satisfied)/\(bucket.total) \(suffix)")
                    .font(SBFont.bodySmallBold)
                    .foregroundStyle(accent)
            }
            VStack(spacing: 6) {
                ForEach(bucket.rules) { rule in
                    ruleRow(rule)
                }
            }
        }
        .padding(14)
        .background(Color.sbIvory2)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func ruleRow(_ rule: SeatService.GenerateResult.RuleEntry) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: ruleIconName(rule.status))
                .foregroundStyle(ruleIconColor(rule.status))
                .frame(width: 18, alignment: .center)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 2) {
                let title = rule.partial.map { "\(rule.description) (\($0))" } ?? rule.description
                Text(title.isEmpty ? "—" : title)
                    .font(SBFont.bodySmall)
                    .foregroundStyle(Color.sbCharcoal)
                if let details = rule.details, !details.isEmpty {
                    Text(details)
                        .font(SBFont.caption)
                        .foregroundStyle(Color.sbWarm)
                }
            }
            Spacer()
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(ruleRowBackground(rule.status))
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    private func ruleIconName(_ status: String) -> String {
        switch status {
        case "satisfied": return "checkmark"
        case "violated":  return "xmark"
        case "partial":   return "circle.lefthalf.filled"
        default:          return "minus"
        }
    }

    private func ruleIconColor(_ status: String) -> Color {
        switch status {
        case "satisfied": return Color.sbSage
        case "violated":  return Color.sbError
        case "partial":   return Color.sbGoldDk
        default:          return Color.sbWarm
        }
    }

    private func ruleRowBackground(_ status: String) -> Color {
        switch status {
        case "satisfied": return Color.sbSage.opacity(0.10)
        case "violated":  return Color.sbError.opacity(0.10)
        case "partial":   return Color.sbChampagne.opacity(0.50)
        default:          return Color.clear
        }
    }

    private var actionStackComplete: some View {
        VStack(spacing: 10) {
            SBButton(title: "View in canvas", icon: "rectangle.grid.3x2", variant: .gold, fullWidth: true) {
                appState.selectedTab = .edit
            }
            SBButton(title: "Generate again", variant: .ghost, fullWidth: true) {
                phase = .ready
            }
        }
        .padding(.top, 4)
    }

    private var errorState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 44))
                .foregroundStyle(Color.sbError)
            Text("Couldn't generate")
                .font(SBFont.displaySmall)
                .foregroundStyle(Color.sbCharcoal)
            if let msg = resultMessage {
                Text(msg)
                    .font(SBFont.caption)
                    .foregroundStyle(Color.sbWarm)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
            Spacer()
            SBButton(title: "Try again", variant: .gold, fullWidth: true) {
                phase = .ready
            }
            .padding(.horizontal, SBSpacing.screenMargin)
            .padding(.bottom, 120)
        }
    }

    // MARK: - Components

    private var header: some View {
        HStack(alignment: .top, spacing: 10) {
            // Small honeycomb mark to tie the page to the loader's vibe.
            Image(systemName: "hexagon.fill")
                .font(.system(size: 18))
                .foregroundStyle(Color.sbGold)
                .padding(.top, 4)
            VStack(alignment: .leading, spacing: 2) {
                Text("Generate Seating")
                    .font(SBFont.displaySmall)
                    .foregroundStyle(Color.sbCharcoal)
                Text("AI-powered, tuned to your rules and parties")
                    .font(SBFont.caption)
                    .foregroundStyle(Color.sbWarm)
            }
            Spacer()
        }
    }

    /// Stat row: two cards side-by-side, each with a tinted icon, a big
    /// number, a small label, and (for "Seated") a thin progress bar so
    /// users can see the seated proportion at a glance.
    private var statsRow: some View {
        HStack(spacing: 10) {
            seatedStatCard
            availableStatCard
        }
    }

    private var seatedStatCard: some View {
        let progress = activeGuestCount == 0 ? 0 : Double(guestsSeated) / Double(activeGuestCount)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "person.2.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.sbGoldDk)
                Text("SEATED")
                    .font(SBFont.capsLabel)
                    .foregroundStyle(Color.sbGoldDk)
            }
            Text("\(guestsSeated)")
                .font(SBFont.statNumber)
                .foregroundStyle(Color.sbCharcoal)
            + Text(" / \(activeGuestCount)")
                .font(SBFont.bodySemibold)
                .foregroundStyle(Color.sbWarm)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.sbWarm2.opacity(0.20))
                    Capsule()
                        .fill(LinearGradient(colors: [Color.sbGold, Color.sbGoldDk], startPoint: .leading, endPoint: .trailing))
                        .frame(width: geo.size.width * CGFloat(progress))
                }
            }
            .frame(height: 5)
            .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.sbChampagne.opacity(0.55))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var availableStatCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "chair.lounge.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.sbSage)
                Text("AVAILABLE")
                    .font(SBFont.capsLabel)
                    .foregroundStyle(Color.sbSage)
            }
            Text("\(seatsAvailable)")
                .font(SBFont.statNumber)
                .foregroundStyle(Color.sbCharcoal)
            Text("of \(totalSeats) total seats")
                .font(SBFont.caption)
                .foregroundStyle(Color.sbWarm)
                .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.sbSage.opacity(0.18))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    /// Active Rules card: total + a stacked horizontal bar showing the
    /// proportional split between Required (gold) and Preferences (sage).
    /// More visual than two separate sub-cards and uses brand colors.
    private var activeRulesCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "checklist")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.sbCharcoal)
                Text("Active Rules")
                    .font(SBFont.bodySmallBold)
                    .foregroundStyle(Color.sbCharcoal)
                Spacer()
                Text("\(enabledRulesCount)")
                    .font(SBFont.bodySemibold)
                    .foregroundStyle(Color.sbCharcoal)
            }

            // Stacked proportional bar
            GeometryReader { geo in
                let total = max(1, enabledRulesCount)
                let reqW = geo.size.width * CGFloat(requiredRulesCount) / CGFloat(total)
                let prefW = geo.size.width * CGFloat(preferenceRulesCount) / CGFloat(total)
                HStack(spacing: 2) {
                    if requiredRulesCount > 0 {
                        Capsule().fill(Color.sbGoldDk).frame(width: max(0, reqW - (preferenceRulesCount > 0 ? 1 : 0)))
                    }
                    if preferenceRulesCount > 0 {
                        Capsule().fill(Color.sbSage).frame(width: max(0, prefW - (requiredRulesCount > 0 ? 1 : 0)))
                    }
                }
            }
            .frame(height: 8)

            // Legend
            HStack(spacing: 16) {
                legendChip(color: Color.sbGoldDk, count: requiredRulesCount, label: "Required")
                legendChip(color: Color.sbSage,   count: preferenceRulesCount, label: "Preferences")
                Spacer()
            }
        }
        .padding(14)
        .background(Color.sbIvory2)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func legendChip(color: Color, count: Int, label: String) -> some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text("\(count)")
                .font(SBFont.bodySmallBold)
                .foregroundStyle(Color.sbCharcoal)
            Text(label)
                .font(SBFont.caption)
                .foregroundStyle(Color.sbWarm)
        }
    }

    /// Subtle hint that any locked tables will be preserved. Only renders
    /// when there's at least one — otherwise it's noise.
    private var lockedTablesHint: some View {
        HStack(spacing: 8) {
            Image(systemName: "lock.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.sbGoldDk)
            Text("\(lockedTablesCount) locked table\(lockedTablesCount == 1 ? "" : "s") will be preserved")
                .font(SBFont.caption)
                .foregroundStyle(Color.sbCharcoal2)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.sbGold.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    /// Prominent Generate Seating button. Tall, gold, with sparkles icon.
    /// This is the hero action — every other piece of the screen is
    /// secondary to it.
    private var generateButton: some View {
        Button {
            Task { await runGenerate() }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.system(size: 16, weight: .semibold))
                Text("Generate Seating")
                    .font(SBFont.inter(16, weight: .semibold))
            }
            .foregroundStyle(Color.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                LinearGradient(
                    colors: [Color.sbGold, Color.sbGoldDk],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .shadow(color: Color.sbGoldDk.opacity(0.25), radius: 10, x: 0, y: 4)
        }
        .buttonStyle(.plain)
        .padding(.top, 4)
    }

    /// Reset button — only visible when there are seated guests to clear.
    /// Opens an action sheet so the destructive options aren't a permanent
    /// red label cluttering the screen.
    private var resetButton: some View {
        Button {
            showResetSheet = true
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "arrow.counterclockwise")
                    .font(.system(size: 12, weight: .semibold))
                Text("Reset seating")
                    .font(SBFont.bodySmall)
            }
            .foregroundStyle(Color.sbWarm)
            .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
    }

    private func lastRunCard(_ s: SeatService.GenerateResult.Scorecard) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showLastRunDetail.toggle()
                }
            } label: {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("LAST RUN")
                            .font(SBFont.capsLabel)
                            .foregroundStyle(Color.sbWarm2)
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text("\(s.overallPercent)%")
                                .font(SBFont.fraunces(22, weight: .medium))
                                .foregroundStyle(Color.sbCharcoal)
                            Text(s.overallLabel)
                                .font(SBFont.bodySmall)
                                .foregroundStyle(Color.sbSage)
                        }
                    }
                    Spacer()
                    Text("\(s.totalSatisfied)/\(s.totalRules) rules")
                        .font(SBFont.caption)
                        .foregroundStyle(Color.sbWarm)
                    Image(systemName: showLastRunDetail ? "chevron.up" : "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.sbWarm2)
                }
                .padding(14)
            }
            .buttonStyle(.plain)

            if showLastRunDetail {
                VStack(spacing: 8) {
                    Divider().padding(.horizontal, 14)
                    if s.hardConstraints.total > 0 {
                        rulesSection(title: "Required Rules", bucket: s.hardConstraints, accent: Color.sbGoldDk)
                            .padding(.horizontal, 14)
                    }
                    if s.softPreferences.total > 0 {
                        rulesSection(title: "Preferences", bucket: s.softPreferences, accent: Color.sbSage)
                            .padding(.horizontal, 14)
                    }
                }
                .padding(.bottom, 14)
            }
        }
        .background(Color.sbIvory2)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var tipText: some View {
        Text("Each generation uses a different random seed — re-running can produce different arrangements.")
            .font(SBFont.small)
            .foregroundStyle(Color.sbWarm2)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 16)
            .padding(.top, 8)
    }

    // MARK: - Stats (mirror App.jsx:13119-13133)

    private var activeGuests: [Guest] {
        (appState.activePlan?.guests ?? []).filter { $0.rsvp != .no }
    }

    private var activeGuestIds: Set<String> {
        Set(activeGuests.map { $0.id })
    }

    private var activeGuestCount: Int { activeGuests.count }

    private var guestsSeated: Int {
        guard let plan = appState.activePlan else { return 0 }
        return plan.tables.reduce(0) { sum, t in
            let seatedHere = t.assignments.keys.filter { activeGuestIds.contains($0) }.count
            return sum + min(seatedHere, t.seats)
        }
    }

    private var totalSeats: Int {
        (appState.activePlan?.tables ?? []).reduce(0) { $0 + $1.seats }
    }

    private var seatsAvailable: Int { max(0, totalSeats - guestsSeated) }

    private var enabledRulesCount: Int {
        (appState.activePlan?.rules ?? []).filter { $0.enabled }.count
    }

    private var requiredRulesCount: Int {
        (appState.activePlan?.rules ?? []).filter {
            $0.enabled && ($0.hard || $0.source == "party" || $0.partyId != nil)
        }.count
    }

    private var preferenceRulesCount: Int {
        max(0, enabledRulesCount - requiredRulesCount)
    }

    private var lockedTablesCount: Int {
        (appState.activePlan?.tables ?? []).filter { $0.locked == true }.count
    }

    // MARK: - Actions

    private func runGenerate() async {
        // Tier gate (mirrors web checkTierLimit('ai_generate') at App.jsx:6217).
        guard appState.activePlanLimits.aiGenerate else {
            HapticEngine.error()
            tierGateAlert = appState.isActivePlanExpired
                ? TierGateAlert(title: "Pass Expired",
                                message: "This event's pass has expired. Apply a new Event Pass in Settings to use AI seating again.")
                : TierGateAlert(title: "AI Seating Needs an Event Pass",
                                message: "AI seating is included with Event Pass, Signature Pass, and Grand Event Pass. Apply a pass in Settings → Event Passes to unlock.")
            return
        }
        guard var plan = appState.activePlan else { return }
        guard !plan.tables.isEmpty, !plan.guests.isEmpty else {
            resultMessage = "Add at least one table and one guest before generating."
            phase = .error
            return
        }

        phase = .generating
        resultMessage = nil
        fellBackToRoundRobin = false
        lastResult = nil

        do {
            let result = try await appState.seat.generateSeating(plan: plan)
            plan.applyGeneratedSeating(result)
            appState.activePlan = plan
            try await appState.database.savePlanData(plan: plan)
            lastResult = result
            appState.lastGenResult = (planId: plan.id, result: result)
            fellBackToRoundRobin = result.fallback ?? false
            resultMessage = "Seated \(plan.tables.reduce(0) { $0 + $1.assignments.count }) of \(activeGuestCount) guests."
            HapticEngine.success()
            phase = .complete
        } catch let error as SeatService.SeatError {
            HapticEngine.error()
            resultMessage = error.localizedDescription
            phase = .error
        } catch {
            HapticEngine.error()
            resultMessage = error.localizedDescription
            phase = .error
        }
    }

    private func performClear(_ action: ClearAction) {
        guard var plan = appState.activePlan else { return }
        switch action {
        case .unlockedOnly: plan.clearUnlockedTableAssignments()
        case .all:          plan.clearAllAssignments()
        }
        appState.activePlan = plan
        Task {
            try? await appState.database.savePlanData(plan: plan)
        }
        HapticEngine.medium()
        clearConfirm = nil
    }
}

#Preview {
    AIGenerateView()
        .environment(AppState())
}

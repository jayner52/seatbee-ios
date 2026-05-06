import SwiftUI

// AI Seating screen — calls the web's /api/seat endpoint (which runs the
// SAME `generateSeating()` function the web client uses, src/lib/solve.js)
// and applies the resulting assignments + seat orders to the active plan.
// True parity with web: identical inputs always produce identical outputs.

struct AIGenerateView: View {
    @Environment(AppState.self) private var appState

    @State private var phase: Phase = .ready
    @State private var resultMessage: String?
    @State private var harmonyScore: Int?
    @State private var fellBackToRoundRobin = false
    @State private var tierGateAlert: TierGateAlert?
    @State private var clearConfirm: ClearAction?

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

    /// Ready: shows stats + active rules + the three action buttons.
    /// Mirrors the web's "Generate Seating" panel layout.
    private var readyState: some View {
        ScrollView {
            VStack(spacing: 20) {
                header
                statsRow
                activeRulesCard
                actionStack
                tipText
                Spacer(minLength: 60)
            }
            .padding(.horizontal, SBSpacing.screenMargin)
            .padding(.top, 8)
        }
    }

    private var generatingState: some View {
        VStack(spacing: 16) {
            Spacer()
            ProgressView()
                .scaleEffect(1.4)
                .tint(Color.sbGoldDk)
            Text("Generating seating…")
                .font(SBFont.bodySemibold)
                .foregroundStyle(Color.sbCharcoal)
            Text("This usually takes a few seconds.")
                .font(SBFont.caption)
                .foregroundStyle(Color.sbWarm)
            Spacer()
        }
    }

    private var completeState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 56))
                .foregroundStyle(Color.sbSage)
            Text("Seating generated")
                .font(SBFont.displaySmall)
                .foregroundStyle(Color.sbCharcoal)
            if let score = harmonyScore {
                Text("Harmony score \(score)")
                    .font(SBFont.body)
                    .foregroundStyle(Color.sbGoldDk)
            }
            if let msg = resultMessage {
                Text(msg)
                    .font(SBFont.caption)
                    .foregroundStyle(Color.sbWarm)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
            if fellBackToRoundRobin {
                Text("Note: solver returned 0; used round-robin fallback. Check your rules for conflicts.")
                    .font(SBFont.caption)
                    .foregroundStyle(Color.sbError)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
            Spacer()
            VStack(spacing: 12) {
                SBButton(title: "View in canvas", icon: "rectangle.grid.3x2", variant: .gold, fullWidth: true) {
                    appState.selectedTab = .edit
                }
                SBButton(title: "Generate again", variant: .ghost, fullWidth: true) {
                    phase = .ready
                }
            }
            .padding(.horizontal, SBSpacing.screenMargin)
            .padding(.bottom, 120)
        }
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
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Generate Seating")
                    .font(SBFont.displaySmall)
                    .foregroundStyle(Color.sbCharcoal)
                Text("AI seating powered by your rules and parties")
                    .font(SBFont.caption)
                    .foregroundStyle(Color.sbWarm)
            }
            Spacer()
        }
    }

    private var statsRow: some View {
        HStack(spacing: 10) {
            statCard(
                title: "guests seated",
                value: "\(guestsSeated)/\(activeGuestCount)",
                tint: Color.sbChampagne
            )
            statCard(
                title: "seats available",
                value: "\(seatsAvailable)",
                tint: Color.sbSage.opacity(0.20)
            )
        }
    }

    private func statCard(title: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(SBFont.statNumber)
                .foregroundStyle(Color.sbGoldDk)
            Text(title)
                .font(SBFont.caption)
                .foregroundStyle(Color.sbWarm)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(tint)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var activeRulesCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Active Rules")
                    .font(SBFont.bodySmallBold)
                    .foregroundStyle(Color.sbCharcoal)
                Spacer()
                Text("\(enabledRulesCount)")
                    .font(SBFont.bodySemibold)
                    .foregroundStyle(Color.sbGoldDk)
            }
            HStack(spacing: 10) {
                ruleSubCard(label: "Required", count: requiredRulesCount, accent: Color.sbGoldDk, tint: Color.sbChampagne)
                ruleSubCard(label: "Preferences", count: preferenceRulesCount, accent: Color.sbCharcoal, tint: Color.sbSage.opacity(0.20))
            }
        }
        .padding(14)
        .background(Color.sbIvory2)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func ruleSubCard(label: String, count: Int, accent: Color, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(count)")
                .font(SBFont.statNumberSmall)
                .foregroundStyle(accent)
            Text(label)
                .font(SBFont.caption)
                .foregroundStyle(Color.sbWarm)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(tint)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var actionStack: some View {
        VStack(spacing: 10) {
            SBButton(title: "Generate Seating", icon: "sparkles", variant: .gold, fullWidth: true) {
                Task { await runGenerate() }
            }
            SBButton(title: "Clear Unlocked Tables", variant: .ghost, fullWidth: true) {
                clearConfirm = .unlockedOnly
            }
            Button {
                clearConfirm = .all
            } label: {
                Text("Clear All Assignments")
                    .font(SBFont.bodySmall)
                    .foregroundStyle(Color.sbError)
                    .padding(.top, 4)
            }
        }
    }

    private var tipText: some View {
        Text("Tip: each generation uses a different random seed, so re-running can produce different arrangements.")
            .font(SBFont.caption)
            .foregroundStyle(Color.sbWarm)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 8)
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
        harmonyScore = nil

        do {
            let result = try await appState.seat.generateSeating(plan: plan)
            plan.applyGeneratedSeating(result)
            appState.activePlan = plan
            try await appState.database.savePlanData(plan: plan)
            harmonyScore = result.score
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

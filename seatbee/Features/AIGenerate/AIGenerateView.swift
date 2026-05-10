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
    @State private var aiInsight: AIInsightState = .idle

    enum Phase { case ready, generating, complete, error }

    /// State of the post-generate AI Insight call. Mirrors web's
    /// `aiAnalysis` object shape so each render branch maps to the
    /// same UX (loading / error / unparseable / real summary).
    enum AIInsightState {
        case idle
        case loading
        case ready(AIService.ConflictResult)
        case unparseable
        case failed(String)
    }

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
            // Restore the previously-cached AI insight when the user
            // returns to this tab after generating earlier in the
            // session. The insight lives on AppState so it survives
            // tab navigation; without this restore the panel comes up
            // empty even though the run still has a stored insight.
            if case .idle = aiInsight,
               let cached = appState.lastGenInsight,
               cached.planId == appState.activePlan?.id {
                aiInsight = .ready(cached.result)
            }
        }
        .onChange(of: appState.activePlan?.id) { _, _ in
            // Switching plans must drop any insight from the previous
            // plan — it's narrative tied to a specific layout.
            aiInsight = .idle
            if let cached = appState.lastGenInsight,
               cached.planId == appState.activePlan?.id {
                aiInsight = .ready(cached.result)
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
            Button("Upgrade") { appState.showUpgrade = true }
            Button("Not now", role: .cancel) {}
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
                suggestionsPanel
                aiInsightPanel
                capacityPanel
                if fellBackToRoundRobin {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Solver returned 0 — used round-robin fallback. Check your rules for conflicts.")
                            .font(SBFont.caption)
                            .foregroundStyle(Color.sbError)
                        // When solve() threw on the server, the actual
                        // exception text is captured in
                        // scorecard.suggestions[0]. Surface it so we
                        // can debug (e.g. "Solver error: cannot read
                        // property 'id' of undefined" → bad rule ref).
                        if let detail = solverErrorDetail {
                            Text(detail)
                                .font(SBFont.caption)
                                .foregroundStyle(Color.sbWarm)
                                .padding(.top, 2)
                        }
                    }
                    .multilineTextAlignment(.leading)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
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
                            .foregroundStyle(labelColor(for: s.overallLabel))
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
            // Progress bar — fill width = overallPercent / 100,
            // colour keyed off the same percentage bands as the
            // label and the web app's getProgressColor (App.jsx
            // ~12968): sage at 80%+, gold at 70%+, blush/orange at
            // 50%+, error red below 50.
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.sbWarm2.opacity(0.25))
                    Capsule()
                        .fill(progressBarColor(for: s.overallPercent))
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

    /// Suggestions card — surfaces actionable hints solve.js stamps
    /// into scorecard.suggestions ("Move Unknown to Table 5"). Web
    /// shows these in a champagne callout (App.jsx ~13540) above
    /// the AI Insight; iOS mirrors that ordering. Filters out the
    /// "Solver error: …" strings since those already render under
    /// the fallback banner — no duplicate noise.
    @ViewBuilder
    private var suggestionsPanel: some View {
        let messages = (lastResult?.scorecard?.suggestions ?? [])
            .filter { !$0.lowercased().hasPrefix("solver error") }
        if !messages.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "lightbulb")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.sbGoldDk)
                    Text("SUGGESTIONS")
                        .font(SBFont.capsLabel)
                        .foregroundStyle(Color.sbCharcoal)
                        .letterSpacing(1.5)
                }
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(messages.indices, id: \.self) { i in
                        HStack(alignment: .top, spacing: 6) {
                            Text("→")
                                .font(SBFont.caption)
                                .foregroundStyle(Color.sbGoldDk.opacity(0.7))
                            Text(messages[i])
                                .font(SBFont.caption)
                                .foregroundStyle(Color.sbCharcoal)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.sbChampagne.opacity(0.5))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.sbGold.opacity(0.2), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }

    /// Capacity feedback — three states keyed off how seats vs.
    /// attending guests stack up (web App.jsx ~13580):
    ///   - shortage > 0  → "Not Enough Seats"  (red, with breakdown)
    ///   - empty% > 40   → "Many Empty Seats"  (gold, suggest fewer
    ///                                          tables)
    ///   - empty% ≤ 20   → "Good capacity match" (sage, "X/Y used")
    /// Anything in between renders nothing — quiet for partial fits.
    @ViewBuilder
    private var capacityPanel: some View {
        if let plan = appState.activePlan {
            let totalSeats = plan.tables.reduce(0) { $0 + $1.seats }
            let attendingCount = plan.guests.filter { $0.rsvp != .no }.count
            let seatedCount = plan.tables.reduce(0) { $0 + $1.assignments.count }
            let emptySeats = max(0, totalSeats - seatedCount)
            let emptyPercent = totalSeats > 0
                ? Int((Double(emptySeats) / Double(totalSeats) * 100).rounded())
                : 0
            let shortage = attendingCount - totalSeats

            if shortage > 0 {
                capacityCard(
                    accent: Color.sbError,
                    icon: "exclamationmark.triangle",
                    title: "Not Enough Seats",
                    rows: [
                        ("Attending guests", "\(attendingCount)"),
                        ("Total seats", "\(totalSeats)"),
                        ("Need", "+\(shortage) more seat\(shortage == 1 ? "" : "s")"),
                    ],
                    footnote: "Add more tables or increase seats per table."
                )
            } else if emptyPercent > 40 && totalSeats > 0 {
                let extraTables = max(1, Int((Double(emptySeats) / 8).rounded(.up)))
                capacityCard(
                    accent: Color.sbGoldDk,
                    icon: "exclamationmark.triangle",
                    title: "Many Empty Seats",
                    rows: [
                        ("Seated", "\(seatedCount) guest\(seatedCount == 1 ? "" : "s")"),
                        ("Empty", "\(emptySeats) seat\(emptySeats == 1 ? "" : "s") (\(emptyPercent)%)"),
                    ],
                    footnote: "Consider removing \(extraTables) table\(extraTables == 1 ? "" : "s") or reducing seats per table."
                )
            } else if seatedCount > 0 && emptyPercent <= 20 {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.sbSage)
                    Text("Good capacity match")
                        .font(SBFont.bodySmallBold)
                        .foregroundStyle(Color.sbSage)
                    Spacer()
                    Text("\(seatedCount)/\(totalSeats) seats used")
                        .font(SBFont.caption)
                        .foregroundStyle(Color.sbWarm)
                }
                .padding(12)
                .background(Color.sbSage.opacity(0.10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color.sbSage.opacity(0.3), lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
        }
    }

    private func capacityCard(accent: Color, icon: String, title: String,
                              rows: [(label: String, value: String)],
                              footnote: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                    .foregroundStyle(accent)
                Text(title)
                    .font(SBFont.bodySmallBold)
                    .foregroundStyle(accent)
            }
            VStack(spacing: 2) {
                ForEach(rows.indices, id: \.self) { i in
                    HStack {
                        Text(rows[i].label)
                            .font(SBFont.caption)
                            .foregroundStyle(accent.opacity(0.85))
                        Spacer()
                        Text(rows[i].value)
                            .font(SBFont.bodySmallBold)
                            .foregroundStyle(accent)
                    }
                    if i == rows.count - 2 {
                        Divider().background(accent.opacity(0.25))
                    }
                }
            }
            Text(footnote)
                .font(SBFont.caption)
                .foregroundStyle(accent.opacity(0.85))
                .padding(.top, 4)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(accent.opacity(0.10))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(accent.opacity(0.30), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    /// Web-parity AI Insight panel under the scorecard. Renders a
    /// distinct view per state so silent failures stay visible — same
    /// design lesson learned on web (App.jsx:13556 had a single
    /// guarded render that hid every failure mode).
    @ViewBuilder
    private var aiInsightPanel: some View {
        switch aiInsight {
        case .idle:
            EmptyView()
        case .loading:
            insightLoadingCard
                .transition(.opacity)
        case .unparseable:
            insightCard(
                accent: Color.sbGoldDk,
                icon: "sparkles",
                heading: "AI Insight",
                body: "AI returned an unparseable response — try again to get a summary.",
                bodyStyle: .italic
            )
        case .failed(let message):
            insightCard(
                accent: Color.sbError,
                icon: "exclamationmark.triangle",
                heading: "AI insight unavailable",
                body: message,
                bodyStyle: .plain
            )
        case .ready(let result):
            insightCard(
                accent: Color.sbGoldDk,
                icon: "sparkles",
                heading: "AI Insight",
                body: "\u{201C}\(result.summary)\u{201D}",
                bodyStyle: .italic
            )
        }
    }

    /// Loading-state card with subtle motion so the user knows the
    /// AI call is alive (5–10s round trips otherwise read as "did
    /// nothing happen?"). Three things move:
    ///   - sparkles icon pulses via SF Symbol's native .pulse effect
    ///   - "Analyzing…" cycles through 1 / 2 / 3 dots via a
    ///     TimelineView ticking every 0.4s — no extra @State
    ///   - sage progress dot drifts L→R on a 1.4s loop, mirroring
    ///     the sparkle accent so it reads as a single moving system
    private var insightLoadingCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.sbGoldDk)
                    .symbolEffect(.pulse, options: .repeating)
                Text("AI Insight")
                    .font(SBFont.bodySmallBold)
                    .foregroundStyle(Color.sbCharcoal)
            }
            TimelineView(.animation(minimumInterval: 0.4, paused: false)) { context in
                let dotCount = (Int(context.date.timeIntervalSinceReferenceDate * 2.5) % 3) + 1
                let dots = String(repeating: ".", count: dotCount)
                Text("Analyzing seating arrangement\(dots)")
                    .font(SBFont.body.italic())
                    .foregroundStyle(Color.sbWarm)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // Indeterminate shimmer bar — gives a horizontal sense of
            // motion that reads as "still working" even if the user
            // looks away mid-call. 2pt high so it stays subtle.
            LoadingShimmerBar()
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.sbCharcoal.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private enum InsightBodyStyle { case italic, plain }

    private func insightCard(accent: Color, icon: String, heading: String, body: String, bodyStyle: InsightBodyStyle) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                    .foregroundStyle(accent)
                Text(heading)
                    .font(SBFont.bodySmallBold)
                    .foregroundStyle(Color.sbCharcoal)
            }
            Text(body)
                .font(bodyStyle == .italic ? SBFont.body.italic() : SBFont.caption)
                .foregroundStyle(Color.sbWarm)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.sbCharcoal.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    /// Tier-coloured progress bar — same bands as the "getLabel"
    /// thresholds in solve.js.
    private func progressBarColor(for percent: Int) -> Color {
        switch percent {
        case 80...:    return Color.sbSage     // Perfect / Excellent / Great
        case 70...:    return Color.sbGold     // Good
        case 50...:    return Color.sbBlush    // Fair
        default:       return Color.sbError    // Needs Work
        }
    }

    /// Coloured label text matching the bar's tier so a 94%
    /// "Excellent" reads as green typography, not red.
    private func labelColor(for label: String) -> Color {
        switch label {
        case "Perfect", "Excellent", "Great": return Color.sbSage
        case "Good":                          return Color.sbGoldDk
        case "Fair":                          return Color.sbBlush
        default:                              return Color.sbError
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

            // Parties footer — parties are guaranteed-together at solve
            // time (passed as atomic units to /api/seat) but live in
            // their own UI section, not the rules array, so they don't
            // show up in the Required count above. Surface them here
            // so users can see they're being honoured.
            if partiesCount > 0 {
                HStack(spacing: 6) {
                    Image(systemName: "person.3.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.sbGoldDk)
                    Text("\(partiesCount) part\(partiesCount == 1 ? "y" : "ies") always seated together")
                        .font(SBFont.caption)
                        .foregroundStyle(Color.sbWarm)
                    Spacer()
                }
                .padding(.top, 2)
            }
        }
        .padding(14)
        .background(Color.sbIvory2)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    /// Number of parties on the active plan. Parties live in
    /// `plan.rawParties` as a passthrough from web/iOS UI creation;
    /// they're not in plan.rules even though they behave like a hard
    /// must_together rule at solve time.
    private var partiesCount: Int {
        (appState.activePlan?.rawParties ?? []).count
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

    /// First entry of scorecard.suggestions when it begins with
    /// "Solver error:" — the server stamps the JS exception message
    /// there when solve() throws. Used by completeState below to
    /// show the actual cause when the round-robin fallback kicks in.
    private var solverErrorDetail: String? {
        guard let s = lastResult?.scorecard else { return nil }
        return s.suggestions.first { $0.hasPrefix("Solver error") }
    }

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
        // Tier gate — skip the alert, go straight to the paywall
        guard appState.activePlanLimits.aiGenerate else {
            HapticEngine.error()
            appState.showUpgrade = true
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
        // Clear any previous insight so the panel doesn't show
        // stale narrative against a freshly-generated layout.
        aiInsight = .idle
        // Also clear the AppState-cached insight so a tab away/back
        // round-trip doesn't restore the old narrative on top of a
        // new run that hasn't completed yet.
        appState.lastGenInsight = nil

        do {
            let result = try await appState.seat.generateSeating(plan: plan)
            plan.applyGeneratedSeating(result)
            appState.activePlan = plan
            try await appState.database.savePlanData(plan: plan)
            lastResult = result
            appState.lastGenResult = (planId: plan.id, result: result)
            fellBackToRoundRobin = result.fallback ?? false
            // Use guestsSeated (which already filters rsvp == .no)
            // for the numerator so the message stays consistent with
            // the denominator. Without the filter, a stale declined
            // guest sitting in plan.tables.assignments produced a
            // "Seated 114 of 108" overshoot.
            resultMessage = "Seated \(guestsSeated) of \(activeGuestCount) guests."
            HapticEngine.success()
            phase = .complete

            // Post-generate AI Insight (web parity App.jsx:13229).
            // Fire only when there's at least one enabled rule —
            // matches web — and only on a successful (non-fallback)
            // result. Background Task so the "Seating generated"
            // UI doesn't block on the LLM round-trip.
            let hasEnabledRules = plan.rules.contains { $0.enabled }
            if hasEnabledRules && !(result.fallback ?? false) {
                Task { await fetchAIInsight(for: plan) }
            }
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

    /// Set both the local `aiInsight` and the AppState-cached insight
    /// in one place so they never drift. AppState's cache is what
    /// survives a tab navigation; without it the user generates,
    /// walks to Plans, comes back, and the insight panel is gone.
    @MainActor
    private func setInsight(_ state: AIInsightState, planId: String) {
        aiInsight = state
        if case .ready(let result) = state {
            appState.lastGenInsight = (planId: planId, result: result)
        }
    }

    /// Background AI Insight call. Web-parity narrative analysis
    /// (App.jsx:13051 analyzeWithAI). Failures are swallowed into
    /// state — never throw to caller — so a flaky LLM doesn't ruin
    /// the "Seating generated" UX.
    @MainActor
    private func fetchAIInsight(for plan: SeatingPlan) async {
        // Demo plan: no /api/ai call. Build the insight string off the
        // pre-baked scorecard so the percentage matches the score panel
        // above (was previously hardcoded at 100% while the solver tops
        // out at 97%, leaving the two cards visibly disagreeing).
        if plan.isDemo {
            let pct = (try? SampleEventService.shared.preBakedResult().scorecard?.overallPercent) ?? 97
            setInsight(.ready(AIService.ConflictResult(
                conflicts: [],
                score: pct,
                summary: "Sample wedding seated at \(pct)%. The couple is at the sweetheart, the wedding party is together at the head table, and the four children are clustered at the Kids Table with their meal pre-set. Both grandmothers landed within reach of the emergency exit, and the bride's college friends are next to the dance floor where they'll actually use it. Every must-sit family stayed at one table, and the divorced grandparents and rival ex-coworkers are seated apart."
            )), planId: plan.id)
            return
        }
        aiInsight = .loading
        do {
            let result = try await appState.ai.detectConflicts(plan: plan)
            // Web treats `summary == "Could not analyze"` as a
            // separate "unparseable" bucket — same here so the user
            // sees a meaningful retry hint instead of a confusing
            // canned string.
            if result.summary.trimmingCharacters(in: .whitespaces) == "Could not analyze" {
                aiInsight = .unparseable
            } else if result.summary.trimmingCharacters(in: .whitespaces).isEmpty {
                aiInsight = .unparseable
            } else {
                setInsight(.ready(result), planId: plan.id)
            }
        } catch let err as AIService.AIError {
            aiInsight = .failed(err.localizedDescription)
        } catch {
            aiInsight = .failed(error.localizedDescription)
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

/// Subtle horizontal shimmer for the AI Insight loading card.
/// 2pt-high champagne strip with a brighter gold pill drifting
/// L→R on a 1.4s loop. Reads as "still working" without competing
/// with the heading or the dot-cycling text.
private struct LoadingShimmerBar: View {
    @State private var offset: CGFloat = -1

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.sbChampagne.opacity(0.7))
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.sbGoldDk.opacity(0),
                                Color.sbGoldDk.opacity(0.65),
                                Color.sbGoldDk.opacity(0),
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: geo.size.width * 0.4)
                    .offset(x: offset * geo.size.width)
            }
            .clipShape(Capsule())
            .onAppear {
                withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) {
                    offset = 1
                }
            }
        }
        .frame(height: 2)
    }
}

#Preview {
    AIGenerateView()
        .environment(AppState())
}

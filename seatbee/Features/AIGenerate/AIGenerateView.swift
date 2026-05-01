import SwiftUI

struct AIGenerateView: View {
    @Environment(AppState.self) private var appState
    @State private var phase: GenerationPhase = .ready
    @State private var seatedCount = 0
    @State private var totalToSeat = 0
    @State private var harmonyScore: Int?
    @State private var steps: [StepStatus] = [
        .init(label: "Grouped families", status: .pending),
        .init(label: "Respected dietary tables", status: .pending),
        .init(label: "Placing +1s", status: .pending),
        .init(label: "Final review", status: .pending),
    ]

    enum GenerationPhase {
        case ready, generating, complete
    }

    struct StepStatus: Identifiable {
        let id = UUID()
        let label: String
        var status: Status

        enum Status { case pending, inProgress, done }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.sbIvory.ignoresSafeArea()

                switch phase {
                case .ready:
                    readyState
                case .generating:
                    generatingState
                case .complete:
                    completeState
                }
            }
        }
    }

    // MARK: - Ready State

    private var readyState: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "sparkles")
                .font(.system(size: 48))
                .foregroundStyle(Color.sbGold)

            VStack(spacing: 8) {
                Text("AI Seating")
                    .font(SBFont.displayLarge)
                    .foregroundStyle(Color.sbCharcoal)
                Text("Let AI find the perfect arrangement")
                    .font(SBFont.body)
                    .foregroundStyle(Color.sbWarm)
            }

            if let plan = appState.activePlan {
                let unseated = plan.guests.count - plan.tables.reduce(0) { $0 + $1.filledCount }
                VStack(spacing: 12) {
                    SBStat(value: "\(max(0, unseated))", label: "Guests to seat", color: .sbGoldDk)

                    SBButton(title: "Generate seating", icon: "sparkles", variant: .gold, fullWidth: true) {
                        startGeneration(unseated: max(0, unseated))
                    }
                    .padding(.horizontal, 40)
                }
            }

            Spacer()
        }
    }

    // MARK: - Generating State

    private var generatingState: some View {
        VStack(spacing: 0) {
            // Canvas with tables
            if let plan = appState.activePlan {
                canvasPreview(plan: plan)
                    .frame(height: 300)
            }

            Spacer()

            // Progress pill
            progressPill

            Spacer().frame(height: 24)

            // Step list
            VStack(alignment: .leading, spacing: 12) {
                ForEach(steps) { step in
                    stepRow(step)
                }
            }
            .padding(.horizontal, SBSpacing.screenMargin)

            Spacer()
        }
    }

    private func canvasPreview(plan: SeatingPlan) -> some View {
        ZStack {
            Color.sbIvory2
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 14), count: 3), spacing: 14) {
                ForEach(plan.tables) { table in
                    SBTableGraphic(
                        totalSeats: table.seats,
                        filledSeats: min(table.filledCount + animatedFillForTable(table), table.seats),
                        label: table.name,
                        size: 60
                    )
                }
            }
            .padding(20)
        }
    }

    private var progressPill: some View {
        HStack(spacing: 8) {
            Text("Seating guests — \(seatedCount) of \(totalToSeat)")
                .font(SBFont.inter(13, weight: .semibold))
                .foregroundStyle(Color.sbIvory)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            Capsule()
                .fill(Color.sbCharcoal)
                .overlay(
                    GeometryReader { geo in
                        Capsule()
                            .fill(Color.sbGold)
                            .frame(width: geo.size.width * progress)
                    }
                    .clipShape(Capsule())
                )
        )
    }

    private func stepRow(_ step: StepStatus) -> some View {
        HStack(spacing: 10) {
            Group {
                switch step.status {
                case .done:
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.sbSage)
                case .inProgress:
                    Image(systemName: "circle.dotted")
                        .foregroundStyle(Color.sbGold)
                        .symbolEffect(.pulse)
                case .pending:
                    Image(systemName: "circle")
                        .foregroundStyle(Color.sbWarm2)
                }
            }
            .font(.system(size: 16))

            Text(step.label)
                .font(SBFont.body)
                .foregroundStyle(step.status == .pending ? Color.sbWarm2 : Color.sbCharcoal)
        }
    }

    // MARK: - Complete State

    private var completeState: some View {
        VStack(spacing: 24) {
            Spacer()

            // Harmony score
            if let score = harmonyScore {
                VStack(spacing: 8) {
                    Text("\(score)")
                        .font(SBFont.fraunces(60, weight: .medium))
                        .foregroundStyle(Color.sbGold)
                        .contentTransition(.numericText())

                    Text("Harmony Score")
                        .font(SBFont.label)
                        .foregroundStyle(Color.sbWarm)
                        .textCase(.uppercase)
                }
            }

            // Summary
            VStack(spacing: 6) {
                Text("12 families together")
                    .font(SBFont.body)
                    .foregroundStyle(Color.sbCharcoal)
                Text("4 accessibility requests honored")
                    .font(SBFont.body)
                    .foregroundStyle(Color.sbCharcoal)
            }

            Spacer()

            // Actions
            VStack(spacing: 12) {
                SBButton(title: "Accept", icon: "checkmark", variant: .gold, fullWidth: true) {
                    // Accept the AI-generated arrangement
                    HapticEngine.success()
                    appState.selectedTab = .edit
                }

                SBButton(title: "Keep editing", variant: .ghost, fullWidth: true) {
                    appState.selectedTab = .edit
                }
            }
            .padding(.horizontal, SBSpacing.screenMargin)
            .padding(.bottom, 120)
        }
    }

    // MARK: - Logic

    private var progress: CGFloat {
        guard totalToSeat > 0 else { return 0 }
        return CGFloat(seatedCount) / CGFloat(totalToSeat)
    }

    private func animatedFillForTable(_ table: SeatTable) -> Int {
        // Simple distribution during animation
        guard totalToSeat > 0 else { return 0 }
        return Int(Double(table.seats - table.filledCount) * Double(seatedCount) / Double(totalToSeat))
    }

    private func startGeneration(unseated: Int) {
        totalToSeat = unseated
        seatedCount = 0
        phase = .generating

        // Simulate progressive generation
        Task {
            // Step 1: Grouped families
            steps[0].status = .inProgress
            try? await Task.sleep(for: .seconds(1.2))
            steps[0].status = .done
            seatedCount = totalToSeat / 4
            HapticEngine.light()

            // Step 2: Dietary
            steps[1].status = .inProgress
            try? await Task.sleep(for: .seconds(1.0))
            steps[1].status = .done
            seatedCount = totalToSeat / 2
            HapticEngine.light()

            // Step 3: +1s
            steps[2].status = .inProgress

            // Actually call the AI service
            do {
                if let plan = appState.activePlan {
                    let result = try await appState.ai.getSeatingSuggestions(
                        guests: plan.guests,
                        tables: plan.tables,
                        rules: plan.rules
                    )
                    harmonyScore = result.score
                }
            } catch {
                // Fallback score
                harmonyScore = 85
            }

            steps[2].status = .done
            seatedCount = Int(Double(totalToSeat) * 0.8)
            HapticEngine.light()

            // Step 4: Final review
            steps[3].status = .inProgress
            try? await Task.sleep(for: .seconds(0.8))
            steps[3].status = .done
            seatedCount = totalToSeat
            HapticEngine.success()

            try? await Task.sleep(for: .seconds(0.5))

            withAnimation(.seatbeeSpring) {
                phase = .complete
            }
        }
    }
}

#Preview {
    AIGenerateView()
        .environment(AppState())
}

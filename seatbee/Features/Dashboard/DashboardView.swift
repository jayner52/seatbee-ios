import SwiftUI

struct DashboardView: View {
    @Environment(AppState.self) private var appState
    @State private var plans: [SeatingPlan] = []
    @State private var isLoading = true
    @State private var loadError: String?
    @State private var showEditPlan = false

    private var activePlan: SeatingPlan? { plans.first }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: SBSpacing.sectionGapLarge) {
                    // Greeting
                    greeting

                    // Error state
                    if let loadError {
                        VStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle")
                                .font(.system(size: 24))
                                .foregroundStyle(Color.sbError)
                            Text(loadError)
                                .font(SBFont.caption)
                                .foregroundStyle(Color.sbWarm)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                    }

                    // Loading state
                    if isLoading {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .padding(.top, 40)
                    }

                    // Empty state — prompt to create wedding
                    if !isLoading && plans.isEmpty && loadError == nil {
                        VStack(spacing: 20) {
                            Spacer().frame(height: 20)

                            Image("SeatbeeLogo")
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 64, height: 64)

                            Text("Your wedding,\nperfectly seated")
                                .font(SBFont.displayLarge)
                                .foregroundStyle(Color.sbCharcoal)
                                .multilineTextAlignment(.center)

                            Text("Create your seating plan in minutes with AI")
                                .font(SBFont.body)
                                .foregroundStyle(Color.sbWarm)
                                .multilineTextAlignment(.center)

                            SBButton(title: "Plan your wedding", icon: "sparkles", variant: .gold, fullWidth: true) {
                                appState.showOnboarding = true
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 20)
                    }

                    // Hero card - active event
                    if let plan = activePlan {
                        Button {
                            selectPlan(plan)
                        } label: {
                            heroCard(plan)
                        }
                        .buttonStyle(.plain)
                    }

                    // Quick actions
                    if !plans.isEmpty {
                        quickActions
                    }

                    // Other plans
                    if plans.count > 1 {
                        otherPlans
                    }

                    Spacer(minLength: 100) // Tab bar clearance
                }
                .padding(.horizontal, SBSpacing.screenMargin)
                .padding(.top, SBSpacing.screenMargin)
            }
            .background(Color.sbIvory)
            .refreshable {
                await loadPlans()
            }
        }
        .task {
            await loadPlans()
        }
        .sheet(isPresented: $showEditPlan) {
            EditPlanSheet()
                .environment(appState)
        }
    }

    // MARK: - Greeting

    private var greeting: some View {
        HStack {
            Text(greetingText)
                .font(SBFont.displayMedium)
                .foregroundStyle(Color.sbCharcoal)

            Spacer()

            if !plans.isEmpty {
                Button {
                    appState.showOnboarding = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color.sbGoldDk)
                        .frame(width: 36, height: 36)
                        .background(Color.sbChampagne)
                        .clipShape(Circle())
                }
            }
        }
    }

    private var greetingText: String {
        let hour = Calendar.current.component(.hour, from: Date())
        let prefix: String
        if hour < 12 { prefix = "Morning" }
        else if hour < 17 { prefix = "Afternoon" }
        else { prefix = "Evening" }
        return prefix
    }

    // MARK: - Hero Card

    private func heroCard(_ plan: SeatingPlan) -> some View {
        SBCard(elevated: true, backgroundColor: .sbIvory2) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text(plan.name)
                        .font(SBFont.fraunces(26, weight: .medium))
                        .foregroundStyle(Color.sbCharcoal)
                    Spacer()
                    Button {
                        showEditPlan = true
                    } label: {
                        Image(systemName: "pencil")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(Color.sbGoldDk)
                            .frame(width: 30, height: 30)
                            .background(Color.sbChampagne)
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                }

                if let date = plan.eventDate {
                    HStack(spacing: 6) {
                        if let venue = plan.venue {
                            Text(venue)
                        }
                        Text("·")
                        Text(date, style: .date)
                    }
                    .font(SBFont.meta)
                    .foregroundStyle(Color.sbWarm)
                }

                // Progress bar
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.sbWarm2)
                            .frame(height: 6)

                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.sbGold)
                            .frame(width: geo.size.width * seatedProgress(plan), height: 6)
                    }
                }
                .frame(height: 6)

                // Stats row
                HStack(spacing: 0) {
                    SBStat(value: "\(plan.guests.count)", label: "Guests")
                    Spacer()
                    SBStat(value: "\(unseatedCount(plan))", label: "Unseated", color: .sbGoldDk)
                    Spacer()
                    SBStat(value: "\(plan.tables.count)", label: "Tables")
                }

                // AI action card
                if unseatedCount(plan) > 0 {
                    aiActionCard(unseated: unseatedCount(plan))
                }
            }
        }
    }

    private func aiActionCard(unseated: Int) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Ready to seat")
                    .font(SBFont.caption)
                    .foregroundStyle(Color.sbIvory.opacity(0.7))
                Text("\(unseated) guests waiting")
                    .font(SBFont.bodySemibold)
                    .foregroundStyle(Color.sbIvory)
            }

            Spacer()

            SBButton(title: "AI seat \(unseated)", icon: "sparkles", variant: .gold, size: .small) {
                appState.selectedTab = .ai
            }
        }
        .padding(16)
        .background(Color.sbCharcoal)
        .clipShape(RoundedRectangle(cornerRadius: SBRadius.button))
    }

    // MARK: - Quick Actions

    private var quickActions: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            quickActionButton(icon: "person.2", title: "Guests", tab: .guests)
            quickActionButton(icon: "map", title: "Venue", tab: .edit)
            quickActionButton(icon: "list.bullet", title: "Rules", tab: .edit)
            quickActionButton(icon: "square.and.arrow.up", title: "Export", tab: .share)
        }
    }

    private func quickActionButton(icon: String, title: String, tab: SBTab) -> some View {
        Button {
            appState.selectedTab = tab
        } label: {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Color.sbGoldDk)
                Text(title)
                    .font(SBFont.bodySmallBold)
                    .foregroundStyle(Color.sbCharcoal)
                Spacer()
            }
            .padding(14)
            .background(Color.sbIvory2)
            .clipShape(RoundedRectangle(cornerRadius: SBRadius.button))
            .overlay(
                RoundedRectangle(cornerRadius: SBRadius.button)
                    .strokeBorder(Color.sbLine, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Other Plans

    private var otherPlans: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Other plans")
                .font(SBFont.label)
                .foregroundStyle(Color.sbWarm)
                .textCase(.uppercase)

            ForEach(plans.dropFirst()) { plan in
                planRow(plan)
            }
        }
    }

    private func planRow(_ plan: SeatingPlan) -> some View {
        Button {
            selectPlan(plan)
        } label: {
            HStack(spacing: 12) {
                SBTableGraphic(totalSeats: 8, filledSeats: min(plan.guests.count, 8), size: 44)

                VStack(alignment: .leading, spacing: 2) {
                    Text(plan.name)
                        .font(SBFont.bodySmallBold)
                        .foregroundStyle(Color.sbCharcoal)
                    Text("\(plan.guests.count) guests · \(plan.tables.count) tables")
                        .font(SBFont.caption)
                        .foregroundStyle(Color.sbWarm)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.sbWarm2)
            }
            .padding(12)
            .background(Color.sbIvory2)
            .clipShape(RoundedRectangle(cornerRadius: SBRadius.card))
        }
        .buttonStyle(.plain)
    }

    private func selectPlan(_ plan: SeatingPlan) {
        appState.activePlan = plan
        appState.selectedTab = .edit
        HapticEngine.selection()
    }

    // MARK: - Helpers

    private func seatedProgress(_ plan: SeatingPlan) -> CGFloat {
        guard plan.guests.count > 0 else { return 0 }
        let seated = plan.tables.reduce(0) { $0 + $1.filledCount }
        return CGFloat(seated) / CGFloat(plan.guests.count)
    }

    private func unseatedCount(_ plan: SeatingPlan) -> Int {
        let seated = plan.tables.reduce(0) { $0 + $1.filledCount }
        return max(0, plan.guests.count - seated)
    }

    private func loadPlans() async {
        do {
            plans = try await appState.database.fetchPlans()
            appState.activePlan = plans.first
            print("[Dashboard] Loaded \(plans.count) plans, active: \(plans.first?.name ?? "none")")
        } catch {
            print("[Dashboard] Error loading plans: \(error)")
            loadError = error.localizedDescription
        }
        isLoading = false
    }
}

#Preview {
    DashboardView()
        .environment(AppState())
}

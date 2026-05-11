import SwiftUI

struct DashboardView: View {
    @Environment(AppState.self) private var appState
    @State private var plans: [SeatingPlan] = []
    @State private var samplePlan: SeatingPlan?
    @State private var isLoading = true
    @State private var loadError: String?
    @State private var showEditPlan = false
    @State private var showSettings = false
    @State private var ctaAppeared = false

    /// Plan currently driving the hero card. Mirrors appState.activePlan so
    /// switches initiated from any tab keep the dashboard in sync, falling
    /// back to the first real plan on initial load.
    private var activePlan: SeatingPlan? {
        if let active = appState.activePlan { return active }
        return plans.first
    }

    /// True when the user has no real plans yet — drives the empty-state
    /// CTA. Demo plan never counts as a "real" plan for this check.
    private var hasNoRealPlans: Bool { plans.isEmpty }

    /// "Other Plans" feed: every plan that's not the active one, with the
    /// sample plan always pinned to the bottom (or only entry when there
    /// are no real plans yet).
    private var otherPlanRows: [SeatingPlan] {
        var rows = plans.filter { $0.id != activePlan?.id }
        if let sample = samplePlan, sample.id != activePlan?.id {
            rows.append(sample)
        }
        return rows
    }

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

                    // Welcome CTA — shown when the user has no real plans.
                    // Encourages creating their own event while keeping
                    // the sample plan visible below for exploration.
                    if !isLoading && hasNoRealPlans && loadError == nil {
                        VStack(spacing: 16) {
                            Image("SeatbeeLogo")
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 48, height: 48)
                                .scaleEffect(ctaAppeared ? 1 : 0.6)
                                .opacity(ctaAppeared ? 1 : 0)

                            Text("Ready to plan\nyour event?")
                                .font(SBFont.displayLarge)
                                .foregroundStyle(Color.sbCharcoal)
                                .multilineTextAlignment(.center)
                                .opacity(ctaAppeared ? 1 : 0)
                                .offset(y: ctaAppeared ? 0 : 12)

                            Text("Create your seating plan in minutes with AI")
                                .font(SBFont.body)
                                .foregroundStyle(Color.sbWarm)
                                .multilineTextAlignment(.center)
                                .opacity(ctaAppeared ? 1 : 0)
                                .offset(y: ctaAppeared ? 0 : 12)

                            SBButton(title: "Start planning", icon: "sparkles", variant: .gold, fullWidth: true) {
                                appState.showOnboarding = true
                            }
                            .opacity(ctaAppeared ? 1 : 0)
                            .offset(y: ctaAppeared ? 0 : 16)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 28)
                        .padding(.horizontal, 20)
                        .background(
                            RoundedRectangle(cornerRadius: 20)
                                .fill(
                                    LinearGradient(
                                        colors: [Color.sbChampagne.opacity(0.6), Color.sbIvory],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 20)
                                        .strokeBorder(Color.sbGold.opacity(0.3), lineWidth: 1)
                                )
                        )
                        .onAppear {
                            withAnimation(.spring(response: 0.7, dampingFraction: 0.8).delay(0.2)) {
                                ctaAppeared = true
                            }
                        }
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

                    // Quick actions — show whenever we have an active plan
                    // (real or sample) so the demo lets users explore the
                    // same UI flow real plans use.
                    if activePlan != nil {
                        quickActions
                    }

                    // Other plans — always rendered when there's at least
                    // one row to show. With the sample plan pinned at the
                    // bottom, this section is essentially always visible.
                    if !otherPlanRows.isEmpty {
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
            // Refresh pass inventory so tier gates anywhere in the app
            // (AI Generate, guest add, CSV import) can see passes the
            // user redeemed on web. Without this, plans where the tier
            // column is null but a pass IS applied (web's fallback path)
            // get treated as free on iOS.
            await appState.refreshPasses()
        }
        .sheet(isPresented: $showEditPlan) {
            EditPlanSheet()
                .environment(appState)
        }
        .sheet(isPresented: $showSettings) {
            SettingsSheet()
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
            .spotlightTag("tour_plus")

            Button {
                showSettings = true
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Color.sbWarm)
                    .frame(width: 36, height: 36)
                    .background(Color.sbIvory2)
                    .clipShape(Circle())
            }
            .spotlightTag("tour_settings")
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

                // Tier badge — shows which pass (if any) is applied to
                // this event. Tapping the free chip opens the paywall;
                // paid chips are informational. Branding matches the
                // EventPassesView statCards so users recognise tiers
                // wherever they appear in the app.
                tierBadge(for: plan)

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

    // MARK: - Tier badge
    //
    // Branding mirrors EventPassesView statCards (lines 64–68):
    //   Event Pass     — sbChampagne tint, sbGoldDk accent
    //   Signature Pass — sbChampagne2 tint, sbGoldDk accent
    //   Grand Pass     — sbCharcoal/10 tint, sbCharcoal accent
    //   Free / Expired — neutral warm tint with gold "Upgrade" CTA

    @ViewBuilder
    private func tierBadge(for plan: SeatingPlan) -> some View {
        let tier = appState.activePlanTier
        let expired = appState.isActivePlanExpired
        let daysLeft = appState.daysRemaining(for: plan)

        if plan.isDemo {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.system(size: 11, weight: .semibold))
                Text("Sample")
                    .font(SBFont.bodySmallBold)
            }
            .foregroundStyle(Color.sbGoldDk)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.sbChampagne)
            .clipShape(Capsule())
        } else if tier == .free || expired {
            // Free / expired → tappable upgrade chip.
            Button {
                appState.showUpgrade = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "ticket")
                        .font(.system(size: 11, weight: .semibold))
                    Text(expired ? "Pass expired" : "Free Plan")
                        .font(SBFont.bodySmallBold)
                    Text("·")
                        .foregroundStyle(Color.sbWarm)
                    Text("Upgrade")
                        .font(SBFont.bodySmallBold)
                    Image(systemName: "arrow.right")
                        .font(.system(size: 10, weight: .semibold))
                }
                .foregroundStyle(Color.sbGoldDk)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.sbChampagne)
                .clipShape(Capsule())
                .overlay(
                    Capsule().strokeBorder(Color.sbGoldDk.opacity(0.4), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
        } else {
            // Paid tier → informational chip styled per tier.
            let style = tierBadgeStyle(for: tier)
            HStack(spacing: 6) {
                Image(systemName: "ticket.fill")
                    .font(.system(size: 11, weight: .semibold))
                Text(tier.displayName)
                    .font(SBFont.bodySmallBold)
                if let daysLeft, daysLeft >= 0 {
                    Text("·")
                        .foregroundStyle(style.accent.opacity(0.6))
                    Text("\(daysLeft)d left")
                        .font(SBFont.caption)
                }
            }
            .foregroundStyle(style.accent)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(style.tint)
            .clipShape(Capsule())
        }
    }

    private func tierBadgeStyle(for tier: PlanTier) -> (tint: Color, accent: Color) {
        switch tier {
        case .eventPass:     return (Color.sbChampagne,             Color.sbGoldDk)
        case .signaturePass: return (Color.sbChampagne2,            Color.sbGoldDk)
        case .proPass:       return (Color.sbCharcoal.opacity(0.10), Color.sbCharcoal)
        case .free:          return (Color.sbChampagne,             Color.sbGoldDk)
        }
    }

    // MARK: - Quick Actions

    private var quickActions: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            quickActionButton(icon: "person.2", title: "Guests", tab: .guests)
            quickActionButton(icon: "map", title: "Venue", tab: .edit)
            // Rules routes to Guests tab (where the Rules sheet lives) and
            // asks GuestsView to open the Rules panel via pendingShowRules.
            quickActionButton(icon: "list.bullet", title: "Rules", tab: .guests, openRules: true)
            quickActionButton(icon: "square.and.arrow.up", title: "Export", tab: .share)
        }
    }

    private func quickActionButton(icon: String, title: String, tab: SBTab, openRules: Bool = false) -> some View {
        Button {
            if openRules { appState.pendingShowRules = true }
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

            ForEach(otherPlanRows) { plan in
                planRow(plan)
                    .if(plan.id == samplePlan?.id) { $0.spotlightTag("tour_sample") }
            }
        }
    }

    private func planRow(_ plan: SeatingPlan) -> some View {
        Button {
            selectPlan(plan)
        } label: {
            HStack(spacing: 12) {
                SBTableGraphic(totalSeats: 8, filledSeats: min(plan.guests.count, 8), size: 44)

                VStack(alignment: .leading, spacing: 4) {
                    Text(plan.name)
                        .font(SBFont.bodySmallBold)
                        .foregroundStyle(Color.sbCharcoal)
                    HStack(spacing: 6) {
                        Text("\(plan.guests.count) guests · \(plan.tables.count) tables")
                            .font(SBFont.caption)
                            .foregroundStyle(Color.sbWarm)
                        // Tier pill — at-a-glance read on which plan
                        // is on which tier without opening Event
                        // Passes. Resolves through the same chain as
                        // AppState.activePlanTier so plans with stale
                        // tier columns but valid event_pass_expires_at
                        // render correctly.
                        planTierPill(for: plan)
                    }
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

    /// Compact uppercase pill carrying the plan's effective tier.
    /// Free renders muted so paid plans visually pop on the list.
    @ViewBuilder
    private func planTierPill(for plan: SeatingPlan) -> some View {
        let (label, fg, bg): (String, Color, Color) = {
            // Sample plan gets its own pill so it's instantly recognisable
            // as "this isn't a real plan you can save".
            if plan.isDemo {
                return ("SAMPLE", Color.sbCharcoal, Color.sbChampagne2)
            }
            let tier = plan.resolvedTier(against: appState.userPasses)
            switch tier {
            case .free:           return ("FREE",      Color.sbWarm,    Color.sbWarm.opacity(0.10))
            case .eventPass:      return ("EVENT",     Color.sbGoldDk,  Color.sbChampagne)
            case .signaturePass:  return ("SIGNATURE", Color.white,     Color.sbGoldDk)
            case .proPass:        return ("GRAND",     Color.white,     Color.sbCharcoal)
            }
        }()
        Text(label)
            .font(.system(size: 9, weight: .bold))
            .kerning(1)
            .foregroundStyle(fg)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(bg)
            .clipShape(Capsule())
    }

    private func selectPlan(_ plan: SeatingPlan) {
        // Switch active plan WITHOUT navigating away. Bubble the chosen
        // plan to the top of the local list so the hero card updates and
        // the user can see they're now operating on a different plan
        // before deciding which tab to dive into.
        //
        // Guard against re-selecting the already-active plan — the hero
        // card itself calls selectPlan, so a hero tap shouldn't trigger
        // a redundant reorder animation.
        guard plan.id != activePlan?.id else { return }
        withAnimation(.spring(response: 0.35, dampingFraction: 0.78)) {
            // Reorder among real plans only. The sample plan stays separate
            // and is always pinned to the bottom of "Other plans" via
            // otherPlanRows; promoting it visually happens by setting
            // appState.activePlan, not by mutating the plans array.
            if !plan.isDemo, let idx = plans.firstIndex(where: { $0.id == plan.id }) {
                plans.remove(at: idx)
                plans.insert(plan, at: 0)
            }
            appState.activePlan = plan
        }
        HapticEngine.selection()
    }

    // MARK: - Helpers

    private func attendingGuests(_ plan: SeatingPlan) -> [Guest] {
        plan.guests.filter { $0.rsvp != .no }
    }

    private func seatedProgress(_ plan: SeatingPlan) -> CGFloat {
        let attending = attendingGuests(plan)
        guard !attending.isEmpty else { return 0 }
        let seatedIds = Set(plan.tables.flatMap { $0.assignments.keys })
        let seatedCount = attending.filter { seatedIds.contains($0.id) }.count
        return CGFloat(seatedCount) / CGFloat(attending.count)
    }

    private func unseatedCount(_ plan: SeatingPlan) -> Int {
        let seatedIds = Set(plan.tables.flatMap { $0.assignments.keys })
        return attendingGuests(plan).filter { !seatedIds.contains($0.id) }.count
    }

    private func loadPlans() async {
        // Sample plan loads from the bundle once and stays cached. Lazy-
        // load it the first time we render and reuse from the cache after.
        if samplePlan == nil {
            do {
                samplePlan = try SampleEventService.shared.load().plan
            } catch {
                print("[Dashboard] Sample plan load failed: \(error)")
            }
        }

        do {
            plans = try await appState.database.fetchPlans()
            // Preserve the user's current plan selection across
            // re-renders. The Plans tab's .task fires every time the
            // tab re-appears (e.g., user taps Guests then taps Plans
            // again); without the guard below, this method clobbered
            // the selection by re-pinning to plans.first — which
            // shifts as plans get re-sorted by updated_at after any
            // edit. Three cases:
            //   - No selection yet (initial load): leave nil so the
            //     empty state surfaces (user gets the "Plan your wedding"
            //     CTA on first launch with zero real plans).
            //   - Selection is the sample plan: leave it active so the
            //     dashboard keeps showing the demo even after a refresh.
            //   - Selection still valid in real plans: refresh its data
            //     and pin it to the top of the visible list.
            //   - Selection was deleted: fall back to first real plan
            //     (or nil → empty state).
            if appState.activePlan?.isDemo == true {
                // Keep sample as active — refresh from bundle in case the
                // generator was re-run mid-session.
                if let sample = samplePlan {
                    appState.activePlan = sample
                }
            } else if let currentId = appState.activePlan?.id,
                      let freshIdx = plans.firstIndex(where: { $0.id == currentId }) {
                let fresh = plans[freshIdx]
                appState.activePlan = fresh
                if freshIdx != 0 {
                    plans.remove(at: freshIdx)
                    plans.insert(fresh, at: 0)
                }
            } else {
                appState.activePlan = plans.first
            }
            print("[Dashboard] Loaded \(plans.count) real plans + sample, active: \(appState.activePlan?.name ?? "none")")
        } catch is CancellationError {
            // Task cancelled (e.g. view disappeared) — not a real error.
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

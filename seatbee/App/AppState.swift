import SwiftUI

@Observable
final class AppState {
    var selectedTab: SBTab = .plans
    var showSpotlightTour = false
    /// The plan the rest of the app reads + mutates. didSet auto-pushes
    /// the *previous* value to the undo stack on every change, so the
    /// 70+ existing `appState.activePlan = …` mutation sites all become
    /// undo-able for free. Two suppression escape hatches:
    ///   - `suppressNextHistorySnapshot` — single-shot, used internally
    ///     by undo() / redo() so the round-trip back doesn't itself
    ///     push to the undo stack.
    ///   - Plan-id mismatch — switching to a different plan (oldValue.id
    ///     != newValue.id) is a load, not a mutation. Same for the
    ///     initial nil → first-load.
    var activePlan: SeatingPlan? {
        didSet {
            if suppressNextHistorySnapshot {
                suppressNextHistorySnapshot = false
                return
            }
            // Only mutations to the SAME plan generate undo entries.
            // Plan-switch and initial-load are not user mutations.
            if let old = oldValue, let new = activePlan, old.id == new.id {
                undoManager.pushState(old)
            }
        }
    }
    /// Single-shot bypass — undo() / redo() / refreshActivePlan() set
    /// this to true before assigning so the resulting didSet doesn't
    /// double-record. Auto-clears on the next assignment.
    var suppressNextHistorySnapshot: Bool = false
    var isOnline = true
    var showAuth = false
    var showOnboarding = false
    var showUpgrade = false

    // Navigation paths for each tab
    var plansPath = NavigationPath()
    var guestsPath = NavigationPath()
    var editorPath = NavigationPath()
    var aiPath = NavigationPath()
    var sharePath = NavigationPath()

    // Services
    let auth = AuthService()
    let database = DatabaseService()
    let ai = AIService()
    let passes = PassesService()
    let seat = SeatService()
    let undoManager = SBUndoManager()

    // Pass inventory (web purchases — Apple IAP comes in Phase 2)
    var userPasses: PassesResponse = .empty
    var loadingPasses = false
    var passesLastFetched: Date?

    // One-shot per session: have we already shown the 80%-of-free-cap nudge?
    // Reset on new session (new app launch). Mirrors web's `limitToastFired`
    // ref at App.jsx:6211.
    var hasShownGuestSoftWarning = false

    // Cross-tab navigation hint: when the Plans-tab "Rules" quick-action
    // button is tapped, we switch to the Guests tab and ask GuestsView to
    // open the Rules sheet on next appearance. GuestsView reads + resets
    // this flag in onChange.
    var pendingShowRules = false

    // Last AI generation result, keyed by plan ID so it auto-invalidates
    // when the user switches plans. Survives tab navigation within a session.
    var lastGenResult: (planId: String, result: SeatService.GenerateResult)?

    // Last AI insight summary (the post-generate narrative card). Lives on
    // AppState so it survives tab navigation — without this it was a
    // @State on AIGenerateView and got discarded the moment the user
    // walked over to Plans/Edit/Share. Keyed by plan ID so switching
    // plans invalidates it; cleared on a new run before the network call.
    // Session-only: app restart wipes it (next run re-fetches).
    var lastGenInsight: (planId: String, result: AIService.ConflictResult)?

    /// Re-fetch the active plan from Supabase so tier/expiry
    /// columns reflect server-side changes (e.g. after an IAP).
    func refreshActivePlan() async {
        guard let plan = activePlan else { return }
        do {
            // Server refresh isn't a user mutation — don't pollute the
            // undo stack with it.
            suppressNextHistorySnapshot = true
            activePlan = try await database.fetchPlan(id: plan.id)
            print("[AppState] refreshActivePlan OK — tier: \(activePlan?.tier ?? "nil")")
        } catch {
            print("[AppState] refreshActivePlan error: \(error.localizedDescription)")
        }
    }

    /// Refresh the user's pass inventory from /api/passes.
    /// Safe to call on app foreground and after sign-in.
    func refreshPasses() async {
        guard auth.currentUser != nil else {
            userPasses = .empty
            return
        }
        loadingPasses = true
        defer { loadingPasses = false }
        do {
            userPasses = try await passes.fetchPasses()
            passesLastFetched = Date()
        } catch {
            // Silent fail on background refresh — UI screens that need passes
            // can surface their own error if a manual refresh fails.
            print("[AppState] refreshPasses error: \(error.localizedDescription)")
        }
    }

    /// Active plan's effective tier — mirrors web's resolution chain
    /// (App.jsx:6155-6191 + api/passes.js:250). Web learned the hard way
    /// that plan.tier alone isn't authoritative: collaborated plans, plans
    /// with stale tier columns, and plans where the pass was applied via
    /// promo all rely on the fallback paths below.
    ///
    /// Resolution order:
    ///   1. plan.tier if set to a paid tier AND not expired
    ///   2. plan.eventPassExpiresAt in the future → assume event_pass
    ///   3. userPasses contains a redeemed pass tied to this plan ID and
    ///      not expired → use that pass's tier (catches signature/grand)
    ///   4. free
    var activePlanTier: PlanTier {
        guard let plan = activePlan else { return .free }

        // 1. Direct tier column, respecting expiry.
        let raw = plan.tier ?? "free"
        if raw != "free" {
            if let exp = plan.eventPassExpiresAt, Date() > exp {
                // Paid tier but pass has expired — fall through to other
                // signals before giving up to free.
            } else {
                return PlanTier.from(raw)
            }
        }

        // 2. event_pass_expires_at fallback (web's api/passes.js:250).
        if let exp = plan.eventPassExpiresAt, Date() < exp {
            return .eventPass
        }

        // 3. Cross-reference user's pass inventory (web's effect at
        //    App.jsx:6155-6191) — most reliable for plans applied via
        //    promo or where the tier column is stale.
        if let pass = userPasses.passes.first(where: { p in
            p.status == "redeemed"
            && p.redeemedForPlanId == plan.id
            && (p.expiresAt.map { Date() < $0 } ?? true)
        }) {
            return pass.tier
        }

        return .free
    }

    /// Effective tier limits for the active plan. Expired plans collapse
    /// to free-tier limits.
    var activePlanLimits: TierLimits {
        TierLimits.limits(for: activePlanTier)
    }

    /// True if the active plan was on a paid tier (per any of the
    /// resolution paths above) but its pass is now in the past. Used to
    /// distinguish "expired" from "never had a pass" in error messages.
    var isActivePlanExpired: Bool {
        guard let plan = activePlan else { return false }
        let raw = plan.tier ?? "free"
        let everHadPaidTier = raw != "free"
            || plan.eventPassExpiresAt != nil
            || userPasses.passes.contains { $0.status == "redeemed" && $0.redeemedForPlanId == plan.id }
        guard everHadPaidTier else { return false }

        // If any future-dated signal exists, not expired.
        if let exp = plan.eventPassExpiresAt, Date() < exp { return false }
        if userPasses.passes.contains(where: { p in
            p.status == "redeemed"
            && p.redeemedForPlanId == plan.id
            && (p.expiresAt.map { Date() < $0 } ?? false)
        }) {
            return false
        }
        return true
    }

    /// Effective expiry date for a plan's pass, mirroring the
    /// resolution chain used by `activePlanTier`. Required because
    /// the `event_pass_expires_at` column on `seating_plans` was added
    /// part-way through the web app's life — older redemptions, admin
    /// overrides (web's `admin.js:5583`), and some legacy promo paths
    /// set `tier` without backfilling the column. We fall back to the
    /// user's pass inventory (which is the source of truth and always
    /// has `expires_at`).
    ///
    /// Resolution order:
    ///   1. plan.eventPassExpiresAt if set
    ///   2. user's redeemed pass tied to this plan ID, if any
    ///   3. plan.eventPassPurchasedAt + 180 days (matches web's
    ///      TIER_LIMITS expiry for all paid tiers)
    ///   4. nil — no expiry knowable; UI hides the days-left badge
    func effectivePassExpiry(for plan: SeatingPlan) -> Date? {
        if let exp = plan.eventPassExpiresAt { return exp }
        if let pass = userPasses.passes.first(where: { p in
            p.status == "redeemed" && p.redeemedForPlanId == plan.id
        }), let exp = pass.expiresAt {
            return exp
        }
        if let purchased = plan.eventPassPurchasedAt {
            return Calendar.current.date(byAdding: .day, value: 180, to: purchased)
        }
        return nil
    }

    /// Whole days between now and the plan's effective pass expiry
    /// (see `effectivePassExpiry`). Returns nil if no expiry is on
    /// file via any of the resolution paths.
    func daysRemaining(for plan: SeatingPlan) -> Int? {
        guard let exp = effectivePassExpiry(for: plan) else { return nil }
        let secs = exp.timeIntervalSince(Date())
        guard secs > 0 else { return 0 }
        return Int(secs / 86_400)
    }

    /// Number of unique guests currently seated at any table. Web parity
    /// (App.jsx ~4463 `seatedCount`) — only this number matters for the
    /// tier cap; the unsorted guest list itself is unmetered.
    var seatedGuestCount: Int {
        guard let plan = activePlan else { return 0 }
        var seen = Set<String>()
        for t in plan.tables {
            for gid in t.assignments.keys { seen.insert(gid) }
        }
        return seen.count
    }

    /// Can this guest be seated under the current tier? Returns true for
    /// existing-seated guests (a re-seat / move never counts against the
    /// cap), and for fresh seatings only when the cap has slack.
    func canSeatGuest(_ guestId: String) -> Bool {
        guard let plan = activePlan else { return false }
        let seated = plan.tables.flatMap { $0.assignments.keys }
        if seated.contains(guestId) { return true }
        return seated.count < activePlanLimits.seatedGuests
    }

    /// True when seating the next *new* guest will cross the 80% soft
    /// nudge threshold on a free plan. The toast fires once per session
    /// (gated by `hasShownGuestSoftWarning`) — mirrors web's nudge at
    /// App.jsx:4470 which only fires for free tier.
    var isAtSoftSeatedWarning: Bool {
        guard activePlanTier == .free else { return false }
        let limit = activePlanLimits.seatedGuests
        return seatedGuestCount >= Int(Double(limit) * 0.8)
    }

    /// Manual snapshot — kept for backward compat / explicit-snapshot
    /// flows. The didSet on activePlan now records every mutation
    /// automatically, so most call sites no longer need to call this.
    func pushUndo() {
        if let plan = activePlan {
            undoManager.pushState(plan)
        }
    }

    func undo() {
        guard let plan = activePlan,
              let previous = undoManager.undo(current: plan) else { return }
        // Suppress the didSet on the next assignment so applying the
        // undo doesn't itself push to the undo stack (which would loop
        // the user back to the state they just escaped from).
        suppressNextHistorySnapshot = true
        activePlan = previous
        Task { try? await database.savePlanData(plan: previous) }
    }

    func redo() {
        guard let plan = activePlan,
              let next = undoManager.redo(current: plan) else { return }
        suppressNextHistorySnapshot = true
        activePlan = next
        Task { try? await database.savePlanData(plan: next) }
    }
}

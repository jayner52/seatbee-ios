import SwiftUI

@Observable
final class AppState {
    var selectedTab: SBTab = .plans
    var activePlan: SeatingPlan?
    var isOnline = true
    var showAuth = false
    var showOnboarding = false

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
    let undoManager = SBUndoManager()

    // Pass inventory (web purchases — Apple IAP comes in Phase 2)
    var userPasses: PassesResponse = .empty
    var loadingPasses = false
    var passesLastFetched: Date?

    // One-shot per session: have we already shown the 80%-of-free-cap nudge?
    // Reset on new session (new app launch). Mirrors web's `limitToastFired`
    // ref at App.jsx:6211.
    var hasShownGuestSoftWarning = false

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

    /// Active plan's tier as enum (treats expired plans as free).
    var activePlanTier: PlanTier {
        if isActivePlanExpired { return .free }
        return PlanTier.from(activePlan?.tier)
    }

    /// Effective tier limits for the active plan. Expired plans collapse
    /// to free-tier limits.
    var activePlanLimits: TierLimits {
        TierLimits.limits(for: activePlanTier)
    }

    /// True if the active plan has a paid tier whose pass has expired.
    /// Free plans are never expired. Plans without expiry data are treated
    /// as not expired (defensive — server populates this when /api/passes
    /// is redeemed).
    var isActivePlanExpired: Bool {
        guard let plan = activePlan else { return false }
        let raw = plan.tier ?? "free"
        guard raw != "free" else { return false }
        guard let expiresAt = plan.eventPassExpiresAt else { return false }
        return Date() > expiresAt
    }

    /// Returns true if adding `count` more guests would exceed the active
    /// plan's seated-guest cap. Used to gate add/import flows.
    func wouldExceedGuestLimit(adding count: Int) -> Bool {
        guard let plan = activePlan else { return false }
        return plan.guests.count + count > activePlanLimits.seatedGuests
    }

    /// True when free-tier plan has crossed the 80% guest soft warning
    /// threshold. Mirrors web's nudge at App.jsx:6211.
    var isAtSoftGuestWarning: Bool {
        guard activePlanTier == .free, let plan = activePlan else { return false }
        let limit = activePlanLimits.seatedGuests
        return plan.guests.count >= Int(Double(limit) * 0.8)
    }

    // Push current state before a mutation
    func pushUndo() {
        if let plan = activePlan {
            undoManager.pushState(plan)
        }
    }

    func undo() {
        guard let plan = activePlan,
              let previous = undoManager.undo(current: plan) else { return }
        activePlan = previous
        Task { try? await database.savePlanData(plan: previous) }
    }

    func redo() {
        guard let plan = activePlan,
              let next = undoManager.redo(current: plan) else { return }
        activePlan = next
        Task { try? await database.savePlanData(plan: next) }
    }
}

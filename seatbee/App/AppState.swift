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

    /// Effective tier limits for the active plan. Falls back to free.
    var activePlanLimits: TierLimits {
        TierLimits.limits(for: activePlan?.tier)
    }

    /// Active plan's tier as enum.
    var activePlanTier: PlanTier {
        PlanTier.from(activePlan?.tier)
    }

    /// Returns true if adding `count` more guests would exceed the active
    /// plan's seated-guest cap. Used to gate add/import flows.
    func wouldExceedGuestLimit(adding count: Int) -> Bool {
        guard let plan = activePlan else { return false }
        return plan.guests.count + count > activePlanLimits.seatedGuests
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

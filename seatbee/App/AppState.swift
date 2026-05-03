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
    let undoManager = SBUndoManager()

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

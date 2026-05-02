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
}

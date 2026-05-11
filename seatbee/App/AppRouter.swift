import SwiftUI

struct AppRouter: View {
    @Environment(AppState.self) private var appState
    @State private var showFeatureTour = false

    var body: some View {
        @Bindable var state = appState

        ZStack(alignment: .bottom) {
            // Content tabs
            Group {
                switch state.selectedTab {
                case .plans:
                    DashboardView()
                case .guests:
                    GuestsView()
                case .edit:
                    EditorView()
                case .ai:
                    AIGenerateView()
                case .share:
                    ShareView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Custom tab bar pinned to bottom
            SBTabBar(selectedTab: $state.selectedTab)
        }
        .ignoresSafeArea(.keyboard)
        .fullScreenCover(isPresented: $state.showOnboarding) {
            OnboardingView()
                .environment(appState)
        }
        .sheet(isPresented: $state.showUpgrade) {
            UpgradeView()
                .environment(appState)
        }
        .fullScreenCover(isPresented: $showFeatureTour) {
            FeatureTourView()
        }
        .onAppear {
            if !UserDefaults.standard.bool(forKey: "seatbee.hasSeenFeatureTour") {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    showFeatureTour = true
                }
            }
        }
    }
}

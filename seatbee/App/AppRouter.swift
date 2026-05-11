import SwiftUI

struct AppRouter: View {
    @Environment(AppState.self) private var appState
    @State private var spotlightRects: [String: CGRect] = [:]

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

            // Spotlight tour overlay (renders ON TOP of real UI)
            if state.showSpotlightTour {
                SpotlightTourOverlay(
                    isShowing: $state.showSpotlightTour,
                    spotlightRects: spotlightRects
                )
                .ignoresSafeArea()
            }
        }
        .coordinateSpace(name: "spotlight")
        .onPreferenceChange(SpotlightPreferenceKey.self) { items in
            for item in items {
                spotlightRects[item.id] = item.rect
            }
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
        .onAppear {
            if !UserDefaults.standard.bool(forKey: "seatbee.hasSeenFeatureTour") {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    appState.showSpotlightTour = true
                }
            }
        }
    }
}

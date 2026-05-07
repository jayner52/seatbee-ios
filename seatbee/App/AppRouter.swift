import SwiftUI

struct AppRouter: View {
    @Environment(AppState.self) private var appState

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
        .onChange(of: state.showUpgrade) { _, show in
            guard show else { return }
            if AppConfig.iapEnabled {
                // Native paywall — handled by the sheet below
            } else {
                // IAP not QA'd yet — send to web pricing
                state.showUpgrade = false
                if let url = URL(string: "https://seatbee.app/pricing") {
                    UIApplication.shared.open(url)
                }
            }
        }
        .sheet(isPresented: Binding(
            get: { state.showUpgrade && AppConfig.iapEnabled },
            set: { state.showUpgrade = $0 }
        )) {
            UpgradeView()
                .environment(appState)
        }
    }
}

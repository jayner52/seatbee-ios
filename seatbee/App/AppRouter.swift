import SwiftUI

struct AppRouter: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var state = appState

        ZStack(alignment: .bottom) {
            TabView(selection: $state.selectedTab) {
                DashboardView()
                    .tag(SBTab.plans)

                GuestsView()
                    .tag(SBTab.guests)

                EditorView()
                    .tag(SBTab.edit)

                AIGenerateView()
                    .tag(SBTab.ai)

                ShareView()
                    .tag(SBTab.share)
            }
            .tabViewStyle(.automatic)
            // Hide default tab bar
            .toolbar(.hidden, for: .tabBar)

            // Custom glassmorphic tab bar
            SBTabBar(selectedTab: $state.selectedTab)
        }
        .ignoresSafeArea(.keyboard)
    }
}

import SwiftUI

struct AppRouter: View {
    @Environment(AppState.self) private var appState
    @State private var spotlightRects: [String: CGRect] = [:]
    /// First-run "try Pro" paywall, shown once per device before the
    /// feature tour. Skippable via the small text link (no X) — see
    /// UpgradeContext.onboardingFlow.
    @State private var showOnboardingPaywall = false

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
        .fullScreenCover(isPresented: $showOnboardingPaywall, onDismiss: {
            // The feature tour waits its turn behind the intro paywall so a
            // new user never gets two overlays stacked on first launch.
            startFeatureTourIfNeeded(after: 0.6)
        }) {
            UpgradeView(context: .onboardingFlow)
                .environment(appState)
        }
        .onAppear {
            let defaults = UserDefaults.standard
            let isFirstRun = !defaults.bool(forKey: "seatbee.hasSeenFeatureTour")
            let hasSeenIntroPaywall = defaults.bool(forKey: "seatbee.hasSeenOnboardingPaywall")

            // First-run sequence: intro paywall (skippable) → feature tour.
            // Existing installs already have hasSeenFeatureTour set, so they
            // never see the intro paywall — only fresh devices do.
            if isFirstRun && !hasSeenIntroPaywall
                && appState.userSubscription?.isProEntitled != true {
                defaults.set(true, forKey: "seatbee.hasSeenOnboardingPaywall")
                appState.upgradeTrigger = "onboarding_intro"
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                    showOnboardingPaywall = true
                }
            } else {
                startFeatureTourIfNeeded(after: 1.0)
            }
        }
    }

    private func startFeatureTourIfNeeded(after delay: Double) {
        guard !UserDefaults.standard.bool(forKey: "seatbee.hasSeenFeatureTour") else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            appState.showSpotlightTour = true
        }
    }
}

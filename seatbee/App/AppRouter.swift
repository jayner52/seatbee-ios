import SwiftUI

struct AppRouter: View {
    @Environment(AppState.self) private var appState
    @State private var spotlightRects: [String: CGRect] = [:]
    /// First-run "try Pro" paywall, shown once per device before the
    /// feature tour. Skippable via the small text link (no X) — see
    /// UpgradeContext.onboardingFlow.
    @State private var showOnboardingPaywall = false
    @State private var showContactEmailPrompt = false

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
        .sheet(isPresented: $showContactEmailPrompt) {
            ContactEmailSheet()
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
        .task {
            await maybeShowContactEmailPrompt()
        }
    }

    private func startFeatureTourIfNeeded(after delay: Double) {
        guard !UserDefaults.standard.bool(forKey: "seatbee.hasSeenFeatureTour") else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            appState.showSpotlightTour = true
        }
    }

    /// One-time ask for a reachable email, for users whose sign-in address is
    /// an Apple Hide My Email relay (or missing entirely). See ContactEmailSheet.
    ///
    /// Last in the first-run queue, behind the intro paywall and the feature
    /// tour. Gating on `hasSeenFeatureTour` means a fresh device can't stack
    /// three overlays, and it puts a launch between Sign in with Apple and an
    /// email ask rather than pinning them back to back.
    ///
    /// The authoritative "already asked" gate is server-side
    /// (profiles.contact_email_prompted_at), because it has to survive
    /// reinstalls and follow the user across devices. The UserDefaults key here
    /// is only a local suppressor so a slow or offline round trip can't produce
    /// a second sheet in the same install.
    private func maybeShowContactEmailPrompt() async {
        guard !showContactEmailPrompt else { return }
        guard UserDefaults.standard.bool(forKey: "seatbee.hasSeenFeatureTour") else { return }
        guard !UserDefaults.standard.bool(forKey: Self.contactEmailPromptShownKey) else { return }
        guard !appState.showOnboarding, !appState.showUpgrade, !appState.showSpotlightTour else { return }
        guard !showOnboardingPaywall else { return }
        guard await appState.auth.needsContactEmailPrompt() else { return }

        UserDefaults.standard.set(true, forKey: Self.contactEmailPromptShownKey)
        // Stamp "asked" up front rather than on dismissal, so a swipe-down, a
        // force-quit, or the Not now button all leave the same state and
        // nobody gets asked twice. A save later overwrites contact_email
        // itself; prompted_at is already correct either way.
        await appState.auth.markContactEmailPrompted()
        showContactEmailPrompt = true
    }

    private static let contactEmailPromptShownKey = "seatbee.contactEmailPromptShown"
}

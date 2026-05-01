import SwiftUI
import SwiftData

@main
struct SeatbeeApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(appState)
                .onOpenURL { url in
                    Task {
                        await appState.auth.handleDeepLink(url: url)
                    }
                }
        }
    }
}

struct RootView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        Group {
            if appState.auth.isAuthenticated {
                AppRouter()
            } else {
                AuthView()
            }
        }
        .preferredColorScheme(.light)
        .animation(.seatbeeScreen, value: appState.auth.isAuthenticated)
    }
}

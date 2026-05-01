import SwiftUI

struct LandingView: View {
    @Environment(AppState.self) private var appState
    var planName: String = "Sarah & Jon"
    var sharedBy: String = "Sarah"

    var body: some View {
        VStack(spacing: 0) {
            Spacer().frame(height: 60)

            // Shared by chip
            HStack(spacing: 8) {
                SBAvatar(name: sharedBy, size: 24)
                Text("\(sharedBy) shared this")
                    .font(SBFont.meta)
                    .foregroundStyle(Color.sbWarm)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.sbIvory2)
            .clipShape(Capsule())

            Spacer().frame(height: 24)

            // Headline
            VStack(spacing: 4) {
                Text(planName)
                    .font(SBFont.displayHero)
                    .foregroundStyle(Color.sbCharcoal)

                Text("wedding")
                    .font(SBFont.fraunces(28, weight: .medium))
                    .foregroundStyle(Color.sbGoldDk)
                    .italic()
            }

            Spacer().frame(height: 8)

            // Date/venue
            Text("June 15, 2026 · The Garden House")
                .font(SBFont.meta)
                .foregroundStyle(Color.sbWarm)

            Spacer().frame(height: 32)

            // Mini canvas preview
            miniCanvas
                .frame(height: 180)
                .frame(maxWidth: .infinity)
                .background(Color.sbIvory2)
                .clipShape(RoundedRectangle(cornerRadius: SBRadius.card))
                .padding(.horizontal, SBSpacing.screenMargin)

            Spacer()

            // CTAs
            VStack(spacing: 14) {
                SBButton(title: "Save this plan", variant: .primary, fullWidth: true) {
                    appState.showAuth = true
                }

                SBButton(title: "Keep viewing", variant: .ghost, fullWidth: true) {
                    // Navigate to read-only editor
                }
            }
            .padding(.horizontal, SBSpacing.screenMargin)
            .padding(.bottom, 40)
        }
        .background(Color.sbIvory)
    }

    // MARK: - Mini Canvas

    private var miniCanvas: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3), spacing: 12) {
            ForEach(0..<6, id: \.self) { i in
                SBTableGraphic(totalSeats: 8, filledSeats: Int.random(in: 4...8), size: 50)
            }
        }
        .padding(20)
    }
}

#Preview {
    LandingView()
        .environment(AppState())
}

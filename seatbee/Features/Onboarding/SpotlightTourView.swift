import SwiftUI

// MARK: - Preference key for collecting spotlight rects

struct SpotlightItem: Equatable {
    let id: String
    let rect: CGRect
}

struct SpotlightPreferenceKey: PreferenceKey {
    static var defaultValue: [SpotlightItem] = []
    static func reduce(value: inout [SpotlightItem], nextValue: () -> [SpotlightItem]) {
        value.append(contentsOf: nextValue())
    }
}

// MARK: - View modifier to tag spotlightable elements

extension View {
    func spotlightTag(_ id: String) -> some View {
        self.overlay(
            GeometryReader { geo in
                Color.clear
                    .preference(
                        key: SpotlightPreferenceKey.self,
                        value: [SpotlightItem(id: id, rect: geo.frame(in: .named("spotlight")))]
                    )
            }
        )
    }
}

// MARK: - Tour step definition

struct TourStep {
    let spotlightId: String
    let title: String
    let description: String
}

// MARK: - Spotlight overlay

struct SpotlightTourOverlay: View {
    @Binding var isShowing: Bool
    let spotlightRects: [String: CGRect]

    @State private var step = 0
    @State private var appeared = false

    private let steps: [TourStep] = [
        TourStep(spotlightId: "tour_plus", title: "Create a new event", description: "Tap here to start planning your wedding or celebration."),
        TourStep(spotlightId: "tour_tab_plans", title: "Your events", description: "View and switch between your seating plans."),
        TourStep(spotlightId: "tour_tab_guests", title: "Guest list", description: "Add guests, import CSVs, track RSVPs and dietary needs."),
        TourStep(spotlightId: "tour_tab_edit", title: "Visual editor", description: "Drag tables and objects on an interactive canvas."),
        TourStep(spotlightId: "tour_tab_ai", title: "AI seating", description: "Let AI arrange your guests based on your rules."),
        TourStep(spotlightId: "tour_tab_share", title: "Share & export", description: "Export PDFs, generate QR codes, invite collaborators."),
        TourStep(spotlightId: "tour_sample", title: "Explore the sample", description: "Tap to explore a pre-built wedding with 122 guests."),
        TourStep(spotlightId: "tour_settings", title: "Settings", description: "Manage your account, event passes, and preferences."),
    ]

    private var currentStep: TourStep { steps[step] }

    private var targetRect: CGRect {
        spotlightRects[currentStep.spotlightId] ?? .zero
    }

    private var spotlightPadding: CGFloat { 8 }

    private var spotlightRect: CGRect {
        targetRect.insetBy(dx: -spotlightPadding, dy: -spotlightPadding)
    }

    // Place tooltip above if element is in bottom half, below otherwise
    private var tooltipAbove: Bool {
        targetRect.midY > UIScreen.main.bounds.height * 0.5
    }

    var body: some View {
        ZStack {
            // Dimmed scrim with spotlight cutout
            scrim
                .ignoresSafeArea()
                .opacity(appeared ? 1 : 0)

            // Tooltip card
            if targetRect != .zero {
                tooltipCard
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }
        }
        .animation(.easeInOut(duration: 0.3), value: step)
        .onAppear {
            withAnimation(.easeOut(duration: 0.4)) { appeared = true }
        }
        .onTapGesture {
            advance()
        }
    }

    // MARK: - Scrim with cutout

    private var scrim: some View {
        Color.black.opacity(0.7)
            .reverseMask {
                RoundedRectangle(cornerRadius: 12)
                    .frame(width: spotlightRect.width, height: spotlightRect.height)
                    .position(x: spotlightRect.midX, y: spotlightRect.midY)
            }
    }

    // MARK: - Tooltip

    private var tooltipCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(currentStep.title)
                .font(SBFont.bodySemibold)
                .foregroundStyle(Color.sbCharcoal)

            Text(currentStep.description)
                .font(SBFont.caption)
                .foregroundStyle(Color.sbWarm)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Text("\(step + 1) of \(steps.count)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.sbWarm2)

                Spacer()

                if step < steps.count - 1 {
                    Button("Skip") { completeTour() }
                        .font(SBFont.inter(13, weight: .medium))
                        .foregroundStyle(Color.sbWarm)
                }

                Button(step == steps.count - 1 ? "Done" : "Next") { advance() }
                    .font(SBFont.inter(13, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.sbGoldDk)
                    .clipShape(Capsule())
            }
        }
        .padding(16)
        .background(Color.sbIvory)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .shadow(color: .black.opacity(0.15), radius: 12, y: 4)
        .frame(maxWidth: 300)
        .position(tooltipPosition)
    }

    private var tooltipPosition: CGPoint {
        let x = min(max(targetRect.midX, 170), UIScreen.main.bounds.width - 170)
        if tooltipAbove {
            return CGPoint(x: x, y: spotlightRect.minY - 80)
        } else {
            return CGPoint(x: x, y: spotlightRect.maxY + 80)
        }
    }

    // MARK: - Actions

    private func advance() {
        if step < steps.count - 1 {
            step += 1
        } else {
            completeTour()
        }
    }

    private func completeTour() {
        UserDefaults.standard.set(true, forKey: "seatbee.hasSeenFeatureTour")
        withAnimation(.easeOut(duration: 0.25)) {
            appeared = false
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            isShowing = false
        }
    }
}

// MARK: - Reverse mask helper

extension View {
    func reverseMask<Mask: View>(@ViewBuilder _ mask: () -> Mask) -> some View {
        self.mask(
            Rectangle()
                .overlay(
                    mask()
                        .blendMode(.destinationOut)
                )
                .compositingGroup()
        )
    }
}

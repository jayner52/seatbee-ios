import SwiftUI

struct FeatureTourView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var currentPage = 0
    @State private var appeared = false

    private let pages: [TourPage] = [
        TourPage(
            icon: "sparkles",
            iconColor: Color.sbGold,
            headline: "Welcome to Seatbee",
            description: "Plan your perfect seating arrangement in minutes — powered by AI."
        ),
        TourPage(
            icon: "person.2.fill",
            iconColor: Color.sbSage,
            headline: "Manage your\nguest list",
            description: "Add guests one by one, paste a list, or import a CSV. Track RSVPs, dietary needs, meals, and categories."
        ),
        TourPage(
            icon: "pencil.and.ruler.fill",
            iconColor: Color.sbBlush,
            headline: "Design your\nlayout",
            description: "Drag tables and venue objects on an interactive canvas. Set up your room shape, upload a floor plan, and arrange everything visually."
        ),
        TourPage(
            icon: "sparkles",
            iconColor: Color.sbGold,
            headline: "AI-powered\nseating",
            description: "Let AI seat your guests automatically based on your rules — keep groups together, separate feuding relatives, assign VIPs."
        ),
        TourPage(
            icon: "list.bullet.rectangle.fill",
            iconColor: Color.sbWarm,
            headline: "Set seating\nrules",
            description: "Create parties, seat-together groups, keep-apart rules, and table assignments. AI uses these to build the perfect arrangement."
        ),
        TourPage(
            icon: "square.and.arrow.up.fill",
            iconColor: Color.sbGoldDk,
            headline: "Share &\nexport",
            description: "Generate a guest QR code, export seating charts and place cards as PDF, invite collaborators, and share via CSV."
        ),
    ]

    var body: some View {
        ZStack {
            Color.sbIvory.ignoresSafeArea()

            VStack(spacing: 0) {
                // Skip button
                HStack {
                    Spacer()
                    if currentPage < pages.count - 1 {
                        Button("Skip") {
                            completeTour()
                        }
                        .font(SBFont.bodySemibold)
                        .foregroundStyle(Color.sbWarm)
                        .padding(.trailing, 24)
                        .padding(.top, 16)
                    }
                }
                .frame(height: 44)

                // Pages
                TabView(selection: $currentPage) {
                    ForEach(Array(pages.enumerated()), id: \.offset) { index, page in
                        tourPageView(page, index: index)
                            .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))

                // Dots + button
                VStack(spacing: 24) {
                    // Custom page dots
                    HStack(spacing: 8) {
                        ForEach(0..<pages.count, id: \.self) { i in
                            Circle()
                                .fill(i == currentPage ? Color.sbGold : Color.sbWarm2.opacity(0.4))
                                .frame(width: i == currentPage ? 10 : 7, height: i == currentPage ? 10 : 7)
                                .animation(.spring(response: 0.3), value: currentPage)
                        }
                    }

                    // CTA button
                    if currentPage == pages.count - 1 {
                        SBButton(title: "Get Started", icon: "arrow.right", variant: .gold, fullWidth: true) {
                            completeTour()
                        }
                        .padding(.horizontal, 32)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                    } else {
                        Button {
                            withAnimation(.seatbeeSpring) {
                                currentPage += 1
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Text("Next")
                                    .font(SBFont.bodySemibold)
                                Image(systemName: "arrow.right")
                                    .font(.system(size: 14, weight: .semibold))
                            }
                            .foregroundStyle(Color.sbGoldDk)
                        }
                    }
                }
                .padding(.bottom, 60)
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.8).delay(0.1)) {
                appeared = true
            }
        }
    }

    private func tourPageView(_ page: TourPage, index: Int) -> some View {
        VStack(spacing: 20) {
            Spacer()

            // Icon
            Image(systemName: page.icon)
                .font(.system(size: 56))
                .foregroundStyle(page.iconColor)
                .frame(width: 100, height: 100)
                .background(page.iconColor.opacity(0.12))
                .clipShape(Circle())
                .scaleEffect(appeared && currentPage == index ? 1 : 0.7)
                .opacity(appeared && currentPage == index ? 1 : 0)
                .animation(.spring(response: 0.5, dampingFraction: 0.7).delay(0.1), value: currentPage)

            // Headline
            Text(page.headline)
                .font(SBFont.displayLarge)
                .foregroundStyle(Color.sbCharcoal)
                .multilineTextAlignment(.center)
                .opacity(appeared && currentPage == index ? 1 : 0)
                .offset(y: appeared && currentPage == index ? 0 : 15)
                .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.2), value: currentPage)

            // Description
            Text(page.description)
                .font(SBFont.body)
                .foregroundStyle(Color.sbWarm)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
                .opacity(appeared && currentPage == index ? 1 : 0)
                .offset(y: appeared && currentPage == index ? 0 : 15)
                .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.3), value: currentPage)

            Spacer()
            Spacer()
        }
    }

    private func completeTour() {
        UserDefaults.standard.set(true, forKey: "seatbee.hasSeenFeatureTour")
        dismiss()
    }
}

private struct TourPage {
    let icon: String
    let iconColor: Color
    let headline: String
    let description: String
}

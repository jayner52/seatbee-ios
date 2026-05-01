import SwiftUI

enum SBTab: Int, CaseIterable {
    case plans = 0
    case guests
    case edit
    case ai
    case share

    var label: String {
        switch self {
        case .plans: return "Plans"
        case .guests: return "Guests"
        case .edit: return "Edit"
        case .ai: return "AI"
        case .share: return "Share"
        }
    }

    var icon: String {
        switch self {
        case .plans: return "square.grid.2x2"
        case .guests: return "person.2"
        case .edit: return "pencil.and.ruler"
        case .ai: return "sparkles"
        case .share: return "square.and.arrow.up"
        }
    }

    var isHighlighted: Bool {
        self == .ai
    }
}

struct SBTabBar: View {
    @Binding var selectedTab: SBTab

    var body: some View {
        HStack(spacing: 0) {
            ForEach(SBTab.allCases, id: \.rawValue) { tab in
                tabItem(tab)
            }
        }
        .padding(.top, 10)
        .padding(.bottom, 22)
        .background(
            Rectangle()
                .fill(.ultraThinMaterial)
                .overlay(
                    Color.sbIvory.opacity(0.88)
                )
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(Color.sbLine)
                        .frame(height: 0.5)
                }
        )
    }

    private func tabItem(_ tab: SBTab) -> some View {
        Button {
            withAnimation(.seatbee) {
                selectedTab = tab
            }
        } label: {
            VStack(spacing: 4) {
                Image(systemName: tab.icon)
                    .font(.system(size: 22, weight: .regular))
                    .foregroundStyle(tabColor(tab))

                Text(tab.label.uppercased())
                    .font(SBFont.capsLabel)
                    .foregroundStyle(tabColor(tab))
                    .letterSpacing(0.5)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }

    private func tabColor(_ tab: SBTab) -> Color {
        if selectedTab == tab {
            return tab.isHighlighted ? .sbGold : .sbCharcoal
        }
        return .sbWarm
    }
}

#Preview {
    VStack {
        Spacer()
        SBTabBar(selectedTab: .constant(.edit))
    }
    .background(Color.sbIvory)
}

import SwiftUI

enum SBButtonVariant {
    case gold
    case primary
    case ghost
    case `default`
}

enum SBButtonSize {
    case small
    case regular
}

struct SBButton: View {
    let title: String
    var icon: String? = nil
    var variant: SBButtonVariant = .primary
    var size: SBButtonSize = .regular
    var fullWidth: Bool = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: size == .small ? 12 : 14, weight: .semibold))
                }
                Text(title)
                    .font(size == .small ? SBFont.meta : SBFont.bodySemibold)
            }
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .padding(.horizontal, size == .small ? 14 : 20)
            .padding(.vertical, size == .small ? 8 : 14)
            .background(backgroundColor)
            .foregroundStyle(foregroundColor)
            .clipShape(RoundedRectangle(cornerRadius: size == .small ? SBRadius.small : SBRadius.button))
            .overlay(
                RoundedRectangle(cornerRadius: size == .small ? SBRadius.small : SBRadius.button)
                    .strokeBorder(borderColor, lineWidth: variant == .ghost ? 1 : 0)
            )
            .shadow(
                color: variant == .gold ? Color(.sRGB, red: 201/255, green: 169/255, blue: 97/255, opacity: 0.3) : .clear,
                radius: variant == .gold ? 12 : 0,
                x: 0,
                y: variant == .gold ? 4 : 0
            )
        }
        .buttonStyle(.plain)
    }

    private var backgroundColor: Color {
        switch variant {
        case .gold: return .sbGold
        case .primary: return .sbCharcoal
        case .ghost: return .clear
        case .default: return .sbChampagne
        }
    }

    private var foregroundColor: Color {
        switch variant {
        case .gold: return .white
        case .primary: return .sbIvory
        case .ghost: return .sbCharcoal
        case .default: return .sbGoldDk
        }
    }

    private var borderColor: Color {
        switch variant {
        case .ghost: return .sbLine2
        default: return .clear
        }
    }
}

#Preview {
    VStack(spacing: 16) {
        SBButton(title: "AI seat 18", icon: "sparkles", variant: .gold, fullWidth: true) {}
        SBButton(title: "Save this plan", variant: .primary, fullWidth: true) {}
        SBButton(title: "Keep viewing", variant: .ghost, fullWidth: true) {}
        SBButton(title: "Family", variant: .default, size: .small) {}
    }
    .padding()
    .background(Color.sbIvory)
}

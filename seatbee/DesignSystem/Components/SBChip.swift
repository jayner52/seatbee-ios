import SwiftUI

enum SBChipVariant {
    case `default`
    case gold
    case muted
}

struct SBChip: View {
    let text: String
    var variant: SBChipVariant = .default
    var icon: String? = nil

    var body: some View {
        HStack(spacing: 4) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .semibold))
            }
            Text(text)
                .font(SBFont.small)
                .fontWeight(.semibold)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(chipBackground)
        .foregroundStyle(chipForeground)
        .clipShape(RoundedRectangle(cornerRadius: SBRadius.chip))
        .overlay(
            RoundedRectangle(cornerRadius: SBRadius.chip)
                .strokeBorder(chipBorder, style: StrokeStyle(lineWidth: 1, dash: variant == .muted ? [3, 2] : []))
        )
    }

    private var chipBackground: Color {
        switch variant {
        case .default: return .sbIvory2
        case .gold: return .sbChampagne
        case .muted: return .clear
        }
    }

    private var chipForeground: Color {
        switch variant {
        case .default: return .sbCharcoal2
        case .gold: return .sbGoldDk
        case .muted: return .sbWarm2
        }
    }

    private var chipBorder: Color {
        switch variant {
        case .muted: return .sbWarm2
        default: return .clear
        }
    }
}

#Preview {
    HStack(spacing: 8) {
        SBChip(text: "Family")
        SBChip(text: "Near cake", variant: .gold)
        SBChip(text: "+ tag", variant: .muted)
        SBChip(text: "Veg", icon: "leaf")
    }
    .padding()
    .background(Color.sbIvory)
}

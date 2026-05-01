import SwiftUI

struct SBCard<Content: View>: View {
    var elevated: Bool = false
    var backgroundColor: Color = .sbIvory
    var padding: CGFloat = SBSpacing.cardPadding
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .padding(padding)
            .background(backgroundColor)
            .clipShape(RoundedRectangle(cornerRadius: SBRadius.card))
            .overlay(
                RoundedRectangle(cornerRadius: SBRadius.card)
                    .strokeBorder(Color.sbLine, lineWidth: elevated ? 0 : 1)
            )
            .if(elevated) { view in
                view.sbCardShadow()
            }
    }
}

extension View {
    @ViewBuilder
    func `if`<Transform: View>(_ condition: Bool, transform: (Self) -> Transform) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }
}

#Preview {
    VStack(spacing: 16) {
        SBCard {
            Text("Default Card")
                .font(SBFont.body)
        }

        SBCard(elevated: true, backgroundColor: .sbIvory2) {
            Text("Elevated Card")
                .font(SBFont.body)
        }
    }
    .padding()
    .background(Color.sbIvory)
}

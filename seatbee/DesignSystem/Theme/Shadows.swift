import SwiftUI

enum SBShadow {
    static let sm = ShadowStyle(
        color: Color(.sRGB, red: 201/255, green: 169/255, blue: 97/255, opacity: 0.12),
        radius: 4,
        x: 0,
        y: 1
    )

    static let md = ShadowStyle(
        color: Color(.sRGB, red: 201/255, green: 169/255, blue: 97/255, opacity: 0.18),
        radius: 14,
        x: 0,
        y: 4
    )

    static let lg = ShadowStyle(
        color: Color(.sRGB, red: 45/255, green: 45/255, blue: 45/255, opacity: 0.12),
        radius: 32,
        x: 0,
        y: 12
    )

    static let goldButton = ShadowStyle(
        color: Color(.sRGB, red: 201/255, green: 169/255, blue: 97/255, opacity: 0.3),
        radius: 12,
        x: 0,
        y: 4
    )
}

struct ShadowStyle {
    let color: Color
    let radius: CGFloat
    let x: CGFloat
    let y: CGFloat
}

extension View {
    func sbShadow(_ style: ShadowStyle) -> some View {
        self.shadow(color: style.color, radius: style.radius, x: style.x, y: style.y)
    }

    func sbCardShadow() -> some View {
        self
            .shadow(color: Color(.sRGB, red: 201/255, green: 169/255, blue: 97/255, opacity: 0.18), radius: 14, x: 0, y: 4)
            .shadow(color: Color(.sRGB, red: 45/255, green: 45/255, blue: 45/255, opacity: 0.05), radius: 6, x: 0, y: 2)
    }
}

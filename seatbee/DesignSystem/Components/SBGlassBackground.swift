import SwiftUI

struct SBGlassBackground: View {
    var tint: Color = .sbIvory
    var opacity: Double = 0.88

    var body: some View {
        Rectangle()
            .fill(tint.opacity(opacity))
            .background(.ultraThinMaterial)
    }
}

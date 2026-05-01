import SwiftUI

extension Animation {
    /// Premium ease - matches brand cubic-bezier(.07,.96,.72,.96)
    static let seatbee = Animation.timingCurve(0.07, 0.96, 0.72, 0.96, duration: 0.2)

    /// Screen transition timing
    static let seatbeeScreen = Animation.timingCurve(0.07, 0.96, 0.72, 0.96, duration: 0.25)

    /// Slower version for larger movements
    static let seatbeeSlow = Animation.timingCurve(0.07, 0.96, 0.72, 0.96, duration: 0.4)

    /// Spring for score reveals and bouncy elements
    static let seatbeeSpring = Animation.spring(response: 0.4, dampingFraction: 0.7)

    /// Pulse animation for AI progress
    static let seatbeePulse = Animation.easeInOut(duration: 1.2).repeatForever(autoreverses: true)
}

// MARK: - Transition Helpers

extension AnyTransition {
    /// Fade + slight slide up (for cards appearing)
    static let sbSlideUp = AnyTransition.asymmetric(
        insertion: .move(edge: .bottom).combined(with: .opacity),
        removal: .opacity
    )

    /// Simple fade matching brand timing
    static let sbFade = AnyTransition.opacity.animation(.seatbeeScreen)
}

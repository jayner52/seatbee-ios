import SwiftUI

enum SBFont {
    // MARK: - Fraunces (Display/Headings)
    static func fraunces(_ size: CGFloat, weight: Font.Weight = .medium) -> Font {
        .custom("Fraunces", size: size).weight(weight)
    }

    // MARK: - Inter (Body/UI)
    static func inter(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        return .custom("Inter", size: size).weight(weight)
    }

    // MARK: - Raleway Dots (Logo accent only)
    static func ralewayDots(_ size: CGFloat) -> Font {
        return .custom("RalewayDots-Regular", size: size)
    }

    // MARK: - Semantic Styles

    /// 34px Fraunces - Hero headlines
    static let displayHero = fraunces(34, weight: .medium)
    /// 28px Fraunces - Screen titles
    static let displayLarge = fraunces(28, weight: .medium)
    /// 22px Fraunces - Section headers
    static let displayMedium = fraunces(22, weight: .medium)
    /// 20px Fraunces - Card titles
    static let displaySmall = fraunces(20, weight: .medium)
    /// 17px Fraunces - Nav titles
    static let displayNav = fraunces(17, weight: .medium)

    /// 32px Fraunces - Stat numbers
    static let statNumber = fraunces(32, weight: .medium)
    /// 28px Fraunces - Stat numbers (smaller)
    static let statNumberSmall = fraunces(28, weight: .medium)

    /// 15px Inter - Body text
    static let body = inter(15, weight: .regular)
    /// 15px Inter - Body semibold
    static let bodySemibold = inter(15, weight: .semibold)
    /// 14px Inter - Body smaller
    static let bodySmall = inter(14, weight: .regular)
    /// 14px Inter - Bold body
    static let bodySmallBold = inter(14, weight: .semibold)

    /// 13px Inter - Metadata, dates
    static let meta = inter(13, weight: .regular)
    /// 12px Inter - Captions, footer text
    static let caption = inter(12, weight: .regular)
    /// 11px Inter - Small labels
    static let small = inter(11, weight: .regular)

    /// 11px Inter 600 uppercase - Section labels
    static let label = inter(11, weight: .semibold)
    /// 10px Inter 600 uppercase - Caps labels (stat labels, tab labels)
    static let capsLabel = inter(10, weight: .semibold)
}

// MARK: - Letter Spacing Modifier

struct LetterSpacingModifier: ViewModifier {
    let spacing: CGFloat

    func body(content: Content) -> some View {
        content.tracking(spacing)
    }
}

extension View {
    func letterSpacing(_ spacing: CGFloat) -> some View {
        modifier(LetterSpacingModifier(spacing: spacing))
    }
}

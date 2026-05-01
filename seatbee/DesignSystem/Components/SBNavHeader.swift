import SwiftUI

struct SBNavHeader: View {
    var title: String = ""
    var backLabel: String? = nil
    var translucent: Bool = false
    var dark: Bool = false
    var backAction: (() -> Void)? = nil
    var rightContent: AnyView? = nil

    var body: some View {
        HStack {
            if let backAction {
                Button(action: backAction) {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 14, weight: .semibold))
                        if let backLabel {
                            Text(backLabel)
                                .font(SBFont.bodySmall)
                        }
                    }
                    .foregroundStyle(dark ? Color.sbIvory : Color.sbGoldDk)
                }
            }

            Spacer()

            if !title.isEmpty {
                Text(title)
                    .font(SBFont.displayNav)
                    .foregroundStyle(dark ? Color.sbIvory : Color.sbCharcoal)
            }

            Spacer()

            if let rightContent {
                rightContent
            } else {
                // Invisible spacer to balance layout
                Color.clear.frame(width: 44, height: 1)
            }
        }
        .padding(.horizontal, SBSpacing.screenMargin)
        .padding(.vertical, 12)
        .background(
            Group {
                if translucent {
                    Color.sbIvory.opacity(0.88)
                        .background(.ultraThinMaterial)
                } else if dark {
                    Color.sbCharcoal
                } else {
                    Color.sbIvory
                }
            }
        )
    }
}

#Preview {
    VStack(spacing: 0) {
        SBNavHeader(
            title: "Guests",
            backLabel: "Back",
            backAction: {}
        )
        Spacer()
    }
    .background(Color.sbIvory)
}

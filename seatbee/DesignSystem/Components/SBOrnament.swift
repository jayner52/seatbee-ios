import SwiftUI

struct SBOrnament: View {
    var label: String? = nil

    var body: some View {
        HStack(spacing: 12) {
            line
            if let label {
                Text(label.uppercased())
                    .font(SBFont.capsLabel)
                    .foregroundStyle(Color.sbWarm)
                    .letterSpacing(1.5)
            }
            line
        }
        .padding(.vertical, SBSpacing.sm)
    }

    private var line: some View {
        Rectangle()
            .fill(Color.sbLine)
            .frame(height: 0.5)
    }
}

#Preview {
    VStack(spacing: 20) {
        SBOrnament()
        SBOrnament(label: "OR")
        SBOrnament(label: "Share via")
    }
    .padding()
    .background(Color.sbIvory)
}

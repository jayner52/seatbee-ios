import SwiftUI

struct SBStat: View {
    let value: String
    let label: String
    var color: Color = .sbCharcoal

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(SBFont.statNumber)
                .foregroundStyle(color)
                .contentTransition(.numericText())

            Text(label.uppercased())
                .font(SBFont.capsLabel)
                .foregroundStyle(Color.sbWarm)
                .letterSpacing(1.5)
        }
    }
}

#Preview {
    HStack(spacing: 32) {
        SBStat(value: "142", label: "Guests")
        SBStat(value: "18", label: "Unseated", color: .sbGoldDk)
        SBStat(value: "124", label: "RSVP'd", color: .sbSage)
    }
    .padding()
    .background(Color.sbIvory)
}

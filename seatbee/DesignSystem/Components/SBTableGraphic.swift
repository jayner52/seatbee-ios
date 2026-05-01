import SwiftUI

struct SBTableGraphic: View {
    let totalSeats: Int
    var filledSeats: Int = 0
    var label: String? = nil
    var size: CGFloat = 70
    var isSelected: Bool = false

    var body: some View {
        ZStack {
            // Table circle
            Circle()
                .fill(Color.sbChampagne)
                .stroke(Color.sbCharcoal.opacity(0.15), lineWidth: 1)
                .frame(width: tableSize, height: tableSize)

            // Seats arranged radially
            ForEach(0..<totalSeats, id: \.self) { index in
                seatDot(filled: index < filledSeats)
                    .offset(y: -seatRadius)
                    .rotationEffect(.degrees(Double(index) * 360.0 / Double(totalSeats)))
            }

            // Center label
            if let label {
                Text(label)
                    .font(SBFont.fraunces(size * 0.16, weight: .medium))
                    .foregroundStyle(Color.sbCharcoal)
            }
        }
        .frame(width: size, height: size)
        .overlay(
            Circle()
                .strokeBorder(Color.sbGold, style: StrokeStyle(lineWidth: 2, dash: [4, 3]))
                .padding(-4)
                .opacity(isSelected ? 1 : 0)
        )
        .scaleEffect(isSelected ? 1.06 : 1.0)
        .animation(.seatbee, value: isSelected)
    }

    private var tableSize: CGFloat {
        size * 0.52
    }

    private var seatRadius: CGFloat {
        size * 0.38
    }

    private var seatDotSize: CGFloat {
        size * 0.12
    }

    private func seatDot(filled: Bool) -> some View {
        Circle()
            .fill(filled ? Color.sbGold : Color.sbIvory)
            .stroke(filled ? Color.sbGold : Color.sbWarm2, lineWidth: 1)
            .frame(width: seatDotSize, height: seatDotSize)
    }
}

#Preview {
    HStack(spacing: 20) {
        SBTableGraphic(totalSeats: 8, filledSeats: 5, label: "5")
        SBTableGraphic(totalSeats: 8, filledSeats: 8, label: "8", isSelected: true)
        SBTableGraphic(totalSeats: 10, filledSeats: 3, label: "3", size: 90)
    }
    .padding()
    .background(Color.sbIvory2)
}

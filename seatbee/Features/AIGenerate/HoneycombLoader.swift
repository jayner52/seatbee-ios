import SwiftUI

// HoneycombLoader — staggered hexagon grid that pulses while AI seating
// is in progress. The cells fade up and down with a phase offset that
// sweeps diagonally across the grid, so the eye reads it as a wave of
// activity rather than a uniform blink.
//
// Used by AIGenerateView's `.generating` state.

struct HoneycombLoader: View {
    /// Number of hex columns / rows in the grid. 5×4 reads well at 220pt.
    private let cols = 5
    private let rows = 4

    /// One full pulse takes ~1.5s; each cell is offset by a fraction of
    /// that based on its diagonal index, producing the wave effect.
    private let cycleSeconds: Double = 1.6

    var body: some View {
        TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            GeometryReader { geo in
                ZStack {
                    ForEach(0..<rows, id: \.self) { row in
                        ForEach(0..<cols, id: \.self) { col in
                            cell(row: row, col: col, t: t, geo: geo)
                        }
                    }
                }
            }
        }
    }

    private func cell(row: Int, col: Int, t: Double, geo: GeometryProxy) -> some View {
        let cellW: CGFloat = geo.size.width / CGFloat(cols)
        let cellH: CGFloat = cellW * 0.95
        // Diagonal phase offset so the wave sweeps NW → SE.
        let phaseDenom = Double(rows + cols - 2)
        let phase = Double(row + col) / max(1, phaseDenom)
        let raw = t / cycleSeconds + phase
        let normalized = raw.truncatingRemainder(dividingBy: 1)
        // 0…1 sine wave shaped to dwell at low/high.
        let wave = (sin(normalized * 2 * .pi - .pi / 2) + 1) / 2
        let opacity: Double = 0.20 + 0.80 * wave
        let scale: Double = 0.85 + 0.15 * wave
        let xOffset: CGFloat = row.isMultiple(of: 2) ? 0 : cellW / 2
        let posX: CGFloat = cellW * (CGFloat(col) + 0.5) + xOffset
        let posY: CGFloat = cellH * (CGFloat(row) + 0.5)
        return Image(systemName: "hexagon.fill")
            .resizable()
            .scaledToFit()
            .frame(width: cellW * 0.82, height: cellH * 0.82)
            .foregroundStyle(Color.sbGold.opacity(opacity))
            .scaleEffect(scale)
            .position(x: posX, y: posY)
    }
}

#Preview {
    HoneycombLoader()
        .frame(width: 220, height: 220)
        .background(Color.sbIvory)
}

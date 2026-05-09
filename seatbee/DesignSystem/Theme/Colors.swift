import SwiftUI
import UIKit

extension Color {
    // MARK: - Seatbee Brand Colors

    static let sbIvory = Color(hex: "FFFEF9")
    static let sbIvory2 = Color(hex: "FAF6EC")
    static let sbChampagne = Color(hex: "F7E7CE")
    static let sbChampagne2 = Color(hex: "EFDDB9")
    static let sbGold = Color(hex: "C9A961")
    static let sbGoldDk = Color(hex: "A88843")
    static let sbGoldLt = Color(hex: "E8D5A3")
    static let sbCharcoal = Color(hex: "2D2D2D")
    static let sbCharcoal2 = Color(hex: "4A4641")
    static let sbWarm = Color(hex: "8B8680")
    static let sbWarm2 = Color(hex: "B9B3A6")
    static let sbSage = Color(hex: "9CAF88")
    static let sbBlush = Color(hex: "D4A5A5")
    static let sbPlum = Color(hex: "9B8EC4")          // Grand Pass accent (web --color-grand)
    static let sbPlumLt = Color(hex: "F3F0FA")        // Grand Pass light tint
    static let sbError = Color(hex: "C17B7B")

    static let sbLine = Color(hex: "2D2D2D").opacity(0.10)
    static let sbLine2 = Color(hex: "2D2D2D").opacity(0.18)

    // MARK: - Hex Initializer

    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3:
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }

    /// "#RRGGBB" hex string for the receiver's sRGB components. Used
    /// when the system ColorPicker round-trips into a hex-string
    /// field (e.g. SeatTable.color). Alpha is dropped — table /
    /// category colours don't use it.
    func toHexString() -> String {
        let resolved = UIColor(self).cgColor.components ?? [0, 0, 0, 1]
        let r = Int((resolved.indices.contains(0) ? resolved[0] : 0) * 255)
        let g = Int((resolved.indices.contains(1) ? resolved[1] : 0) * 255)
        let b = Int((resolved.indices.contains(2) ? resolved[2] : 0) * 255)
        return String(format: "#%02X%02X%02X",
                      max(0, min(255, r)),
                      max(0, min(255, g)),
                      max(0, min(255, b)))
    }
}

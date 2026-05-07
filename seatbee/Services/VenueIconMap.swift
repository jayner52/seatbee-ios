import UIKit

/// Maps the web app's venue-object icon names (which are NOT SF Symbol
/// names — see `Icon` component in `src/App.jsx`) to the closest SF
/// Symbol so iOS can render objects that round-trip through Supabase.
///
/// The catalog (`VenueObjectsSheet.swift`) stores web-style names so iOS
/// and web both persist the same string. Only the on-screen rendering
/// converts to SF Symbols.
///
/// `sfSymbol(for:)` is forgiving: if the input already names a valid SF
/// Symbol it returns it as-is. Falls back to `"circle.fill"` for anything
/// truly unknown so we never show the broken-image questionmark glyph.
enum VenueIconMap {

    /// Web → SF Symbol mapping. Mirrors `Icon` component handling at
    /// `src/App.jsx` line 229. New web icons should be added here in the
    /// same PR so iOS doesn't regress to questionmarks.
    private static let mapping: [String: String] = [
        // Music + entertainment
        "music":       "music.note",
        "star":        "star.fill",
        "headphones":  "headphones",
        "volume":      "speaker.wave.2.fill",
        "mic":         "mic.fill",

        // Food + beverage
        "glass":       "wineglass.fill",
        "list":        "list.bullet",
        "cake":        "birthday.cake.fill",
        "coffee":      "cup.and.saucer.fill",
        "utensils":    "fork.knife",

        // Photo + decor
        "camera":      "camera.fill",
        "frame":       "photo.on.rectangle",
        "flower":      "leaf.fill",
        "sparkle":     "sparkles",

        // Ceremony / structure
        "arch":        "arrow.up.left.and.arrow.down.right",
        "tent":        "tent.fill",
        "path":        "road.lanes",
        "flame":       "flame.fill",
        "gift":        "gift.fill",
        "lightbulb":   "lightbulb.fill",
        "flag":        "flag.fill",
        "door":        "door.left.hand.open",

        // A/V + tech
        "image":       "photo.fill",
        "settings":    "gearshape.fill",
        "zap":         "bolt.fill",

        // Services / signage
        "clipboard":   "list.clipboard.fill",
        "file":        "doc.fill",
        "tag":         "tag.fill",
        "sign":        "signpost.right.fill",
        "inbox":       "tray.fill",
        "users":       "person.2.fill",
        "heart":       "heart.fill",

        // Geometric shapes
        "circle":      "circle.fill",
        "square":      "square.fill",
        "rect":        "rectangle.fill",
        "type":        "textformat",
    ]

    /// Resolve a web icon name (or already-SF-Symbol name) to an SF Symbol.
    /// Forgiving on unknowns so we never render `questionmark.circle`.
    static func sfSymbol(for icon: String?) -> String {
        guard let icon, !icon.isEmpty else { return "circle.fill" }
        // Already a valid SF Symbol? (Catches old iOS-created objects whose
        // `RoomObject.icon` was persisted as e.g. `"music.note"`.)
        if UIImage(systemName: icon) != nil { return icon }
        if let mapped = mapping[icon] { return mapped }
        // Last-resort fallback. `circle.fill` always exists in SF Symbols.
        return "circle.fill"
    }
}

import Foundation

// MARK: - SeatingPlan (top-level domain model)
// See PARITY.md for the canonical field reference.

struct SeatingPlan: Identifiable, Codable {
    let id: String
    var name: String
    var eventDate: Date?
    var venue: String?
    var eventType: EventType
    var tables: [SeatTable]
    var guests: [Guest]
    var rules: [SeatingRule]
    var objects: [RoomObject]
    var roomWidth: Double?
    var roomHeight: Double?
    // Venue setup (web parity — see PARITY.md and src/App.jsx:11046-11589):
    // these were being silently dropped on iOS save before 2026-05-04. iOS
    // now preserves them on round-trip. Coordinates inside customRoomPoints
    // are absolute pixels (0..roomWidth, 0..roomHeight), matching web's
    // SCALE = 15 px/ft.
    var roomShape: String? = nil
    var measurementUnit: String? = nil      // "imperial" | "metric"
    var customRoomPoints: [RoomPoint]? = nil
    var roomFlipH: Bool? = nil
    var roomFlipV: Bool? = nil
    var roomZones: [RoomZone]? = nil
    var hasSweetheartTable: Bool? = nil
    var createdAt: Date?
    var updatedAt: Date?
    var userId: String?
    var tier: String?
    // Pass expiry — top-level columns on `seating_plans`, set by the web's
    // /api/passes redemption flow. iOS reads these but never writes them
    // (Supabase PATCH preserves untouched columns).
    var eventPassExpiresAt: Date?
    var eventPassPurchasedAt: Date?

    // Raw passthrough: entities iOS doesn't model but must preserve on round-trip
    var rawCategories: [[String: AnyCodable]]?
    var rawParties: [[String: AnyCodable]]?
    var rawGroups: [[String: AnyCodable]]?
    var rawFloorPlanImage: AnyCodable?
    var rawFloorPlanOpacity: Double?
    var rawSeatOrders: [String: AnyCodable]?
    // Web's guestQR config blob ({linkToken, enabled, qrStyle, icebreakers, ...}).
    // iOS reads linkToken + enabled to render the QR; everything else round-trips
    // unchanged so web-side styling / icebreakers survive an iOS save.
    var rawGuestQR: AnyCodable?

    enum EventType: String, Codable, CaseIterable {
        case wedding
        case corporate
        case celebration
        case custom
    }
}

// MARK: - Room geometry (web parity)
//
// Web stores customRoomPoints as an array of {x, y, arc?} where arc is
// an optional {rx, ry, sweep, largeArc} object. Straight walls have no
// arc; double-tap on a wall to add an arc. Coordinates are absolute
// pixels relative to the room origin (0,0) at the top-left.

struct RoomPoint: Codable, Equatable {
    var x: Double
    var y: Double
    var arc: RoomArc?
}

struct RoomArc: Codable, Equatable {
    var rx: Double
    var ry: Double
    var sweep: Int
    var largeArc: Int
}

// Zone = labeled rectangular area inside the room (e.g. Dance Floor).
// Web key: roomZones array of {id, label, x, y, w, h}.
struct RoomZone: Codable, Identifiable, Equatable {
    let id: String
    var label: String
    var x: Double
    var y: Double
    var w: Double
    var h: Double
}

// Direct port of web's getDefaultPoints (src/App.jsx:3763-3789). When the
// user picks a preset shape, generate the canonical point array for that
// shape at the given dimensions. iOS reuses these for canvas rendering
// fallback when customRoomPoints is missing, AND for the eventual trace
// modal (PR V2).
enum RoomShapePresets {
    static func defaultPoints(shape: String, width w: Double, height h: Double) -> [RoomPoint] {
        switch shape.lowercased() {
        case "l":
            return [
                .init(x: 0, y: 0), .init(x: w*0.6, y: 0), .init(x: w*0.6, y: h*0.5),
                .init(x: w, y: h*0.5), .init(x: w, y: h), .init(x: 0, y: h)
            ]
        case "l_rev":
            return [
                .init(x: w*0.4, y: 0), .init(x: w, y: 0), .init(x: w, y: h),
                .init(x: 0, y: h), .init(x: 0, y: h*0.5), .init(x: w*0.4, y: h*0.5)
            ]
        case "t":
            return [
                .init(x: w*0.2, y: 0), .init(x: w*0.8, y: 0), .init(x: w*0.8, y: h*0.35),
                .init(x: w, y: h*0.35), .init(x: w, y: h), .init(x: 0, y: h),
                .init(x: 0, y: h*0.35), .init(x: w*0.2, y: h*0.35)
            ]
        case "u":
            return [
                .init(x: 0, y: 0), .init(x: w*0.3, y: 0), .init(x: w*0.3, y: h*0.6),
                .init(x: w*0.7, y: h*0.6), .init(x: w*0.7, y: 0), .init(x: w, y: 0),
                .init(x: w, y: h), .init(x: 0, y: h)
            ]
        case "circle":
            let r = min(w, h) / 2
            let cx = w / 2, cy = h / 2
            let arc = RoomArc(rx: r, ry: r, sweep: 1, largeArc: 0)
            return [
                RoomPoint(x: cx, y: cy - r, arc: arc),
                RoomPoint(x: cx + r, y: cy, arc: arc),
                RoomPoint(x: cx, y: cy + r, arc: arc),
                RoomPoint(x: cx - r, y: cy, arc: arc),
            ]
        case "oval":
            let arc = RoomArc(rx: w * 0.5, ry: h * 0.5, sweep: 1, largeArc: 0)
            return [
                RoomPoint(x: w * 0.5, y: 0,       arc: arc),
                RoomPoint(x: w,       y: h * 0.5, arc: arc),
                RoomPoint(x: w * 0.5, y: h,       arc: arc),
                RoomPoint(x: 0,       y: h * 0.5, arc: arc),
            ]
        default:  // "rect" or unknown
            return [
                .init(x: 0, y: 0), .init(x: w, y: 0),
                .init(x: w, y: h), .init(x: 0, y: h)
            ]
        }
    }
}

extension RoomPoint {
    init(x: Double, y: Double) {
        self.x = x; self.y = y; self.arc = nil
    }
}

// Web's UNITS table (src/App.jsx:2577-2579). All persisted room dims are
// pixels; the unit is just a display preference. iOS uses these factors to
// convert user-entered ft/m back to pixels on save and pixels to ft/m on load.
enum RoomScale {
    static let imperial: Double = 15.0
    static let metric: Double = 49.21
    static func factor(for unit: String?) -> Double {
        (unit ?? "imperial").lowercased() == "metric" ? metric : imperial
    }
    static func unitLabel(for unit: String?) -> String {
        (unit ?? "imperial").lowercased() == "metric" ? "m" : "ft"
    }
}

// Lenient bridge between AnyCodable (DTO storage — preserves any shape on
// round-trip) and typed RoomPoint / RoomZone (iOS-side use). Bad legacy
// entries decode as nil rather than blowing up the entire plan fetch.
enum RoomGeometryCoder {
    static func decodePoints(_ raw: AnyCodable?) -> [RoomPoint]? {
        guard let array = raw?.value as? [Any], !array.isEmpty else { return nil }
        let pts: [RoomPoint] = array.compactMap { item in
            guard let dict = item as? [String: Any] else { return nil }
            guard let x = numericDouble(dict["x"]), let y = numericDouble(dict["y"]) else { return nil }
            var arc: RoomArc?
            if let arcDict = dict["arc"] as? [String: Any] {
                let rx = numericDouble(arcDict["rx"]) ?? 0
                let ry = numericDouble(arcDict["ry"]) ?? 0
                let sweep = numericInt(arcDict["sweep"]) ?? 1
                let largeArc = numericInt(arcDict["largeArc"]) ?? 0
                arc = RoomArc(rx: rx, ry: ry, sweep: sweep, largeArc: largeArc)
            }
            return RoomPoint(x: x, y: y, arc: arc)
        }
        return pts.isEmpty ? nil : pts
    }

    static func encodePoints(_ pts: [RoomPoint]?) -> AnyCodable? {
        guard let pts = pts, !pts.isEmpty else { return nil }
        let array: [[String: Any]] = pts.map { p in
            var dict: [String: Any] = ["x": p.x, "y": p.y]
            if let arc = p.arc {
                dict["arc"] = [
                    "rx": arc.rx, "ry": arc.ry,
                    "sweep": arc.sweep, "largeArc": arc.largeArc
                ]
            }
            return dict
        }
        return AnyCodable(array)
    }

    static func decodeZones(_ raw: AnyCodable?) -> [RoomZone]? {
        guard let array = raw?.value as? [Any], !array.isEmpty else { return nil }
        let zones: [RoomZone] = array.compactMap { item in
            guard let dict = item as? [String: Any] else { return nil }
            let id = (dict["id"] as? String) ?? UUID().uuidString
            let label = (dict["label"] as? String) ?? "Area"
            guard let x = numericDouble(dict["x"]),
                  let y = numericDouble(dict["y"]),
                  let w = numericDouble(dict["w"]),
                  let h = numericDouble(dict["h"]) else { return nil }
            return RoomZone(id: id, label: label, x: x, y: y, w: w, h: h)
        }
        return zones.isEmpty ? nil : zones
    }

    static func encodeZones(_ zones: [RoomZone]?) -> AnyCodable? {
        guard let zones = zones, !zones.isEmpty else { return nil }
        let array: [[String: Any]] = zones.map { z in
            ["id": z.id, "label": z.label, "x": z.x, "y": z.y, "w": z.w, "h": z.h]
        }
        return AnyCodable(array)
    }

    private static func numericDouble(_ any: Any?) -> Double? {
        if let d = any as? Double { return d }
        if let i = any as? Int { return Double(i) }
        if let s = any as? String { return Double(s) }
        return nil
    }

    private static func numericInt(_ any: Any?) -> Int? {
        if let i = any as? Int { return i }
        if let d = any as? Double { return Int(d) }
        if let s = any as? String { return Int(s) }
        return nil
    }
}

// MARK: - SeatTable

struct SeatTable: Identifiable, Codable {
    let id: String
    var name: String
    var type: TableType
    var seats: Int
    var x: Double
    var y: Double
    var rotation: Double?
    var assignments: [String: Int] // guestId -> seatIndex
    var locked: Bool?
    var color: String?
    // Web-parity fields (preserved on round-trip)
    var width: Double?      // rect/head table width in px
    var height: Double?     // rect/head table height in px
    var diameter: Double?   // round table diameter in px
    var sweetShape: String? // "heart"/"oval"/"diamond" for sweetheart
    var oneSide: Bool?      // head table one-side-only seating

    enum TableType: String, Codable, CaseIterable {
        case round
        case rect
        case head
        case sweetheart
        case oval     // ellipse-shaped table; seats distributed around perimeter
    }

    var filledCount: Int {
        assignments.count
    }
}

// MARK: - Guest

struct Guest: Identifiable, Codable {
    let id: String
    var name: String
    var firstName: String?
    var lastName: String?
    var email: String?
    var categories: [String]
    var dietary: String?
    var notes: String?
    var rsvp: RSVPStatus
    var side: GuestSide
    var vip: Bool
    var accessibility: String?
    var plusOne: Bool?
    var party: String?
    // Web-parity fields (preserved on round-trip)
    var display: String?
    var dietaryTags: [String]?   // per-restriction tags for emoji rendering
    var highChair: Bool?
    var isChild: Bool?           // web persists this as a separate boolean (NOT a category)
    var groupIds: [String]?
    var isBride: Bool?           // cached flag
    var isGroom: Bool?           // cached flag
    var meal: String?
    var guestCreatedAt: String?  // "createdAt" in web — renamed to avoid conflict with plan-level

    enum RSVPStatus: String, Codable {
        case yes
        case no
        case pending
        case unknown
    }

    enum GuestSide: String, Codable {
        case bride
        case groom
        case both
        case none
    }

    var displayName: String {
        if let d = display, !d.isEmpty { return d }
        if let first = firstName, let last = lastName {
            return "\(first) \(last)"
        }
        return name
    }

    var initials: String {
        let parts = displayName.split(separator: " ")
        if parts.count >= 2 {
            return String(parts[0].prefix(1) + parts[1].prefix(1)).uppercased()
        }
        return String(displayName.prefix(2)).uppercased()
    }
}

// MARK: - SeatingRule

struct SeatingRule: Identifiable, Codable {
    let id: String
    var type: RuleType
    var guests: [String]
    var tableId: String?
    var weight: Int
    var hard: Bool
    var enabled: Bool
    // Web-parity fields
    var categoryId: String?
    var objectId: String?
    var sideValue: String?
    var sideA: [String]? = nil   // Keep Apart "Side A" guest IDs (web parity)
    var sideB: [String]? = nil   // Keep Apart "Side B" guest IDs (web parity)
    var desc: String?
    var auto: Bool?
    var source: String?
    var partyId: String?
    var groupId: String?

    enum RuleType: Codable, Equatable, Hashable {
        case mustTogether
        case preferTogether
        case mustNot
        case mustTable
        case nearTable
        case nearObject
        case categoryTogether
        case vipPriority
        case sideTogether
        case seatAdjacent
        case unknown(String)

        var rawValue: String {
            switch self {
            case .mustTogether: return "must_together"
            case .preferTogether: return "prefer_together"
            case .mustNot: return "must_not"
            case .mustTable: return "must_table"
            case .nearTable: return "near_table"
            case .nearObject: return "near_object"
            case .categoryTogether: return "category_together"
            case .vipPriority: return "vip_priority"
            case .sideTogether: return "side_together"
            case .seatAdjacent: return "seat_adjacent"
            case .unknown(let raw): return raw
            }
        }

        static func parse(_ raw: String?) -> RuleType {
            guard let raw = raw else {
                print("[Seatbee] ⚠️ Rule has nil type — preserving as .unknown(\"\")")
                return .unknown("")
            }
            switch raw {
            // Canonical web snake_case values
            case "must_together":     return .mustTogether
            case "prefer_together":   return .preferTogether
            case "must_not":          return .mustNot
            case "must_table":        return .mustTable
            case "near_table":        return .nearTable
            case "near_object":       return .nearObject
            case "category_together": return .categoryTogether
            case "vip_priority":      return .vipPriority
            case "side_together":     return .sideTogether
            case "seat_adjacent":     return .seatAdjacent
            // Legacy iOS camelCase — migrate on read
            case "seatTogether":      return .mustTogether
            case "keepApart":         return .mustNot
            case "assignTable":       return .mustTable
            case "seatNear":          return .nearTable
            default:
                print("[Seatbee] ⚠️ Unknown rule type: '\(raw)' — preserving raw on round-trip.")
                return .unknown(raw)
            }
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            let raw = try container.decode(String.self)
            self = RuleType.parse(raw)
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            try container.encode(rawValue)
        }
    }
}

// MARK: - RoomObject

struct RoomObject: Identifiable, Codable {
    let id: String
    var type: String
    var name: String
    var x: Double
    var y: Double
    var width: Double
    var height: Double
    var rotation: Double?
    // Web-parity fields
    var color: String?
    var category: String?    // e.g. "entertainment", "food"
    var icon: String?        // icon name from web
    var isObstacle: Bool?
}

// MARK: - AnyCodable (type-erased JSON value for passthrough)

struct AnyCodable: Codable {
    let value: Any

    init(_ value: Any) {
        self.value = value
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let bool = try? container.decode(Bool.self) { value = bool }
        else if let int = try? container.decode(Int.self) { value = int }
        else if let double = try? container.decode(Double.self) { value = double }
        else if let string = try? container.decode(String.self) { value = string }
        else if let array = try? container.decode([AnyCodable].self) { value = array.map(\.value) }
        else if let dict = try? container.decode([String: AnyCodable].self) { value = dict.mapValues(\.value) }
        else if container.decodeNil() { value = NSNull() }
        else { value = NSNull() }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch value {
        case let bool as Bool: try container.encode(bool)
        case let int as Int: try container.encode(int)
        case let double as Double: try container.encode(double)
        case let string as String: try container.encode(string)
        case let array as [Any]:
            try container.encode(array.map { AnyCodable($0) })
        case let dict as [String: Any]:
            try container.encode(dict.mapValues { AnyCodable($0) })
        default:
            try container.encodeNil()
        }
    }
}

// MARK: - Reverse Mapping (Domain → DTO for saving to Supabase)

extension SeatingPlan {
    func toPlanData() -> PlanDataDTO {
        var assignmentsMap: [String: AssignmentDTO] = [:]
        for table in tables {
            for (guestId, seatIndex) in table.assignments {
                assignmentsMap[guestId] = AssignmentDTO(tableId: table.id, seatIndex: seatIndex)
            }
        }

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"

        return PlanDataDTO(
            event: EventDataDTO(
                name: name,
                date: eventDate.map { dateFormatter.string(from: $0) },
                venue: venue,
                eventType: eventType.rawValue,
                roomWidth: roomWidth,
                roomHeight: roomHeight,
                roomShape: roomShape,
                measurementUnit: measurementUnit,
                customRoomPoints: RoomGeometryCoder.encodePoints(customRoomPoints),
                roomFlipH: roomFlipH,
                roomFlipV: roomFlipV,
                roomZones: RoomGeometryCoder.encodeZones(roomZones),
                hasSweetheartTable: hasSweetheartTable
            ),
            guests: guests.map { g in
                GuestDTO(
                    id: g.id, name: g.name, firstName: g.firstName, lastName: g.lastName,
                    email: g.email, categories: g.categories, dietary: g.dietary, notes: g.notes,
                    rsvp: g.rsvp.rawValue, side: g.side.rawValue, vip: g.vip,
                    accessibility: g.accessibility, plusOne: g.plusOne, party: g.party,
                    display: g.display ?? g.displayName,
                    dietaryTags: g.dietaryTags, highChair: g.highChair, isChild: g.isChild,
                    groupIds: g.groupIds, isBride: g.isBride, isGroom: g.isGroom,
                    meal: g.meal.map { MealField($0) }, createdAt: g.guestCreatedAt
                )
            },
            tables: tables.map { t in
                TableDTO(
                    id: t.id, name: t.name, type: t.type.rawValue, seats: t.seats,
                    x: t.x, y: t.y, rotation: t.rotation, locked: t.locked, color: t.color,
                    width: t.width, height: t.height, diameter: t.diameter,
                    sweetShape: t.sweetShape, oneSide: t.oneSide
                )
            },
            rules: rules.map { r in
                RuleDTO(
                    id: r.id, type: r.type.rawValue, guests: r.guests, tableId: r.tableId,
                    weight: r.weight, hard: r.hard, enabled: r.enabled,
                    categoryId: r.categoryId, objectId: r.objectId, sideValue: r.sideValue,
                    sideA: r.sideA, sideB: r.sideB,
                    desc: r.desc, auto: r.auto, source: r.source, partyId: r.partyId, groupId: r.groupId
                )
            },
            objects: objects.map { o in
                ObjectDTO(
                    id: o.id, type: o.type, name: o.name, x: o.x, y: o.y,
                    width: o.width, height: o.height, rotation: o.rotation,
                    color: o.color, category: o.category, icon: o.icon, isObstacle: o.isObstacle
                )
            },
            categories: rawCategories,
            assignments: assignmentsMap.isEmpty ? nil : assignmentsMap,
            parties: rawParties,
            groups: rawGroups,
            floorPlanImage: rawFloorPlanImage,
            floorPlanOpacity: rawFloorPlanOpacity,
            seatOrders: rawSeatOrders,
            guestQR: rawGuestQR
        )
    }
}

// MARK: - Meal display

extension Guest {
    /// Short label + emoji icon for displaying meal choice in lists.
    /// Mirrors web's auto-derive logic at App.jsx:3421-3427 — keyword
    /// match against the meal text, fallback to a generic plate.
    /// Returns nil when the guest has no meal set.
    var mealDisplay: (short: String, icon: String)? {
        guard let raw = meal?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return nil
        }
        let m = raw.lowercased()
        if m.contains("beef") || m.contains("tenderloin")        { return ("Beef", "🥩") }
        if m.contains("salmon") || m.contains("prawn") || m.contains("fish") { return ("Salmon", "🐟") }
        if m.contains("chicken")                                  { return ("Chicken", "🍗") }
        if m.contains("mushroom") || m.contains("quinoa") || m.contains("vegan") || m.contains("vegetarian") {
            return ("Vegan", "🥗")
        }
        // Fallback: keep the first two words as the short label.
        let short = raw.split(separator: " ").prefix(2).joined(separator: " ")
        return (short.isEmpty ? raw : short, "🍽️")
    }
}

// MARK: - Category resolution

extension SeatingPlan {
    /// Returns a friendly display label for the guest's first usable
    /// category, or nil if none exist / none can be resolved.
    ///
    /// Iterates `guest.categories` in order. For each entry:
    ///   1. Try resolving as a category ID against `rawCategories` —
    ///      use the canonical `name` field if found.
    ///   2. If unresolved AND the raw value looks like a generated ID
    ///      (6+ lowercase alphanumeric chars), skip it. These are
    ///      orphaned references to deleted categories — leaking them
    ///      into the UI shows "5eido12nz" next to a guest's name.
    ///   3. Otherwise treat the raw value as a legacy plain-text
    ///      category like "Family" or "VIP" and use it as-is.
    func displayCategoryLabel(for guest: Guest) -> String? {
        for raw in guest.categories {
            if let resolved = canonicalCategoryName(forId: raw) {
                return resolved
            }
            if !Self.looksLikeGeneratedId(raw) {
                return raw
            }
        }
        return nil
    }

    /// Look up `id` in rawCategories and return the canonical `name` if
    /// the entry exists and has a non-empty name.
    func canonicalCategoryName(forId id: String) -> String? {
        guard let raw = rawCategories else { return nil }
        let entry = raw.first { ($0["id"]?.value as? String) == id }
        return (entry?["name"]?.value as? String).flatMap { $0.isEmpty ? nil : $0 }
    }

    /// Heuristic: short hashes like "5eido12nz" / "a5gb6pp2n" are 6+
    /// chars of lowercase alphanumerics with no spaces or capitals. Real
    /// category names ("Family", "Bride's side", "VIP") fail at least
    /// one of those checks.
    private static func looksLikeGeneratedId(_ s: String) -> Bool {
        guard s.count >= 6 else { return false }
        return s.allSatisfy { $0.isLowercase || $0.isNumber }
    }
}

// MARK: - Guest QR helpers

extension SeatingPlan {
    /// The token web mints on the `/api/guest` endpoint. Used to build the
    /// scannable URL `seatbee.app/g/<token>`. Nil when guest QR has never
    /// been enabled for this plan.
    var guestQRToken: String? {
        (rawGuestQR?.value as? [String: Any])?["linkToken"] as? String
    }

    /// Whether guests can currently access the plan via the QR. Web defaults
    /// to false until the user explicitly toggles on.
    var guestQREnabled: Bool {
        ((rawGuestQR?.value as? [String: Any])?["enabled"] as? Bool) ?? false
    }
}

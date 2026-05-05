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
    var createdAt: Date?
    var updatedAt: Date?
    var userId: String?
    var tier: String?

    // Raw passthrough: entities iOS doesn't model but must preserve on round-trip
    var rawCategories: [[String: AnyCodable]]?
    var rawParties: [[String: AnyCodable]]?
    var rawGroups: [[String: AnyCodable]]?
    var rawFloorPlanImage: AnyCodable?
    var rawFloorPlanOpacity: Double?
    var rawSeatOrders: [String: AnyCodable]?

    enum EventType: String, Codable, CaseIterable {
        case wedding
        case corporate
        case celebration
        case custom
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
                roomShape: nil,
                measurementUnit: nil,
                customRoomPoints: nil,
                roomFlipH: nil,
                roomFlipV: nil,
                roomZones: nil,
                hasSweetheartTable: nil
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
                    meal: g.meal, createdAt: g.guestCreatedAt
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
            seatOrders: rawSeatOrders
        )
    }
}

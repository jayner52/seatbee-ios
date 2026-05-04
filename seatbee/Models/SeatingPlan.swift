import Foundation

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

    enum EventType: String, Codable, CaseIterable {
        case wedding
        case corporate
        case celebration
        case custom
    }
}

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

struct SeatingRule: Identifiable, Codable {
    let id: String
    var type: RuleType
    var guests: [String] // guestIds
    var tableId: String?
    var weight: Int
    var hard: Bool
    var enabled: Bool
    // Web-parity fields (see PARITY.md) — present on web's Rule shape; iOS preserves them on round-trip
    var categoryId: String?     // for .categoryTogether
    var objectId: String?       // for .nearObject
    var sideValue: String?      // "bride" | "groom" for .sideTogether
    var desc: String?           // human-readable description from web
    var auto: Bool?             // auto-generated rule (from parties/onboarding/AI)
    var source: String?         // "party" | "group" | "ai" | "manual"
    var partyId: String?        // source party id for auto rules
    var groupId: String?        // source group id

    // Canonical rule types — rawValues match the web app's evaluator strings exactly
    // (see /Users/jayneingram/Desktop/Seating Plan App/src/App.jsx:4798 onwards).
    // `.unknown(raw)` preserves any future/unknown type from web on round-trip rather
    // than silently coercing it. PARITY.md anti-pattern: "Silent enum fallback on read".
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
            // Legacy iOS camelCase values — migrate to canonical on read
            case "seatTogether":      return .mustTogether
            case "keepApart":         return .mustNot
            case "assignTable":       return .mustTable
            case "seatNear":          return .nearTable
            default:
                print("[Seatbee] ⚠️ Unknown rule type: '\(raw)' — preserving raw on round-trip. See PARITY.md.")
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

struct RoomObject: Identifiable, Codable {
    let id: String
    var type: String
    var name: String
    var x: Double
    var y: Double
    var width: Double
    var height: Double
    var rotation: Double?
}

// MARK: - Reverse Mapping (Domain → DTO for saving to Supabase)

extension SeatingPlan {
    func toPlanData() -> PlanDataDTO {
        // Build assignments map: guestId -> AssignmentDTO
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
                roomShape: nil
            ),
            guests: guests.map { guest in
                GuestDTO(
                    id: guest.id,
                    name: guest.name,
                    firstName: guest.firstName,
                    lastName: guest.lastName,
                    email: guest.email,
                    categories: guest.categories,
                    dietary: guest.dietary,
                    notes: guest.notes,
                    rsvp: guest.rsvp.rawValue,
                    side: guest.side.rawValue,
                    vip: guest.vip,
                    accessibility: guest.accessibility,
                    plusOne: guest.plusOne,
                    party: guest.party,
                    display: guest.displayName
                )
            },
            tables: tables.map { table in
                TableDTO(
                    id: table.id,
                    name: table.name,
                    type: table.type.rawValue,
                    seats: table.seats,
                    x: table.x,
                    y: table.y,
                    rotation: table.rotation,
                    locked: table.locked,
                    color: table.color
                )
            },
            rules: rules.map { rule in
                RuleDTO(
                    id: rule.id,
                    type: rule.type.rawValue,
                    guests: rule.guests,
                    tableId: rule.tableId,
                    weight: rule.weight,
                    hard: rule.hard,
                    enabled: rule.enabled,
                    categoryId: rule.categoryId,
                    objectId: rule.objectId,
                    sideValue: rule.sideValue,
                    desc: rule.desc,
                    auto: rule.auto,
                    source: rule.source,
                    partyId: rule.partyId,
                    groupId: rule.groupId
                )
            },
            objects: objects.map { obj in
                ObjectDTO(
                    id: obj.id,
                    type: obj.type,
                    name: obj.name,
                    x: obj.x,
                    y: obj.y,
                    width: obj.width,
                    height: obj.height,
                    rotation: obj.rotation
                )
            },
            categories: nil,
            assignments: assignmentsMap.isEmpty ? nil : assignmentsMap,
            parties: nil
        )
    }
}

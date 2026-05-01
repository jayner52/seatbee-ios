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

    enum RuleType: String, Codable {
        case seatTogether
        case keepApart
        case assignTable
        case seatNear
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

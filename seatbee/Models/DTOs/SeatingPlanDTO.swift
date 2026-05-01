import Foundation

// DTOs matching Supabase database schema exactly
// The web app stores tables, guests, rules as JSONB columns within seating_plans

struct SeatingPlanDTO: Codable {
    let id: String
    let user_id: String?
    let name: String
    let event_date: String?
    let venue: String?
    let event_type: String?
    let tables: [TableDTO]?
    let guests: [GuestDTO]?
    let rules: [RuleDTO]?
    let objects: [ObjectDTO]?
    let room_width: Double?
    let room_height: Double?
    let tier: String?
    let created_at: String?
    let updated_at: String?
    let deleted_at: String?

    func toDomain() -> SeatingPlan {
        SeatingPlan(
            id: id,
            name: name,
            eventDate: event_date.flatMap { ISO8601DateFormatter().date(from: $0) },
            venue: venue,
            eventType: SeatingPlan.EventType(rawValue: event_type ?? "wedding") ?? .wedding,
            tables: (tables ?? []).map { $0.toDomain() },
            guests: (guests ?? []).map { $0.toDomain() },
            rules: (rules ?? []).map { $0.toDomain() },
            objects: (objects ?? []).map { $0.toDomain() },
            roomWidth: room_width,
            roomHeight: room_height,
            createdAt: created_at.flatMap { ISO8601DateFormatter().date(from: $0) },
            updatedAt: updated_at.flatMap { ISO8601DateFormatter().date(from: $0) },
            userId: user_id,
            tier: tier
        )
    }
}

struct TableDTO: Codable {
    let id: String
    let name: String?
    let type: String?
    let seats: Int?
    let x: Double?
    let y: Double?
    let rotation: Double?
    let assignments: [String: Int]?
    let locked: Bool?
    let color: String?

    func toDomain() -> SeatTable {
        SeatTable(
            id: id,
            name: name ?? "Table",
            type: SeatTable.TableType(rawValue: type ?? "round") ?? .round,
            seats: seats ?? 8,
            x: x ?? 0,
            y: y ?? 0,
            rotation: rotation,
            assignments: assignments ?? [:],
            locked: locked,
            color: color
        )
    }
}

struct GuestDTO: Codable {
    let id: String
    let name: String?
    let firstName: String?
    let lastName: String?
    let email: String?
    let categories: [String]?
    let dietary: String?
    let notes: String?
    let rsvp: String?
    let side: String?
    let vip: Bool?
    let accessibility: String?
    let plusOne: Bool?
    let party: String?

    func toDomain() -> Guest {
        Guest(
            id: id,
            name: name ?? "\(firstName ?? "") \(lastName ?? "")".trimmingCharacters(in: .whitespaces),
            firstName: firstName,
            lastName: lastName,
            email: email,
            categories: categories ?? [],
            dietary: dietary,
            notes: notes,
            rsvp: Guest.RSVPStatus(rawValue: rsvp ?? "unknown") ?? .unknown,
            side: Guest.GuestSide(rawValue: side ?? "none") ?? .none,
            vip: vip ?? false,
            accessibility: accessibility,
            plusOne: plusOne,
            party: party
        )
    }
}

struct RuleDTO: Codable {
    let id: String
    let type: String?
    let guests: [String]?
    let tableId: String?
    let weight: Int?
    let hard: Bool?
    let enabled: Bool?

    func toDomain() -> SeatingRule {
        SeatingRule(
            id: id,
            type: SeatingRule.RuleType(rawValue: type ?? "seatTogether") ?? .seatTogether,
            guests: guests ?? [],
            tableId: tableId,
            weight: weight ?? 50,
            hard: hard ?? false,
            enabled: enabled ?? true
        )
    }
}

struct ObjectDTO: Codable {
    let id: String
    let type: String?
    let name: String?
    let x: Double?
    let y: Double?
    let width: Double?
    let height: Double?
    let rotation: Double?

    func toDomain() -> RoomObject {
        RoomObject(
            id: id,
            type: type ?? "unknown",
            name: name ?? "Object",
            x: x ?? 0,
            y: y ?? 0,
            width: width ?? 100,
            height: height ?? 100,
            rotation: rotation
        )
    }
}

// AI API response/request DTOs
struct AIRequestBody: Codable {
    let action: String
    let systemPrompt: String
    let userMessage: String
    var model: String?
}

struct AIResponse: Codable {
    let success: Bool?
    let content: String?
    let error: String?
}

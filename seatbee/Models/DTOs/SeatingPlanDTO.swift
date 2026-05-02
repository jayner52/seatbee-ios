import Foundation

// The web app stores everything inside a single `data` JSONB column.
// Schema: seating_plans(id, user_id, name, data, event_date, event_type,
//         event_venue_name, seated_guest_count, created_at, updated_at, deleted_at)

struct SeatingPlanDTO: Codable {
    let id: String
    let user_id: String?
    let name: String
    let data: PlanDataDTO?
    let event_date: String?
    let event_type: String?
    let event_venue_name: String?
    let seated_guest_count: Int?
    let tier: String?
    let created_at: String?
    let updated_at: String?
    let deleted_at: String?

    func toDomain() -> SeatingPlan {
        let planData = data

        // Parse assignments from data.assignments (guestId -> {tableId, seatIndex})
        let assignmentMap = planData?.assignments ?? [:]

        // Build tables with their assignments embedded
        var domainTables = (planData?.tables ?? []).map { $0.toDomain() }
        for (guestId, assignment) in assignmentMap {
            if let tableIndex = domainTables.firstIndex(where: { $0.id == assignment.tableId }) {
                domainTables[tableIndex].assignments[guestId] = assignment.seatIndex ?? 0
            }
        }

        return SeatingPlan(
            id: id,
            name: name,
            eventDate: event_date.flatMap { parseDate($0) },
            venue: event_venue_name ?? planData?.event?.venue,
            eventType: SeatingPlan.EventType(rawValue: event_type ?? planData?.event?.eventType ?? "wedding") ?? .wedding,
            tables: domainTables,
            guests: (planData?.guests ?? []).map { $0.toDomain() },
            rules: (planData?.rules ?? []).map { $0.toDomain() },
            objects: (planData?.objects ?? []).map { $0.toDomain() },
            roomWidth: planData?.event?.roomWidth,
            roomHeight: planData?.event?.roomHeight,
            createdAt: created_at.flatMap { parseDate($0) },
            updatedAt: updated_at.flatMap { parseDate($0) },
            userId: user_id,
            tier: tier
        )
    }

    private func parseDate(_ string: String) -> Date? {
        // Try ISO8601 first
        let iso = ISO8601DateFormatter()
        if let date = iso.date(from: string) { return date }
        // Try with fractional seconds
        iso.formatOptions.insert(.withFractionalSeconds)
        if let date = iso.date(from: string) { return date }
        // Try simple date format (YYYY-MM-DD)
        let simple = DateFormatter()
        simple.dateFormat = "yyyy-MM-dd"
        return simple.date(from: string)
    }
}

// The `data` JSONB blob structure
struct PlanDataDTO: Codable {
    let event: EventDataDTO?
    let guests: [GuestDTO]?
    let tables: [TableDTO]?
    let rules: [RuleDTO]?
    let objects: [ObjectDTO]?
    let categories: [CategoryDTO]?
    let assignments: [String: AssignmentDTO]?
    let parties: [PartyDTO]?
}

struct EventDataDTO: Codable {
    let name: String?
    let date: String?
    let venue: String?
    let eventType: String?
    let roomWidth: Double?
    let roomHeight: Double?
    let roomShape: String?
}

struct AssignmentDTO: Codable {
    let tableId: String?
    let seatIndex: Int?

    // Handle both {tableId, seatIndex} and direct tableId string
    init(from decoder: Decoder) throws {
        if let container = try? decoder.container(keyedBy: CodingKeys.self) {
            tableId = try container.decodeIfPresent(String.self, forKey: .tableId)
            seatIndex = try container.decodeIfPresent(Int.self, forKey: .seatIndex)
        } else if let singleValue = try? decoder.singleValueContainer(),
                  let stringValue = try? singleValue.decode(String.self) {
            tableId = stringValue
            seatIndex = nil
        } else {
            tableId = nil
            seatIndex = nil
        }
    }

    private enum CodingKeys: String, CodingKey {
        case tableId, seatIndex
    }
}

struct CategoryDTO: Codable {
    let id: String?
    let name: String?
    let color: String?
}

struct PartyDTO: Codable {
    let id: String?
    let name: String?
    let members: [String]?
}

struct TableDTO: Codable {
    let id: String
    let name: String?
    let type: String?
    let seats: Int?
    let x: Double?
    let y: Double?
    let rotation: Double?
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
            assignments: [:], // Filled in by SeatingPlanDTO.toDomain()
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
    let display: String?

    func toDomain() -> Guest {
        let displayName = display ?? name ?? "\(firstName ?? "") \(lastName ?? "")".trimmingCharacters(in: .whitespaces)
        return Guest(
            id: id,
            name: displayName.isEmpty ? "Guest" : displayName,
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

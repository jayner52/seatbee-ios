import Foundation

// DTOs matching Supabase seating_plans schema exactly.
// See PARITY.md for the canonical field reference.
// RULE: every field the web persists must be present here, even if iOS doesn't render it.

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
        let d = data

        // Build assignments map: guestId -> {tableId, seatIndex}
        let assignmentMap = d?.assignments ?? [:]

        // Build tables with assignments embedded.
        //
        // Web persists assignments as flat strings ({guestId: "tableId"}, no
        // seat position) — see PR #10 + AssignmentDTO.encode. iOS used to
        // fall back to seatIndex=0 for those, which collided every web-
        // assigned guest at the same table onto seat 0; only the first one
        // was visible in the iOS seat list.
        //
        // Resolution: split into two passes per table. First, honour any
        // explicit seatIndex values that came from older iOS-shape data.
        // Then, fill the remaining (nil-seatIndex) guests into the next
        // free seat in guest-list order — so the iOS list mirrors the
        // order web shows.
        var domainTables = (d?.tables ?? []).map { $0.toDomain() }

        var entriesByTable: [String: [(guestId: String, seatIndex: Int?)]] = [:]
        for guest in (d?.guests ?? []) {
            guard let assignment = assignmentMap[guest.id],
                  let tableId = assignment.tableId, !tableId.isEmpty else { continue }
            entriesByTable[tableId, default: []].append((guest.id, assignment.seatIndex))
        }

        for (tableId, entries) in entriesByTable {
            guard let tableIndex = domainTables.firstIndex(where: { $0.id == tableId }) else { continue }
            var usedSeats = Set<Int>()
            for entry in entries {
                if let idx = entry.seatIndex {
                    domainTables[tableIndex].assignments[entry.guestId] = idx
                    usedSeats.insert(idx)
                }
            }
            var nextFree = 0
            for entry in entries where entry.seatIndex == nil {
                while usedSeats.contains(nextFree) { nextFree += 1 }
                domainTables[tableIndex].assignments[entry.guestId] = nextFree
                usedSeats.insert(nextFree)
                nextFree += 1
            }
        }

        return SeatingPlan(
            id: id,
            name: name,
            eventDate: event_date.flatMap { parseDate($0) },
            venue: event_venue_name ?? d?.event?.venue,
            eventType: SeatingPlan.EventType(rawValue: event_type ?? d?.event?.eventType ?? "wedding") ?? .wedding,
            tables: domainTables,
            guests: (d?.guests ?? []).map { $0.toDomain() },
            rules: (d?.rules ?? []).map { $0.toDomain() },
            objects: (d?.objects ?? []).map { $0.toDomain() },
            roomWidth: d?.event?.roomWidth,
            roomHeight: d?.event?.roomHeight,
            createdAt: created_at.flatMap { parseDate($0) },
            updatedAt: updated_at.flatMap { parseDate($0) },
            userId: user_id,
            tier: tier,
            // Raw passthrough — preserved unchanged on round-trip
            rawCategories: d?.categories,
            rawParties: d?.parties,
            rawGroups: d?.groups,
            rawFloorPlanImage: d?.floorPlanImage,
            rawFloorPlanOpacity: d?.floorPlanOpacity,
            rawSeatOrders: d?.seatOrders
        )
    }

    private func parseDate(_ string: String) -> Date? {
        let iso = ISO8601DateFormatter()
        if let date = iso.date(from: string) { return date }
        iso.formatOptions.insert(.withFractionalSeconds)
        if let date = iso.date(from: string) { return date }
        let simple = DateFormatter()
        simple.dateFormat = "yyyy-MM-dd"
        return simple.date(from: string)
    }
}

// MARK: - PlanDataDTO (the `data` JSONB blob)

struct PlanDataDTO: Codable {
    let event: EventDataDTO?
    let guests: [GuestDTO]?
    let tables: [TableDTO]?
    let rules: [RuleDTO]?
    let objects: [ObjectDTO]?
    let categories: [[String: AnyCodable]]?  // raw passthrough
    let assignments: [String: AssignmentDTO]?
    let parties: [[String: AnyCodable]]?     // raw passthrough
    let groups: [[String: AnyCodable]]?      // raw passthrough
    let floorPlanImage: AnyCodable?          // raw passthrough (can be string URL or null)
    let floorPlanOpacity: Double?
    let seatOrders: [String: AnyCodable]?    // raw passthrough
}

// MARK: - EventDataDTO

struct EventDataDTO: Codable {
    let name: String?
    let date: String?
    let venue: String?
    let eventType: String?
    let roomWidth: Double?
    let roomHeight: Double?
    let roomShape: String?
    // Web-parity passthrough
    let measurementUnit: String?
    let customRoomPoints: AnyCodable?
    let roomFlipH: Bool?
    let roomFlipV: Bool?
    let roomZones: AnyCodable?
    let hasSweetheartTable: Bool?
}

// MARK: - AssignmentDTO

struct AssignmentDTO: Codable {
    let tableId: String?
    let seatIndex: Int?

    init(tableId: String?, seatIndex: Int?) {
        self.tableId = tableId
        self.seatIndex = seatIndex
    }

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

    // Web stores assignments as a flat {guestId: "tableId"} string map.
    // Encode as a single string so iOS round-trip matches that shape and
    // web's `assignments[g.id] === tableId` comparison works.
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(tableId ?? "")
    }

    private enum CodingKeys: String, CodingKey {
        case tableId, seatIndex
    }
}

// MARK: - TableDTO

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
    // Web-parity fields
    let width: Double?
    let height: Double?
    let diameter: Double?
    let sweetShape: String?
    let oneSide: Bool?

    func toDomain() -> SeatTable {
        SeatTable(
            id: id,
            name: name ?? "Table",
            type: SeatTable.TableType(rawValue: type ?? "round") ?? .round,
            seats: seats ?? 8,
            x: x ?? 0,
            y: y ?? 0,
            rotation: rotation,
            assignments: [:], // filled by SeatingPlanDTO.toDomain()
            locked: locked,
            color: color,
            width: width,
            height: height,
            diameter: diameter,
            sweetShape: sweetShape,
            oneSide: oneSide
        )
    }
}

// MARK: - GuestDTO

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
    // Web-parity fields
    let dietaryTags: [String]?
    let highChair: Bool?
    let groupIds: [String]?
    let isBride: Bool?
    let isGroom: Bool?
    let meal: String?
    let createdAt: String?

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
            party: party,
            display: display,
            dietaryTags: dietaryTags,
            highChair: highChair,
            groupIds: groupIds,
            isBride: isBride,
            isGroom: isGroom,
            meal: meal,
            guestCreatedAt: createdAt
        )
    }
}

// MARK: - RuleDTO

struct RuleDTO: Codable {
    let id: String
    let type: String?
    let guests: [String]?
    let tableId: String?
    let weight: Int?
    let hard: Bool?
    let enabled: Bool?
    let categoryId: String?
    let objectId: String?
    let sideValue: String?
    let desc: String?
    let auto: Bool?
    let source: String?
    let partyId: String?
    let groupId: String?

    func toDomain() -> SeatingRule {
        SeatingRule(
            id: id,
            type: SeatingRule.RuleType.parse(type),
            guests: guests ?? [],
            tableId: tableId,
            weight: weight ?? 50,
            hard: hard ?? false,
            enabled: enabled ?? true,
            categoryId: categoryId,
            objectId: objectId,
            sideValue: sideValue,
            desc: desc,
            auto: auto,
            source: source,
            partyId: partyId,
            groupId: groupId
        )
    }
}

// MARK: - ObjectDTO

struct ObjectDTO: Codable {
    let id: String
    let type: String?
    let name: String?
    let x: Double?
    let y: Double?
    let width: Double?
    let height: Double?
    let rotation: Double?
    let color: String?
    let category: String?
    let icon: String?
    let isObstacle: Bool?

    func toDomain() -> RoomObject {
        RoomObject(
            id: id,
            type: type ?? "unknown",
            name: name ?? "Object",
            x: x ?? 0,
            y: y ?? 0,
            width: width ?? 100,
            height: height ?? 100,
            rotation: rotation,
            color: color,
            category: category,
            icon: icon,
            isObstacle: isObstacle
        )
    }
}

// MARK: - AI DTOs

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

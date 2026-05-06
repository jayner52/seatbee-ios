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
    // Pass expiry — top-level columns set by web's /api/passes redemption
    // flow. iOS reads but never writes these; Supabase PATCH preserves them
    // because savePlanData omits them from its payload.
    let event_pass_expires_at: String?
    let event_pass_purchased_at: String?
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
            roomShape: d?.event?.roomShape,
            measurementUnit: d?.event?.measurementUnit,
            customRoomPoints: RoomGeometryCoder.decodePoints(d?.event?.customRoomPoints),
            roomFlipH: d?.event?.roomFlipH,
            roomFlipV: d?.event?.roomFlipV,
            roomZones: RoomGeometryCoder.decodeZones(d?.event?.roomZones),
            hasSweetheartTable: d?.event?.hasSweetheartTable,
            coupleType: d?.event?.coupleType,
            createdAt: created_at.flatMap { parseDate($0) },
            updatedAt: updated_at.flatMap { parseDate($0) },
            userId: user_id,
            tier: tier,
            eventPassExpiresAt: event_pass_expires_at.flatMap { parseDate($0) },
            eventPassPurchasedAt: event_pass_purchased_at.flatMap { parseDate($0) },
            // Raw passthrough — preserved unchanged on round-trip
            rawCategories: d?.categories,
            rawParties: d?.parties,
            rawGroups: d?.groups,
            rawFloorPlanImage: d?.floorPlanImage,
            rawFloorPlanOpacity: d?.floorPlanOpacity,
            rawSeatOrders: d?.seatOrders,
            rawGuestQR: d?.guestQR
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
    let guestQR: AnyCodable?                 // raw passthrough — see SeatingPlan.guestQR* helpers
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
    let measurementUnit: String?
    // Stored as AnyCodable for lenient round-trip — any malformed legacy
    // entries decode without throwing. iOS converts to/from typed
    // [RoomPoint] / [RoomZone] in toDomain + toPlanData.
    let customRoomPoints: AnyCodable?
    let roomFlipH: Bool?
    let roomFlipV: Bool?
    let roomZones: AnyCodable?
    let hasSweetheartTable: Bool?
    let coupleType: String?
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
    let notes: String?

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
            oneSide: oneSide,
            notes: notes
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
    let isChild: Bool?
    let groupIds: [String]?
    let isBride: Bool?
    let isGroom: Bool?
    let meal: MealField?    // accepts string OR {short, icon, full} object
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
            isChild: isChild,
            groupIds: groupIds,
            isBride: isBride,
            isGroom: isGroom,
            meal: meal?.stringValue,
            guestCreatedAt: createdAt
        )
    }
}

// MARK: - MealField
//
// Web stores `meal` as either a plain string ("Beef") or an object
// ({short: "Beef", icon: "🥩", full: "Beef tenderloin"}). iOS used to
// declare `meal: String?` which would crash the whole guest decode
// when web sent an object. This wrapper accepts either shape on read,
// extracts the most informative string (full → short → null), and
// always writes back as a plain string. Web auto-derives the icon
// from text on its own read path (App.jsx:3421-3427), so writing as
// a string doesn't lose visible information.

struct MealField: Codable {
    let stringValue: String?

    init(_ str: String?) { self.stringValue = str }

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() {
            self.stringValue = nil
        } else if let s = try? c.decode(String.self) {
            self.stringValue = s
        } else if let dict = try? c.decode([String: AnyCodable].self) {
            // Object shape from web. Prefer `full` (more descriptive)
            // then fall back to `short`. Drop `icon` — iOS will
            // re-derive it for display via Guest.mealDisplay().
            self.stringValue = (dict["full"]?.value as? String)
                ?? (dict["short"]?.value as? String)
        } else {
            self.stringValue = nil
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        if let s = stringValue, !s.isEmpty {
            try c.encode(s)
        } else {
            try c.encodeNil()
        }
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
    let sideA: [String]?
    let sideB: [String]?
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
            sideA: sideA,
            sideB: sideB,
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

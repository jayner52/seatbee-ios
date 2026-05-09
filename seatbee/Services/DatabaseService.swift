import Foundation
import Supabase

final class DatabaseService {
    private var client: SupabaseClient { SupabaseManager.shared.client }

    // MARK: - Fetch Plans

    func fetchPlans() async throws -> [SeatingPlan] {
        let response: [SeatingPlanDTO] = try await client
            .from("seating_plans")
            .select("id, user_id, name, data, event_date, event_type, event_venue_name, seated_guest_count, tier, event_pass_expires_at, event_pass_purchased_at, created_at, updated_at, deleted_at")
            .is("deleted_at", value: nil as Bool?)
            .order("updated_at", ascending: false)
            .execute()
            .value

        let plans = response.map { $0.toDomain() }
        print("[Seatbee] Fetched \(plans.count) plans")
        for plan in plans {
            print("[Seatbee]   '\(plan.name)': \(plan.guests.count) guests, \(plan.tables.count) tables")
        }
        return plans
    }

    func fetchPlan(id: String) async throws -> SeatingPlan {
        let response: SeatingPlanDTO = try await client
            .from("seating_plans")
            .select("*")
            .eq("id", value: id)
            .single()
            .execute()
            .value

        return response.toDomain()
    }

    // MARK: - Create Plan

    func createPlan(name: String, eventType: String, eventDate: String?, venue: String?, guests: [GuestDTO]?, tables: [TableDTO]?) async throws -> SeatingPlan {
        let session = try await client.auth.session

        let planData = PlanDataDTO(
            event: EventDataDTO(name: name, date: eventDate, venue: venue, eventType: eventType, roomWidth: nil, roomHeight: nil, roomShape: nil, measurementUnit: nil, customRoomPoints: nil, roomFlipH: nil, roomFlipV: nil, roomZones: nil, hasSweetheartTable: nil, coupleType: nil),
            guests: guests,
            tables: tables,
            rules: nil,
            objects: nil,
            categories: nil,
            assignments: nil,
            parties: nil,
            groups: nil,
            floorPlanImage: nil,
            floorPlanOpacity: nil,
            seatOrders: nil,
            guestQR: nil,
            includeMaybes: nil
        )

        struct CreatePlanPayload: Codable {
            let name: String
            let event_type: String
            let user_id: String
            let data: PlanDataDTO
            let event_date: String?
            let event_venue_name: String?
            let seated_guest_count: Int
        }

        let payload = CreatePlanPayload(
            name: name,
            event_type: eventType,
            user_id: session.user.id.uuidString,
            data: planData,
            event_date: eventDate,
            event_venue_name: venue,
            seated_guest_count: guests?.count ?? 0
        )

        let response: SeatingPlanDTO = try await client
            .from("seating_plans")
            .insert(payload)
            .select()
            .single()
            .execute()
            .value

        print("[Seatbee] Created plan '\(name)' with id: \(response.id)")
        return response.toDomain()
    }

    // MARK: - Save Full Plan Data (write-back)

    func savePlanData(plan: SeatingPlan) async throws {
        // Demo plan is local-only — never persist to Supabase. Silently
        // return success so callers (autosave, undo/redo, drag-end) don't
        // throw; the user's edits stay in memory until app restart, when
        // SampleEventService re-loads the bundled state.
        if plan.isDemo { return }

        let planData = plan.toPlanData()

        struct SavePayload: Codable {
            let data: PlanDataDTO
            let name: String
            let updated_at: String
            let seated_guest_count: Int
            let event_venue_name: String?
            let event_date: String?
            let event_type: String?
        }

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"

        let payload = SavePayload(
            data: planData,
            name: plan.name,
            updated_at: ISO8601DateFormatter().string(from: Date()),
            seated_guest_count: plan.guests.count,
            event_venue_name: plan.venue,
            event_date: plan.eventDate.map { dateFormatter.string(from: $0) },
            event_type: plan.eventType.rawValue
        )

        try await client
            .from("seating_plans")
            .update(payload)
            .eq("id", value: plan.id)
            .execute()

        print("[Seatbee] Saved plan '\(plan.name)' — \(plan.guests.count) guests, \(plan.tables.count) tables")
    }

    // MARK: - Simple Updates

    func updatePlan(id: String, updates: [String: String]) async throws {
        if id == SampleEventService.samplePlanId { return }
        try await client
            .from("seating_plans")
            .update(updates)
            .eq("id", value: id)
            .execute()
    }

    func deletePlan(id: String) async throws {
        if id == SampleEventService.samplePlanId { return }
        let now = ISO8601DateFormatter().string(from: Date())
        try await client
            .from("seating_plans")
            .update(["deleted_at": now])
            .eq("id", value: id)
            .execute()
    }
}

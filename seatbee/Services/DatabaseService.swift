import Foundation
import Supabase

final class DatabaseService {
    private var client: SupabaseClient { SupabaseManager.shared.client }

    // MARK: - Seating Plans

    func fetchPlans() async throws -> [SeatingPlan] {
        let response: [SeatingPlanDTO] = try await client
            .from("seating_plans")
            .select("id, user_id, name, data, event_date, event_type, event_venue_name, seated_guest_count, tier, created_at, updated_at, deleted_at")
            .is("deleted_at", value: nil as Bool?)
            .order("updated_at", ascending: false)
            .execute()
            .value

        let plans = response.map { $0.toDomain() }
        print("[Seatbee] Fetched \(plans.count) plans")
        for plan in plans {
            print("[Seatbee] Plan '\(plan.name)': \(plan.guests.count) guests, \(plan.tables.count) tables")
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

    func createPlan(name: String, eventType: String, guests: [GuestDTO]?, tables: [TableDTO]?) async throws -> SeatingPlan {
        let session = try await client.auth.session

        let planData = PlanDataDTO(
            event: EventDataDTO(name: name, date: nil, venue: nil, eventType: eventType, roomWidth: nil, roomHeight: nil, roomShape: nil),
            guests: guests,
            tables: tables,
            rules: nil,
            objects: nil,
            categories: nil,
            assignments: nil,
            parties: nil
        )

        struct CreatePlanPayload: Codable {
            let name: String
            let event_type: String
            let user_id: String
            let data: PlanDataDTO
        }

        let payload = CreatePlanPayload(
            name: name,
            event_type: eventType,
            user_id: session.user.id.uuidString,
            data: planData
        )

        let response: SeatingPlanDTO = try await client
            .from("seating_plans")
            .insert(payload)
            .select()
            .single()
            .execute()
            .value

        return response.toDomain()
    }

    func updatePlan(id: String, updates: [String: String]) async throws {
        try await client
            .from("seating_plans")
            .update(updates)
            .eq("id", value: id)
            .execute()
    }

    func deletePlan(id: String) async throws {
        let now = ISO8601DateFormatter().string(from: Date())
        try await client
            .from("seating_plans")
            .update(["deleted_at": now])
            .eq("id", value: id)
            .execute()
    }
}

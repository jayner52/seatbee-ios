import Foundation
import Supabase

final class DatabaseService {
    private var client: SupabaseClient { SupabaseManager.shared.client }

    // MARK: - Seating Plans

    func fetchPlans() async throws -> [SeatingPlan] {
        let response: [SeatingPlanDTO] = try await client
            .from("seating_plans")
            .select()
            .is("deleted_at", value: nil as Bool?)
            .order("updated_at", ascending: false)
            .execute()
            .value

        return response.map { $0.toDomain() }
    }

    func fetchPlan(id: String) async throws -> SeatingPlan {
        let response: SeatingPlanDTO = try await client
            .from("seating_plans")
            .select()
            .eq("id", value: id)
            .single()
            .execute()
            .value

        return response.toDomain()
    }

    func createPlan(name: String, eventType: String, guests: [GuestDTO]?, tables: [TableDTO]?) async throws -> SeatingPlan {
        let session = try await client.auth.session

        struct CreatePlanPayload: Codable {
            let name: String
            let event_type: String
            let user_id: String
            let guests: [GuestDTO]?
            let tables: [TableDTO]?
        }

        let payload = CreatePlanPayload(
            name: name,
            event_type: eventType,
            user_id: session.user.id.uuidString,
            guests: guests,
            tables: tables
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

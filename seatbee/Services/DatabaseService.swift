import Foundation
import Supabase

final class DatabaseService {
    private var client: SupabaseClient { SupabaseManager.shared.client }

    // MARK: - Analytics

    private struct PaywallEventInsert: Encodable {
        struct EventData: Encodable {
            let platform: String
            let trigger: String
            let tier: String
        }
        let event_name: String
        let event_data: EventData
        let user_id: UUID?
    }

    /// Mirrors web's queueAnalyticsEvent('paywall_shown', …): one row in
    /// analytics_events per paywall view, with platform:"ios" so the admin
    /// dashboard can split web vs iOS hits. Fire-and-forget — analytics must
    /// never block or fail the paywall itself.
    func logPaywallShown(trigger: String, tier: String) async {
        let userId = try? await client.auth.session.user.id
        let payload = PaywallEventInsert(
            event_name: "paywall_shown",
            event_data: .init(platform: "ios", trigger: trigger, tier: tier),
            user_id: userId
        )
        _ = try? await client.from("analytics_events").insert(payload).execute()
    }

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
            includeMaybes: nil,
            rooms: nil,
            activeRoomId: nil
        )

        // Last-editor tracking. The web app reads these columns to show
        // "Edited by Emily, 2m ago" and to detect collaborator conflicts
        // (so a web user's pending edits aren't silently overwritten when
        // someone edits from iOS). Web added the same fields on every
        // INSERT/UPDATE in commit 44970cd. If iOS doesn't match, web users
        // will see stale editor info after iOS edits and may hit false
        // conflict modals. See PARITY.md.
        let lastEditedById = session.user.id.uuidString
        let lastEditedByEmail = session.user.email ?? ""
        var metaFullName: String? = nil
        if case .string(let n) = session.user.userMetadata["full_name"], !n.isEmpty { metaFullName = n }
        var metaName: String? = nil
        if case .string(let n) = session.user.userMetadata["name"], !n.isEmpty { metaName = n }
        let emailLocalPart = (session.user.email ?? "").split(separator: "@").first.map(String.init)
        let lastEditedByName = metaFullName ?? metaName ?? emailLocalPart ?? ""

        struct CreatePlanPayload: Codable {
            let name: String
            let event_type: String
            let user_id: String
            let data: PlanDataDTO
            let event_date: String?
            let event_venue_name: String?
            let seated_guest_count: Int
            let last_edited_by_id: String
            let last_edited_by_email: String
            let last_edited_by_name: String
        }

        let payload = CreatePlanPayload(
            name: name,
            event_type: eventType,
            user_id: session.user.id.uuidString,
            data: planData,
            event_date: eventDate,
            event_venue_name: venue,
            seated_guest_count: guests?.count ?? 0,
            last_edited_by_id: lastEditedById,
            last_edited_by_email: lastEditedByEmail,
            last_edited_by_name: lastEditedByName
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
        let session = try await client.auth.session

        // Last-editor tracking — see createPlan for context.
        let lastEditedById = session.user.id.uuidString
        let lastEditedByEmail = session.user.email ?? ""
        var metaFullName: String? = nil
        if case .string(let n) = session.user.userMetadata["full_name"], !n.isEmpty { metaFullName = n }
        var metaName: String? = nil
        if case .string(let n) = session.user.userMetadata["name"], !n.isEmpty { metaName = n }
        let emailLocalPart = (session.user.email ?? "").split(separator: "@").first.map(String.init)
        let lastEditedByName = metaFullName ?? metaName ?? emailLocalPart ?? ""

        struct SavePayload: Codable {
            let data: PlanDataDTO
            let name: String
            let updated_at: String
            let seated_guest_count: Int
            let event_venue_name: String?
            let event_date: String?
            let event_type: String?
            let last_edited_by_id: String
            let last_edited_by_email: String
            let last_edited_by_name: String
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
            event_type: plan.eventType.rawValue,
            last_edited_by_id: lastEditedById,
            last_edited_by_email: lastEditedByEmail,
            last_edited_by_name: lastEditedByName
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

    // MARK: - User Subscription
    //
    // Cross-app shared shape (PARITY.md). Web's Stripe webhook (or our
    // /api/apple-iap handler) writes these columns to `profiles`. iOS
    // reads but never writes — same contract as legacy pass columns.
    //
    // Defensive: if the backend hasn't yet shipped the subscription
    // columns (Phase 1 of the migration), the select fails or returns
    // nulls. We catch and return nil so `AppState.activePlanTier` can
    // fall back to the legacy pass chain without surfacing an error.

    func fetchUserSubscription() async throws -> UserSubscription? {
        let session = try await client.auth.session
        let userId = session.user.id.uuidString

        // Timestamps decoded as String (mirrors SeatingPlanDTO pattern) so
        // we don't depend on a particular JSONDecoder dateDecodingStrategy.
        struct Row: Decodable {
            let subscription_status: String?
            let subscription_renews_at: String?
            let subscription_provider: String?
            let subscription_id: String?
        }

        do {
            let row: Row = try await client
                .from("profiles")
                .select("subscription_status, subscription_renews_at, subscription_provider, subscription_id")
                .eq("id", value: userId)
                .single()
                .execute()
                .value

            // Backend has the columns but they're null → no subscription
            // on file. Resolution chain falls through to legacy.
            guard let rawStatus = row.subscription_status else {
                return nil
            }

            return UserSubscription(
                status: SubscriptionStatus.from(rawStatus),
                renewsAt: row.subscription_renews_at.flatMap(Self.parseISODate),
                provider: SubscriptionProvider.from(row.subscription_provider),
                subscriptionId: row.subscription_id
            )
        } catch {
            // Most likely cause: web hasn't shipped Phase 1 yet, so the
            // columns don't exist. Quiet fallthrough — the legacy pass
            // chain still works.
            print("[Seatbee] fetchUserSubscription: \(error.localizedDescription) — falling back to legacy pass chain")
            return nil
        }
    }

    private static func parseISODate(_ string: String) -> Date? {
        let iso = ISO8601DateFormatter()
        if let date = iso.date(from: string) { return date }
        iso.formatOptions.insert(.withFractionalSeconds)
        return iso.date(from: string)
    }
}

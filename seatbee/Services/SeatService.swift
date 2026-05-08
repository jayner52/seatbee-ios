import Foundation

// SeatService — calls the web's /api/seat endpoint, which wraps the same
// `generateSeating()` function the web client uses (src/lib/solve.js).
// This guarantees iOS and web produce identical assignments + seat orders
// for identical inputs. Do NOT port the algorithm to Swift — drift is
// inevitable. The endpoint is the single source of truth.

final class SeatService {
    private let baseURL = "https://www.seatbee.app/api/seat"

    enum SeatError: LocalizedError {
        case unauthorized
        case noPlan
        case noTablesOrGuests
        case server(String)
        case network(Error)

        var errorDescription: String? {
            switch self {
            case .unauthorized:        return "Please sign in to generate seating."
            case .noPlan:              return "No active plan."
            case .noTablesOrGuests:    return "Add at least one table and one guest before generating."
            case .server(let m):       return m
            case .network(let e):      return e.localizedDescription
            }
        }
    }

    /// Result returned by the /api/seat endpoint, mirroring
    /// `generateSeating()`'s return shape in src/lib/solve.js.
    struct GenerateResult: Decodable {
        let assignments: [String: String]              // guestId → tableId
        let seatOrders: [String: [String?]]            // tableId → seatMap[]
        let score: Int?
        let fallback: Bool?
        let scorecard: Scorecard?

        struct Scorecard: Decodable {
            let overallPercent: Int
            let overallLabel: String          // "Excellent" | "Great" | …
            let totalRules: Int
            let totalSatisfied: Int
            let hardConstraints: RuleBucket
            let softPreferences: RuleBucket
            // Server's `scorecard.suggestions` array — when solve()
            // throws, the first entry is "Solver error: <message>",
            // which is the only place the actual exception text is
            // exposed. Plumb it so the AI Generate screen can surface
            // it instead of a generic "Error" label.
            let suggestions: [String]

            init(from decoder: Decoder) throws {
                let c = try decoder.container(keyedBy: CodingKeys.self)
                overallPercent  = (try? c.decode(Int.self, forKey: .overallPercent)) ?? Int((try? c.decode(Double.self, forKey: .overallPercent)) ?? 0)
                overallLabel    = (try? c.decode(String.self, forKey: .overallLabel)) ?? ""
                totalRules      = (try? c.decode(Int.self, forKey: .totalRules)) ?? 0
                totalSatisfied  = (try? c.decode(Int.self, forKey: .totalSatisfied)) ?? 0
                hardConstraints = (try? c.decode(RuleBucket.self, forKey: .hardConstraints)) ?? .empty
                softPreferences = (try? c.decode(RuleBucket.self, forKey: .softPreferences)) ?? .empty
                suggestions     = (try? c.decode([String].self, forKey: .suggestions)) ?? []
            }

            enum CodingKeys: String, CodingKey {
                case overallPercent, overallLabel, totalRules, totalSatisfied
                case hardConstraints, softPreferences, suggestions
            }
        }

        struct RuleBucket: Decodable {
            let total: Int
            let satisfied: Int
            let partial: Int
            let violated: Int
            let rules: [RuleEntry]

            static let empty = RuleBucket(total: 0, satisfied: 0, partial: 0, violated: 0, rules: [])

            init(total: Int, satisfied: Int, partial: Int, violated: Int, rules: [RuleEntry]) {
                self.total = total; self.satisfied = satisfied
                self.partial = partial; self.violated = violated; self.rules = rules
            }

            init(from decoder: Decoder) throws {
                let c = try decoder.container(keyedBy: CodingKeys.self)
                total = (try? c.decode(Int.self, forKey: .total)) ?? 0
                satisfied = (try? c.decode(Int.self, forKey: .satisfied)) ?? 0
                partial = (try? c.decode(Int.self, forKey: .partial)) ?? 0
                violated = (try? c.decode(Int.self, forKey: .violated)) ?? 0
                rules = (try? c.decode([RuleEntry].self, forKey: .rules)) ?? []
            }

            enum CodingKeys: String, CodingKey { case total, satisfied, partial, violated, rules }
        }

        struct RuleEntry: Decodable, Identifiable, Hashable {
            let id = UUID()
            let status: String          // "satisfied" | "violated" | "partial" | "neutral"
            let description: String
            let details: String?
            let partial: String?        // e.g. "4/4 seated"

            init(from decoder: Decoder) throws {
                let c = try decoder.container(keyedBy: CodingKeys.self)
                status      = (try? c.decode(String.self, forKey: .status)) ?? "neutral"
                description = (try? c.decode(String.self, forKey: .description)) ?? ""
                details     = try? c.decode(String.self, forKey: .details)
                partial     = try? c.decode(String.self, forKey: .partial)
            }

            enum CodingKeys: String, CodingKey { case status, description, details, partial }
        }

        enum CodingKeys: String, CodingKey {
            case assignments, seatOrders, score, fallback, scorecard
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            assignments = (try? c.decode([String: String].self, forKey: .assignments)) ?? [:]
            seatOrders  = (try? c.decode([String: [String?]].self, forKey: .seatOrders)) ?? [:]
            // score may come back as Int or Double depending on the
            // path solve() took (rounded vs computed). Accept either.
            if let i = try? c.decode(Int.self, forKey: .score) {
                score = i
            } else if let d = try? c.decode(Double.self, forKey: .score) {
                score = Int(d.rounded())
            } else {
                score = nil
            }
            fallback = try? c.decode(Bool.self, forKey: .fallback)
            scorecard = try? c.decode(Scorecard.self, forKey: .scorecard)
        }
    }

    /// Run server-side seating for the given plan. Honours existing locked
    /// tables: their existing assignments are passed in `existingAssignments`
    /// so the solver preserves them.
    func generateSeating(plan: SeatingPlan, seed: Int = Int.random(in: 1...999_999)) async throws -> GenerateResult {
        guard !plan.tables.isEmpty, !plan.guests.isEmpty else {
            throw SeatError.noTablesOrGuests
        }
        guard let url = URL(string: baseURL) else { throw SeatError.server("Invalid URL") }

        guard let token = await AuthService().accessToken else { throw SeatError.unauthorized }

        // Build request body. The shape matches what /api/seat (and
        // generateSeating in src/lib/solve.js) expects: top-level arrays
        // for tables/guests/rules/categories/parties/groups/objects, plus
        // existingAssignments + seed. We reuse PlanDataDTO so the field
        // shapes match what web persists to Supabase exactly.
        let dto = plan.toPlanData()
        let dtoData = try JSONEncoder().encode(dto)
        guard let dtoDict = try JSONSerialization.jsonObject(with: dtoData) as? [String: Any] else {
            throw SeatError.server("Could not serialize plan data")
        }

        // existingAssignments: flat {guestId: tableId} — derived from the
        // current per-table assignments on the plan (already preserved
        // through the DTO as `assignments[guestId].tableId`).
        var existingAssignments: [String: String] = [:]
        for table in plan.tables {
            for (guestId, _) in table.assignments {
                existingAssignments[guestId] = table.id
            }
        }

        // Respect includeMaybes (web parity, App.jsx:13092). solve.js
        // already drops rsvp == "no" guests internally, but pending/
        // unknown only get excluded when includeMaybes == false. Filter
        // the guest payload here so the server sees the same set of
        // attendees web would.
        let includeMaybes = plan.includeMaybes ?? true
        let allGuests = (dtoDict["guests"] as? [[String: Any]]) ?? []
        let filteredGuests: [[String: Any]] = includeMaybes
            ? allGuests
            : allGuests.filter { (($0["rsvp"] as? String) ?? "") == "yes" }

        var body: [String: Any] = [
            "tables":              dtoDict["tables"] ?? [],
            "guests":              filteredGuests,
            "rules":               dtoDict["rules"] ?? [],
            "categories":          dtoDict["categories"] ?? [],
            "parties":             dtoDict["parties"] ?? [],
            "groups":              dtoDict["groups"] ?? [],
            "objects":             dtoDict["objects"] ?? [],
            "existingAssignments": existingAssignments,
            "seed":                seed,
        ]
        // generateSeating expects the parties param as `units` (web
        // history — they're conceptually the same). Map both keys so the
        // server is happy.
        body["units"] = body["parties"]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 60   // solver can take 5–20s on large plans
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw SeatError.network(error)
        }

        guard let http = response as? HTTPURLResponse else { throw SeatError.server("Invalid response") }
        switch http.statusCode {
        case 200:
            do {
                return try JSONDecoder().decode(GenerateResult.self, from: data)
            } catch {
                throw SeatError.server("Could not parse response: \(error.localizedDescription)")
            }
        case 401:
            throw SeatError.unauthorized
        default:
            let msg = (try? JSONDecoder().decode(ErrorBody.self, from: data))?.error ?? "Server error (\(http.statusCode))"
            throw SeatError.server(msg)
        }
    }

    private struct ErrorBody: Decodable {
        let error: String?
    }
}

// MARK: - Plan mutation

extension SeatingPlan {
    /// Apply a /api/seat result to this plan in place. Locked tables are
    /// preserved (the server preserved them via existingAssignments);
    /// every UNLOCKED table is wiped first and then rebuilt from the
    /// returned seatOrders.
    ///
    /// Why the up-front wipe: the server only includes tables it
    /// actually placed guests at in `seatOrders`. So if a regenerate
    /// moves a guest from one table (e.g. Head Table) to another (e.g.
    /// Sweetheart), the destination shows up in seatOrders but the
    /// source doesn't — and without an explicit wipe the old guest
    /// would linger at the source, producing the "guest seated at two
    /// tables at once" bug. Web doesn't hit this because it stores
    /// assignments as a flat guest→table map at state level and
    /// replaces it wholesale; iOS stores them per-table so we have to
    /// reset the per-table dictionaries explicitly.
    mutating func applyGeneratedSeating(_ result: SeatService.GenerateResult) {
        for tIdx in tables.indices where tables[tIdx].locked != true {
            tables[tIdx].assignments.removeAll()
        }
        for tIdx in tables.indices {
            if tables[tIdx].locked == true { continue }
            let tableId = tables[tIdx].id
            guard let seatMap = result.seatOrders[tableId] else { continue }
            for (seatIndex, guestId) in seatMap.enumerated() {
                if let gid = guestId, !gid.isEmpty {
                    tables[tIdx].assignments[gid] = seatIndex
                }
            }
        }
    }

    /// Clear assignments on every UNLOCKED table. Mirrors web's
    /// "Clear Unlocked Tables" action.
    mutating func clearUnlockedTableAssignments() {
        for tIdx in tables.indices where tables[tIdx].locked != true {
            tables[tIdx].assignments.removeAll()
        }
    }

    /// Clear ALL assignments, including locked tables. Mirrors web's
    /// "Clear All Assignments" action.
    mutating func clearAllAssignments() {
        for tIdx in tables.indices {
            tables[tIdx].assignments.removeAll()
        }
    }
}

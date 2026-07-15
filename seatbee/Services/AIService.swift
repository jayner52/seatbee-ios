import Foundation

final class AIService {
    private let baseURL = AppConfig.aiAPIBaseURL

    enum AIAction: String {
        case parseGuestList
        case getSeatingSuggestions
        case parseFloorPlan
        case detectConflicts
        case classifyTags
        case analyzeRulesPreFlight
        case parseRules
    }

    struct SeatingSuggestion: Codable {
        let guestId: String
        let tableId: String
        let reason: String?
    }

    struct SeatingResult: Codable {
        let suggestions: [SeatingSuggestion]
        let warnings: [String]
        let score: Int
    }

    struct ConflictResult: Codable {
        let conflicts: [Conflict]
        let score: Int
        let summary: String

        struct Conflict: Codable {
            let type: String
            let guests: [String]?
            let message: String
            let suggestion: String?
        }
    }

    // MARK: - Core API Call

    func call(action: AIAction, systemPrompt: String, userMessage: String) async throws -> String {
        guard let url = URL(string: baseURL) else {
            throw AIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Get bearer token
        if let token = await AuthService().accessToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let body = AIRequestBody(action: action.rawValue, systemPrompt: systemPrompt, userMessage: userMessage)
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIError.invalidResponse
        }

        let aiResponse = try JSONDecoder().decode(AIResponse.self, from: data)

        switch httpResponse.statusCode {
        case 200:
            guard let content = aiResponse.content else {
                throw AIError.emptyResponse
            }
            return content
        case 401:
            throw AIError.unauthorized
        case 403:
            throw AIError.tierRestricted
        case 429:
            throw AIError.rateLimited
        default:
            throw AIError.serverError(aiResponse.error ?? "Unknown error")
        }
    }

    // MARK: - Typed API Methods

    func parseGuestList(text: String) async throws -> [Guest] {
        let systemPrompt = """
        You are a helpful assistant that parses wedding guest lists.
        Extract guest information and return it as a JSON array.
        Each guest should have: id (random string), name, dietary (if mentioned), notes (if any), categories (array like ["family", "friends", "work"]), side ("bride", "groom", or "none" — extract from context like "bride's side", "groom's family"), vip (boolean), plusOne (boolean if "+1" or "plus one" mentioned).
        If someone is mentioned as a couple or family, create separate entries but note the relationship.
        Return ONLY valid JSON array, no explanation.
        """

        let result = try await call(
            action: .parseGuestList,
            systemPrompt: systemPrompt,
            userMessage: "Parse this guest list:\n\n\(text)"
        )

        // Parse JSON array from response
        guard let data = result.data(using: .utf8) else {
            throw AIError.parseError
        }

        let parsed = try JSONDecoder().decode([GuestDTO].self, from: data)
        return parsed.map { $0.toDomain() }
    }

    func getSeatingSuggestions(guests: [Guest], tables: [SeatTable], rules: [SeatingRule]) async throws -> SeatingResult {
        let systemPrompt = """
        You are an expert event planner specializing in seating arrangements.
        Analyze the guests, tables, rules, and current assignments to suggest optimal seating.
        Consider: family groups, relationships, VIPs, tags/categories, and any explicit rules.
        Return a JSON object with:
        - suggestions: array of {guestId, tableId, reason}
        - warnings: array of potential issues
        - score: 1-100 rating of current arrangement
        """

        struct SeatingContext: Codable {
            let guests: [Guest]
            let tables: [SeatTable]
            let rules: [SeatingRule]
        }

        let context = SeatingContext(guests: guests, tables: tables, rules: rules)
        let contextData = try JSONEncoder().encode(context)
        let contextString = String(data: contextData, encoding: .utf8) ?? "{}"

        let resultString = try await call(
            action: .getSeatingSuggestions,
            systemPrompt: systemPrompt,
            userMessage: "Analyze this seating arrangement:\n\n\(contextString)"
        )

        guard let responseData = resultString.data(using: String.Encoding.utf8) else {
            throw AIError.parseError
        }

        return try JSONDecoder().decode(SeatingResult.self, from: responseData)
    }

    // MARK: - Conflict Detection

    /// Mirrors src/lib/ai.js:detectConflicts so the iOS AI Insight
    /// panel ends up with the same narrative web shows. Web parity
    /// notes:
    ///   - context is `{ guests, assignments, customContext }` where
    ///     assignments maps guestId → table NAME (not id) so the
    ///     model can say "Table 5" instead of a uuid
    ///   - rules are stringified into customContext so the model can
    ///     reason about which rules are violated
    ///   - prompts come straight from web for behavioural identity
    func detectConflicts(plan: SeatingPlan) async throws -> ConflictResult {
        // Voice rules + JSON shape mirror web's detectConflicts in
        // src/lib/ai.js — both apps hit the same /api/ai endpoint
        // with the same systemPrompt for behavioural identity.
        let systemPrompt = """
        You are writing a short, friendly seating summary for the event host. Tone is warm and celebratory — like a thoughtful friend looking at their plan.

        Lead with what's working. Always start with at least one specific positive (\"Sweetheart table is beautifully placed for the couple\", \"Most family groups are seated together\", \"All keep-apart preferences are honoured\"). Then, only if there are real concerns, mention the most important one in a gentle, helpful tone — never alarmist.

        Voice rules (strict):
        - Write for a real person, not a developer.
        - NEVER quote, paraphrase, or include any backend identifier with underscores or camelCase. Examples to NEVER write: \"must_together\", \"must_not\", \"prefer_together\", \"near_object\", \"categoryTogether\". Just describe what the rule means in plain words.
        - Refer to rules conversationally: \"must-sit-together rules\", \"keep-apart preferences\", \"couples seated together\", \"assigned tables\", etc. Avoid quoting rule terminology even informally.
        - Refer to guests by first name, not id.
        - 2-3 sentences total. Compliment first, soften critique, end with a constructive note when possible.

        If you have nothing meaningful to flag, write a fully positive summary — that's a valid result.

        Return a JSON object with:
        - conflicts: array of conflicts, each with type (\"critical\" | \"warning\" | \"suggestion\"), guests (array of guest names — never ids), message (plain English, no backend identifiers), suggestion (how to fix)
        - score: 1-100 rating of overall arrangement quality
        - summary: 2-3 sentence host-friendly summary following the voice rules above
        """

        // Build guestId → tableName map (web App.jsx:13055)
        var tableNameById: [String: String] = [:]
        for t in plan.tables { tableNameById[t.id] = t.name }
        var namedAssignments: [String: String] = [:]
        for t in plan.tables {
            let tableName = tableNameById[t.id] ?? t.id
            for guestId in t.assignments.keys {
                namedAssignments[guestId] = tableName
            }
        }

        // Declined guests should be invisible to the AI — drop them
        // from the guests payload AND scrub their IDs out of every
        // rule.guests / sideA / sideB. Mirrors src/lib/ai.js
        // humaniseRules + cleansedGuests behaviour.
        let declinedIds = Set(plan.guests.filter { $0.rsvp == .no }.map(\.id))
        let attendingGuests = plan.guests.filter { $0.rsvp != .no }

        let guestPayload: [[String: Any]] = attendingGuests.map { g in
            [
                "id": g.id,
                "name": g.name,
                "rsvp": g.rsvp.rawValue,
                "side": g.side.rawValue,
                "vip": g.vip,
                "categories": g.categories,
                "dietary": g.dietary ?? "",
                "dietaryTags": g.dietaryTags ?? [],
                "isChild": g.isChild ?? false,
            ]
        }

        // Plain-English rule kinds — model never sees raw `type`,
        // matching web's RULE_TYPE_PLAIN_LANGUAGE table.
        let kindByType: [String: String] = [
            "must_together":     "must sit together rule",
            "must_not":          "keep-apart rule",
            "prefer_together":   "should sit together rule",
            "must_table":        "assigned-table rule",
            "near_object":       "near venue element rule",
            "near_table":        "near another table rule",
            "seat_adjacent":     "sit-next-to rule",
            "category_together": "category-stays-together rule",
            "side_together":     "side-stays-together rule",
        ]

        // Per-rule-type minimum membership for "rule still meaningful".
        // A must_together with one survivor isn't a rule — it's a
        // solo guest the AI would interpret as "needs a partner",
        // which is exactly the false-positive Jayne hit ("Layla,
        // your partner declined" — there IS no rule anymore).
        let minGuestsByType: [String: Int] = [
            "must_together":   2,
            "prefer_together": 2,
            "must_not":        2,
            "seat_adjacent":   2,
            "must_table":      1,
            "near_table":      1,
            "near_object":     1,
        ]

        let rulesPayload: [[String: Any]] = plan.rules
            .filter { $0.enabled }
            .compactMap { r -> [String: Any]? in
                let scrubbedGuests = r.guests.filter { !declinedIds.contains($0) }
                let scrubbedSideA  = (r.sideA ?? []).filter { !declinedIds.contains($0) }
                let scrubbedSideB  = (r.sideB ?? []).filter { !declinedIds.contains($0) }
                let minRequired = minGuestsByType[r.type.rawValue] ?? 0
                let hasGuests = scrubbedGuests.count >= max(minRequired, 1)
                let hasSides = !scrubbedSideA.isEmpty || !scrubbedSideB.isEmpty
                let isCategoryRule = r.type.rawValue == "category_together"
                // Drop rules whose surviving membership falls below the
                // type's minimum — model never sees them, never invents
                // commentary about them.
                if !hasGuests && !hasSides && !isCategoryRule {
                    return nil
                }
                let kind = kindByType[r.type.rawValue]
                    ?? r.type.rawValue.replacingOccurrences(of: "_", with: " ") + " rule"
                var entry: [String: Any] = [
                    "id": r.id,
                    "kind": kind,
                    "guests": scrubbedGuests,
                    "tableId": r.tableId ?? "",
                    "weight": r.weight,
                    "hard": r.hard,
                    "desc": r.desc ?? "",
                ]
                if !scrubbedSideA.isEmpty { entry["sideA"] = scrubbedSideA }
                if !scrubbedSideB.isEmpty { entry["sideB"] = scrubbedSideB }
                return entry
            }
        let context: [String: Any] = [
            "guests": guestPayload,
            "assignments": namedAssignments,
            "customContext": (try? String(data: JSONSerialization.data(withJSONObject: rulesPayload), encoding: .utf8)) ?? "[]",
        ]
        let contextData = try JSONSerialization.data(withJSONObject: context, options: [.prettyPrinted])
        let contextString = String(data: contextData, encoding: .utf8) ?? "{}"

        let resultString = try await call(
            action: .detectConflicts,
            systemPrompt: systemPrompt,
            userMessage: "Check for conflicts:\n\n\(contextString)"
        )

        // Web also handles the case where the model wraps JSON in
        // prose. Strip to the first {...} block before decoding.
        guard let responseData = resultString.data(using: .utf8) else {
            throw AIError.parseError
        }
        if let direct = try? JSONDecoder().decode(ConflictResult.self, from: responseData) {
            return direct
        }
        if let match = resultString.range(
            of: "\\{[\\s\\S]*\\}",
            options: .regularExpression
        ) {
            let inner = String(resultString[match])
            if let innerData = inner.data(using: .utf8),
               let parsed = try? JSONDecoder().decode(ConflictResult.self, from: innerData) {
                return parsed
            }
        }
        throw AIError.parseError
    }

    // MARK: - Tag Classification

    func classifyTags(tagNames: [String]) async throws -> [String: TagClassification] {
        let systemPrompt = """
        You are classifying tags for a wedding seating app.
        For each tag, determine its TYPE and AFFINITY WEIGHT (0-100) for seating decisions.
        CATEGORIES: administrative (0), family (85), weddingParty (95), eventAttendance (65), organization (65), social (40), kids (65), vip (40), unknown (40).
        Return ONLY valid JSON object: {"tagName": {"type": "category", "weight": 0-100, "reason": "brief explanation"}, ...}
        """

        let resultString = try await call(
            action: .classifyTags,
            systemPrompt: systemPrompt,
            userMessage: "Classify these tags for seating affinity:\n\n\(tagNames.joined(separator: ", "))"
        )

        guard let responseData = resultString.data(using: String.Encoding.utf8) else {
            throw AIError.parseError
        }

        return try JSONDecoder().decode([String: TagClassification].self, from: responseData)
    }

    struct TagClassification: Codable {
        let type: String
        let weight: Int
        let reason: String?
    }

    // MARK: - Errors

    // MARK: - Natural-Language Rules (web parity)
    //
    // Mirrors web parseRulesFromText (src/lib/ai.js:1404) + validateProposed
    // (src/App.jsx:13679). The system prompt is copied VERBATIM from web for
    // behavioural identity — if the web prompt changes, change it here too
    // (PARITY.md notes this pairing). Rules produced here persist to the
    // shared seating_plans.data JSONB, so every field value must match what
    // web writes.

    /// {id,name} lists sent to the model — identical to web's context arg.
    struct NLRulesContext {
        struct IdName: Encodable { let id: String; let name: String }
        var guests: [IdName]
        var tables: [IdName]
        var objects: [IdName]
        var categories: [IdName]
    }

    /// Raw rule shape as the model returns it. Everything optional — the
    /// model may omit fields; validation decides what survives.
    struct ProposedRuleDTO: Decodable {
        let type: String?
        let guests: [String]?
        let sideA: [String]?
        let sideB: [String]?
        let tableId: String?
        let objectId: String?
        let categoryId: String?
        let hard: Bool?
        let weight: Int?
        let desc: String?

        enum CodingKeys: String, CodingKey {
            case type, guests, sideA, sideB, tableId, objectId, categoryId, hard, weight, desc
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            type = try? c.decode(String.self, forKey: .type)
            guests = try? c.decode([String].self, forKey: .guests)
            sideA = try? c.decode([String].self, forKey: .sideA)
            sideB = try? c.decode([String].self, forKey: .sideB)
            tableId = try? c.decode(String.self, forKey: .tableId)
            objectId = try? c.decode(String.self, forKey: .objectId)
            categoryId = try? c.decode(String.self, forKey: .categoryId)
            hard = try? c.decode(Bool.self, forKey: .hard)
            // Weight tolerant: Int → Double → numeric String (models vary).
            if let i = try? c.decode(Int.self, forKey: .weight) { weight = i }
            else if let d = try? c.decode(Double.self, forKey: .weight) { weight = Int(d.rounded()) }
            else if let str = try? c.decode(String.self, forKey: .weight), let i = Int(str) { weight = i }
            else { weight = nil }
            desc = try? c.decode(String.self, forKey: .desc)
        }
    }

    struct ParsedRulesResult {
        let rules: [ProposedRuleDTO]
        let skipped: [String]
    }

    private struct NLRulesEnvelope: Decodable {
        let rules: [ProposedRuleDTO]?
        let skipped: [LossyString]?
        /// Web filters skipped to strings only; mirror by dropping non-strings.
        struct LossyString: Decodable {
            let value: String?
            init(from decoder: Decoder) throws {
                let c = try decoder.singleValueContainer()
                value = try? c.decode(String.self)
            }
        }
    }

    func parseRulesFromText(_ text: String, context: NLRulesContext) async throws -> ParsedRulesResult {
        func js<T: Encodable>(_ v: T) -> String {
            (try? JSONEncoder().encode(v)).flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
        }
        // Prompt text below is verbatim from web src/lib/ai.js:1404.
        let systemPrompt = #"""
You convert a wedding host's plain-English seating wishes into structured seating RULES.
You are given the guests, tables, venue elements, and categories with their IDs. Output ONLY valid JSON — an object of the form {"rules": [...], "skipped": [...]}. No prose, no markdown fences. "rules" is the array of rule objects you created. "skipped" is an array of short strings, ONE FOR EACH wish you could NOT turn into a rule (e.g. a name that isn't in the guest list), each briefly saying why — e.g. "joe at table 3 — no guest named 'Joe' in the list".

Rule types (use these exact strings):
- "must_together": guests MUST sit at the same table. Fields: guests:[guestId]. ("must be together", "always sit with")
- "prefer_together": try to seat together (soft). Fields: guests:[guestId]. ("would be nice", "try to", "together" without "must")
- "must_not": two sets must NOT share a table. Fields: sideA:[guestId], sideB:[guestId]. ("keep apart", "away from", "don't seat with", "exes", "not near")
- "must_table": force guests to a specific table. Fields: guests:[guestId], tableId. ("put X at [table name]", "seat X at the head table")
- "near_table": seat guests physically near a table (soft). Fields: guests:[guestId], tableId.
- "near_object": seat guests near a venue element (soft). Fields: guests:[guestId], objectId. ("near the door/entrance/stage/bar/dance floor/exit/restroom")
- "category_together": keep everyone in a category together (soft). Fields: categoryId.

Every rule also includes:
- "hard": boolean — true ONLY for firm "must"/"never"; false for soft "prefer/try/near/would like".
- "weight": integer 0-100 — hard rules use 100; soft: nice-to-have ~50, important ~75.
- "desc": a short human label, e.g. "Grandma near the entrance".

Strict rules:
- Only use IDs that appear in the lists below. Match names case-insensitively; a unique first name maps to that guest. Names may be a single word, a nickname, or a relationship label (e.g. "Grandma", "Uncle Bob", "Mom") — still match them to the guest whose name equals that, case-insensitively.
- If you cannot confidently match a person/table/element/category, OMIT that rule AND add a line to "skipped" explaining why. Never invent an ID.
- Prefer must_not with sideA/sideB for any "keep apart" wish.
- Return {"rules": [], "skipped": [...]} if nothing maps — but STILL list every unmatched wish in "skipped".

GUESTS: \#(js(context.guests))
TABLES: \#(js(context.tables))
VENUE ELEMENTS: \#(js(context.objects))
CATEGORIES: \#(js(context.categories))
"""#

        let content = try await call(
            action: .parseRules,
            systemPrompt: systemPrompt,
            userMessage: "Convert these seating wishes into rules JSON:\n\n\(text)"
        )

        // Response cleaning — mirrors web: trim, strip ```json fences, parse;
        // on failure regex-extract the first {...} or [...]; bare array = rules.
        var raw = content.trimmingCharacters(in: .whitespacesAndNewlines)
        for prefix in ["```json", "```JSON", "```"] where raw.hasPrefix(prefix) {
            raw = String(raw.dropFirst(prefix.count)); break
        }
        if raw.hasSuffix("```") { raw = String(raw.dropLast(3)) }
        raw = raw.trimmingCharacters(in: .whitespacesAndNewlines)

        func decodeEnvelope(_ str: String) -> ParsedRulesResult? {
            guard let data = str.data(using: .utf8) else { return nil }
            if let env = try? JSONDecoder().decode(NLRulesEnvelope.self, from: data),
               env.rules != nil || env.skipped != nil {
                return ParsedRulesResult(
                    rules: env.rules ?? [],
                    skipped: (env.skipped ?? []).compactMap { $0.value }
                )
            }
            if let arr = try? JSONDecoder().decode([ProposedRuleDTO].self, from: data) {
                return ParsedRulesResult(rules: arr, skipped: [])
            }
            return nil
        }

        if let result = decodeEnvelope(raw) { return result }
        for pattern in ["\\{[\\s\\S]*\\}", "\\[[\\s\\S]*\\]"] {
            if let range = raw.range(of: pattern, options: .regularExpression),
               let result = decodeEnvelope(String(raw[range])) {
                return result
            }
        }
        // Web returns empty (not an error) when nothing parses — UI shows
        // the "couldn't turn that into rules" copy.
        return ParsedRulesResult(rules: [], skipped: [])
    }

    /// Mirrors web validateProposed (src/App.jsx:13679). Never trust model IDs.
    static func validateProposedRules(
        _ proposed: [ProposedRuleDTO],
        guestIds: Set<String>,
        tableIds: Set<String>,
        objectIds: Set<String>,
        categoryIds: Set<String>
    ) -> [SeatingRule] {
        func okG(_ arr: [String]?) -> [String] {
            (arr ?? []).filter { guestIds.contains($0) }
        }
        var out: [SeatingRule] = []
        for r in proposed {
            let type = SeatingRule.RuleType.parse(r.type)
            let hard = r.hard ?? false
            let weight = max(0, min(100, r.weight ?? (hard ? 100 : 60)))
            let desc = String((r.desc ?? "").prefix(80))
            func base(_ t: SeatingRule.RuleType, guests: [String],
                      tableId: String? = nil, objectId: String? = nil,
                      categoryId: String? = nil, sideA: [String]? = nil,
                      sideB: [String]? = nil, forceHard: Bool? = nil) -> SeatingRule {
                SeatingRule(
                    id: UUID().uuidString,
                    type: t,
                    guests: guests,
                    tableId: tableId,
                    weight: forceHard == true ? 100 : weight,
                    hard: forceHard ?? hard,
                    enabled: true,
                    categoryId: categoryId, objectId: objectId, sideValue: nil,
                    sideA: sideA, sideB: sideB,
                    desc: desc,
                    auto: nil, source: "ai",
                    partyId: nil, groupId: nil
                )
            }
            switch type {
            case .mustTogether, .preferTogether:
                let g = okG(r.guests)
                if g.count >= 2 { out.append(base(type, guests: g)) }
            case .mustNot:
                let a = okG(r.sideA), b = okG(r.sideB)
                if !a.isEmpty && !b.isEmpty {
                    // Web parity: sideA + sideB + combined flat guests array.
                    out.append(base(type, guests: a + b, sideA: a, sideB: b))
                } else {
                    let flat = okG(r.guests)
                    if flat.count >= 2 { out.append(base(type, guests: flat)) }
                }
            case .mustTable:
                let g = okG(r.guests)
                if !g.isEmpty, let t = r.tableId, tableIds.contains(t) {
                    // Web forces hard:true weight:100 for explicit table pins.
                    out.append(base(type, guests: g, tableId: t, forceHard: true))
                }
            case .nearTable:
                let g = okG(r.guests)
                if !g.isEmpty, let t = r.tableId, tableIds.contains(t) {
                    out.append(base(type, guests: g, tableId: t))
                }
            case .nearObject:
                let g = okG(r.guests)
                if !g.isEmpty, let o = r.objectId, objectIds.contains(o) {
                    out.append(base(type, guests: g, objectId: o))
                }
            case .categoryTogether:
                if let c = r.categoryId, categoryIds.contains(c) {
                    // guests: [] — matches iOS category rules today; web omits
                    // the field entirely and both shapes round-trip.
                    out.append(base(type, guests: [], categoryId: c))
                }
            default:
                continue // unknown / auto-only types are dropped, same as web
            }
        }
        return out
    }

    enum AIError: LocalizedError {
        case invalidURL
        case invalidResponse
        case emptyResponse
        case unauthorized
        case tierRestricted
        case rateLimited
        case parseError
        case serverError(String)

        var errorDescription: String? {
            switch self {
            case .invalidURL: return "Invalid API URL"
            case .invalidResponse: return "Invalid response from server"
            case .emptyResponse: return "Empty response from AI"
            case .unauthorized: return "Please sign in to use AI features"
            case .tierRestricted: return "AI seating requires an Event Pass"
            case .rateLimited: return "Too many requests. Please wait a moment."
            case .parseError: return "Could not parse AI response"
            case .serverError(let msg): return msg
            }
        }
    }
}

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

    func detectConflicts(guests: [Guest], tables: [SeatTable]) async throws -> ConflictResult {
        let systemPrompt = """
        You are analyzing a seating arrangement for potential conflicts.
        Look for: people who shouldn't sit together, dietary issues, accessibility needs, family dynamics.
        Return a JSON object with:
        - conflicts: array of {type ("critical"|"warning"|"suggestion"), guests (array of names), message, suggestion}
        - score: 1-100 rating of overall arrangement quality
        - summary: brief text summary
        """

        struct ConflictContext: Codable {
            let guests: [Guest]
            let tables: [SeatTable]
        }

        let context = ConflictContext(guests: guests, tables: tables)
        let contextData = try JSONEncoder().encode(context)
        let contextString = String(data: contextData, encoding: .utf8) ?? "{}"

        let resultString = try await call(
            action: .detectConflicts,
            systemPrompt: systemPrompt,
            userMessage: "Check for conflicts:\n\n\(contextString)"
        )

        guard let responseData = resultString.data(using: String.Encoding.utf8) else {
            throw AIError.parseError
        }

        return try JSONDecoder().decode(ConflictResult.self, from: responseData)
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

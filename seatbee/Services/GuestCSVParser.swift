import Foundation

// Shared CSV parser for guest lists. Used by:
//   - Features/Guests/CSVImportSheet (post-onboarding bulk import)
//   - Features/Onboarding/OnboardingView (initial guest seed)
//
// Mirrors the column-detection + dietary-tag inference behaviour of
// `src/lib/guestCsvParser.js` (FIELD_SYNONYMS at line ~7) so iOS reads
// the same exports web users get from The Knot, Zola, Joy, Eventbrite,
// and generic CSVs.

enum GuestCSVParser {

    /// Result of parsing a CSV / pasted text payload.
    struct Result {
        let guests: [Guest]
        let detectedPlatform: String
        let error: String?
    }

    /// Parse CSV / TSV / pasted-text into Guest objects. The output
    /// guests are minimally populated — categories are raw strings (will
    /// later resolve to category IDs in the plan), parties are raw
    /// names (caller can convert to Party objects), dietary tags are
    /// inferred from the dietary free-text column.
    static func parse(_ text: String) -> Result {
        let lines = text
            .components(separatedBy: .newlines)
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard lines.count > 1 else {
            return Result(guests: [], detectedPlatform: "Unknown", error: "File appears empty or has no data rows")
        }

        // Platform detection — driven by header-row keyword sniffing.
        let header = lines[0].lowercased()
        let platform: String
        if header.contains("party") && header.contains("tags") && header.contains("rsvp status") {
            platform = "Joy (WithJoy)"
        } else if header.contains("meal choice") || header.contains("plus one") {
            platform = "Zola"
        } else if header.contains("attending") && header.contains("party name") {
            platform = "The Knot"
        } else if header.contains("ticket type") && header.contains("order") {
            platform = "Eventbrite"
        } else {
            platform = "Generic CSV"
        }

        let headerCols = parseRow(lines[0])
        func find(_ needles: [String]) -> Int? {
            headerCols.firstIndex { col in
                let lc = col.lowercased()
                return needles.contains { lc.contains($0) }
            }
        }
        let nameIdx       = find(["name", "guest"]) ?? 0
        let emailIdx      = find(["email", "e-mail", "e mail"])
        let sideIdx       = find(["side"])
        let mealIdx       = find(["meal", "entree", "entrée", "dinner choice", "food choice", "dinner selection"])
        // Keep "meal" out of dietary so a separate meal column is parsed
        // cleanly. Web does the same split.
        let dietaryIdx    = find(["dietary", "allergies", "allergy", "restrictions"])
        let rsvpIdx       = find(["rsvp", "attending", "attendance", "response"])
        let categoryIdx   = find(["tag", "categor", "groups"])
        let partyIdx      = find(["party", "household"])
        let vipIdx        = find(["vip"])
        let childIdx      = find(["child", "kid", "minor", "youth"])
        let highChairIdx  = find(["high chair", "highchair", "high-chair"])
        let notesIdx      = find(["note", "comment", "message"])
        let plusOneIdx    = find(["plus one", "plus-one", "+1", "plusone"])

        var guests: [Guest] = []

        for line in lines.dropFirst() {
            let cols = parseRow(line)
            guard cols.count > nameIdx else { continue }
            let name = cols[nameIdx].trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty else { continue }
            let parts = name.split(separator: " ", maxSplits: 1)

            let side: Guest.GuestSide = {
                guard let s = colValue(sideIdx, cols)?.lowercased() else { return .none }
                if s.contains("bride") { return .bride }
                if s.contains("groom") { return .groom }
                if s.contains("both")  { return .both }
                return .none
            }()

            let rsvp: Guest.RSVPStatus = {
                guard let r = colValue(rsvpIdx, cols)?.lowercased() else { return .unknown }
                if r.contains("yes") || r.contains("accept") || r.contains("attending") { return .yes }
                if r.contains("no")  || r.contains("decline") { return .no }
                return .pending
            }()

            let categories = colValue(categoryIdx, cols)?
                .split(separator: ",")
                .map { String($0).trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty } ?? []

            let dietaryText = colValue(dietaryIdx, cols)
            let inferredTags = inferDietaryTags(from: dietaryText)

            guests.append(Guest(
                id: UUID().uuidString,
                name: name,
                firstName: String(parts.first ?? ""),
                lastName: parts.count > 1 ? String(parts.last ?? "") : nil,
                email: colValue(emailIdx, cols),
                categories: categories,
                dietary: dietaryText,
                notes: colValue(notesIdx, cols),
                rsvp: rsvp,
                side: side,
                vip: boolColValue(vipIdx, cols),
                accessibility: nil,
                plusOne: plusOneIdx == nil ? nil : boolColValue(plusOneIdx, cols),
                party: colValue(partyIdx, cols),
                display: nil,
                dietaryTags: inferredTags.isEmpty ? nil : inferredTags,
                highChair: highChairIdx == nil ? nil : boolColValue(highChairIdx, cols),
                isChild: childIdx == nil ? nil : boolColValue(childIdx, cols),
                groupIds: nil,
                isBride: nil,
                isGroom: nil,
                meal: colValue(mealIdx, cols),
                guestCreatedAt: nil
            ))
        }

        return Result(
            guests: guests,
            detectedPlatform: platform,
            error: guests.isEmpty ? "No guests found in the file" : nil
        )
    }

    // MARK: - Helpers

    /// Splits a single CSV row honouring quoted fields containing commas.
    static func parseRow(_ line: String) -> [String] {
        var result: [String] = []
        var current = ""
        var inQuotes = false
        for char in line {
            if char == "\"" {
                inQuotes.toggle()
            } else if char == "," && !inQuotes {
                result.append(current)
                current = ""
            } else {
                current.append(char)
            }
        }
        result.append(current)
        return result
    }

    private static func colValue(_ idx: Int?, _ row: [String]) -> String? {
        guard let idx, row.count > idx else { return nil }
        let v = row[idx].trimmingCharacters(in: .whitespaces)
        return v.isEmpty ? nil : v
    }

    private static func boolColValue(_ idx: Int?, _ row: [String]) -> Bool {
        guard let raw = colValue(idx, row)?.lowercased() else { return false }
        return ["yes", "y", "true", "1", "✓", "✔", "x", "star"].contains(raw)
    }

    /// Web parity (src/lib/guestCsvParser.js inferDietaryTags): scan
    /// the dietary free-text column for common restrictions.
    private static func inferDietaryTags(from text: String?) -> [String] {
        guard let text, !text.isEmpty else { return [] }
        let dl = text.lowercased()
        var tags: [String] = []
        if dl.contains("vegan") { tags.append("vegan") }
        else if dl.contains("vegetarian") { tags.append("vegetarian") }
        if dl.contains("halal") { tags.append("halal") }
        if dl.contains("kosher") { tags.append("kosher") }
        if dl.contains("gluten") { tags.append("gluten-free") }
        if dl.contains("dairy") || dl.contains("lactose") { tags.append("dairy-free") }
        if dl.contains("nut") || dl.contains("peanut") { tags.append("nut-allergy") }
        if dl.contains("shellfish") || dl.contains("shrimp") || dl.contains("prawn")
            || dl.contains("lobster") || dl.contains("crab") {
            tags.append("shellfish-allergy")
        }
        return tags
    }
}

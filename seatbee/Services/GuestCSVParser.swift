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
        // Split first/last name columns (web's downloadable templates use
        // these). When both exist we concatenate; otherwise fall back to a
        // single "Name" / "Guest" column. Match exact tokens here so
        // "First Name" doesn't also satisfy the broader name find().
        func findExact(_ tokens: [String]) -> Int? {
            headerCols.firstIndex { col in
                let lc = col.lowercased().trimmingCharacters(in: .whitespaces)
                return tokens.contains(lc)
            }
        }
        let firstNameIdx  = findExact(["first name", "firstname", "first", "given name"])
        let lastNameIdx   = findExact(["last name", "lastname", "last", "surname", "family name"])
        // The fallback single name index excludes the first/last splits so
        // we don't accidentally treat "First Name" as the full name.
        let nameIdx: Int = {
            if let f = firstNameIdx { _ = f } // referenced to silence unused-let in closures
            let candidate = headerCols.firstIndex { col in
                let lc = col.lowercased()
                let lcTrim = lc.trimmingCharacters(in: .whitespaces)
                let isSplit = ["first name","firstname","first","given name",
                               "last name","lastname","last","surname","family name"].contains(lcTrim)
                return !isSplit && (lc.contains("name") || lc.contains("guest"))
            }
            return candidate ?? 0
        }()
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
            // Resolve name from First+Last when both are present, otherwise
            // from the single Name column.
            let resolvedFirst = colValue(firstNameIdx, cols)
            let resolvedLast  = colValue(lastNameIdx, cols)
            let resolvedName: String
            if resolvedFirst != nil || resolvedLast != nil {
                resolvedName = [resolvedFirst, resolvedLast]
                    .compactMap { $0 }
                    .joined(separator: " ")
            } else {
                guard cols.count > nameIdx else { continue }
                resolvedName = cols[nameIdx].trimmingCharacters(in: .whitespaces)
            }
            let name = resolvedName
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

            // Prefer explicit first/last from columns when present.
            let outFirst = resolvedFirst ?? String(parts.first ?? "")
            let outLast: String? = resolvedLast ?? (parts.count > 1 ? String(parts.last ?? "") : nil)
            // Auto-derive display = first token (web parity, App.jsx
            // CSV import line 10443: `display: r.display.trim() ||
            // r.name.trim().split(' ')[0]`). Without this, canvas
            // labels and place cards rendered the full name instead
            // of the abbreviated form web users expect.
            let outDisplay: String = {
                if !outFirst.isEmpty { return outFirst }
                return name.split(separator: " ").first.map(String.init) ?? name
            }()
            guests.append(Guest(
                id: UUID().uuidString,
                name: name,
                firstName: outFirst,
                lastName: outLast,
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
                display: outDisplay.isEmpty ? nil : outDisplay,
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

    // MARK: - Flexible entry point
    //
    // Used by both the onboarding paste textarea and the Guest tab's
    // Import sheet. Sniffs the first line for a CSV-header shape:
    //   - If it looks like CSV (commas + name/email/guest/rsvp keyword
    //     in line 1) → run the full GuestCSVParser pipeline above.
    //   - Otherwise → treat each line as one guest. Optional comma-
    //     separated extras after the name join into the dietary
    //     field. No plus-one parsing — Seatbee treats every guest as
    //     a real entry, so a `+1` would need its own line.
    //
    // Both surfaces share this so the paste experience is identical:
    // type "Sarah Chen, vegetarian" and either parser sees the same
    // shape.

    static func parseFlexible(_ text: String) -> Result {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return Result(guests: [], detectedPlatform: "", error: nil)
        }
        let firstLine = (trimmed.components(separatedBy: .newlines).first ?? "").lowercased()
        let looksLikeCSV = firstLine.contains(",") && (
            firstLine.contains("name") || firstLine.contains("email") ||
            firstLine.contains("guest") || firstLine.contains("rsvp")
        )
        if looksLikeCSV {
            return parse(trimmed)
        }
        return parsePlainTextLines(trimmed)
    }

    /// Plain-text-per-line fallback. Each non-empty line is one guest.
    /// `Name` is the first comma-segment; everything after joins into
    /// `dietary`. Names without a space land in `firstName`.
    private static func parsePlainTextLines(_ text: String) -> Result {
        var guests: [Guest] = []
        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }
            let parts = line.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }
            guard let name = parts.first, !name.isEmpty else { continue }
            var dietary: String? = nil
            for extra in parts.dropFirst() where !extra.isEmpty {
                dietary = (dietary == nil ? extra : "\(dietary!), \(extra)")
            }
            let nameParts = name.split(separator: " ", maxSplits: 1)
            let firstToken = String(nameParts.first ?? "")
            let lastToken = nameParts.count > 1 ? String(nameParts.last ?? "") : nil
            // Auto-derive display = first token so canvas / place cards
            // show "Asher" while the form keeps the full "Asher Russell"
            // (matches web's createGuest behaviour at App.jsx:10443).
            // Also infer dietaryTags from the dietary free-text — same
            // path the CSV parser uses, so "Sarah Chen, vegetarian"
            // produces both dietary="vegetarian" AND a vegetarian
            // dietaryTag chip in the Edit Guest UI. Without this, the
            // chip stays unselected even though the text was captured.
            let inferredTags = inferDietaryTags(from: dietary)
            guests.append(Guest(
                id: UUID().uuidString,
                name: name,
                firstName: firstToken,
                lastName: lastToken,
                email: nil, categories: [], dietary: dietary, notes: nil,
                rsvp: .unknown, side: .none, vip: false,
                accessibility: nil, plusOne: nil, party: nil,
                display: firstToken.isEmpty ? nil : firstToken,
                dietaryTags: inferredTags.isEmpty ? nil : inferredTags,
                highChair: nil, isChild: nil, groupIds: nil,
                isBride: nil, isGroom: nil, meal: nil, guestCreatedAt: nil
            ))
        }
        return Result(
            guests: guests,
            detectedPlatform: guests.isEmpty ? "" : "Pasted names",
            error: guests.isEmpty ? "No guests found" : nil
        )
    }

    // MARK: - CSV templates
    //
    // Templates pre-fill all the columns GuestCSVParser recognises so
    // a user without an existing export can download the file, fill
    // it in their own spreadsheet, and re-upload. Two flavours:
    // wedding (mirrors web's `wedding`) + general (mirrors web's
    // `general` — used for celebration / corporate). Onboarding picks
    // by event type; the Import sheet uses the active plan's event
    // type, falling back to wedding.

    enum TemplateType {
        case wedding
        case general
    }

    static func csvTemplateBody(for type: TemplateType) -> String {
        switch type {
        case .wedding:
            return """
            First Name,Last Name,Email,Phone,Party/Group,RSVP,Meal Choice,Dietary Restrictions,VIP,Child,Tags,Notes
            John,Smith,john@email.com,555-0102,Smith Family,Yes,Chicken,,No,No,"Family, Groom",Best man
            Jane,Smith,jane@email.com,555-0103,Smith Family,Yes,Fish,Gluten-free,No,No,"Family, Groom",
            Emily,Johnson,emily@email.com,555-0104,Johnson Party,Yes,Vegetarian,Vegan,No,No,"Friends, Bride",College friend
            Michael,Brown,michael@email.com,,,Maybe,,Nut allergy,No,No,Coworkers,
            David,Lee,david@email.com,555-0101,Lee Family,Yes,Chicken,,Yes,No,"Family, Head Table",Father of the bride
            """
        case .general:
            return """
            First Name,Last Name,Email,Phone,Party/Group,RSVP,VIP,Child,Tags,Dietary Restrictions,Notes
            Alex,Taylor,alex@email.com,555-0120,Taylor Family,Yes,Yes,No,Host,,Guest of honour
            Jordan,Lee,jordan@email.com,,,Yes,No,No,Guest,Vegetarian,
            Morgan,Chen,morgan@email.com,555-0121,Chen Group,Maybe,No,No,Speaker,,Presenting at 3pm
            Casey,Brown,casey@email.com,,,Yes,No,No,Volunteer,Gluten-free,Setup crew
            Riley,Patel,riley@email.com,,Patel Family,Yes,No,No,Guest,,
            """
        }
    }

    static func csvTemplateFilename(for type: TemplateType) -> String {
        switch type {
        case .wedding:  return "seatbee-wedding-template.csv"
        case .general:  return "seatbee-general-template.csv"
        }
    }

    /// Writes the chosen template to the temp directory and returns the
    /// URL. Both onboarding and the Import sheet feed this into a
    /// SwiftUI `ShareLink`.
    static func writeCSVTemplate(for type: TemplateType) -> URL? {
        let body = csvTemplateBody(for: type)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(csvTemplateFilename(for: type))
        do {
            try body.write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            return nil
        }
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

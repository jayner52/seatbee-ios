import Foundation

// MARK: - Canva CSV Builder
//
// Web parity (App.jsx ExportToCanvaModal ~13638). Generates the two CSV
// formats accepted by Canva's Bulk Create feature, mirroring web's
// column order and escaping byte-for-byte so a CSV produced on iOS
// drops into the same Canva template a web user would use.
//
// Both CSVs:
//   - Quote every field; escape internal quotes per RFC 4180
//   - Sort tables alphanumerically by name (case-insensitive, numeric-aware)
//   - Skip tables with zero seated guests
//   - Skip guests with rsvp=='no'
//   - Place card output: one row per assigned guest
//   - Table seating output: one row per table, fixed 10 guest slots

enum CanvaExportType: String, CaseIterable, Identifiable {
    case placeCards = "place_cards"
    case tableCards = "table_cards"
    var id: String { rawValue }
}

enum CanvaCSVBuilder {

    /// `{eventName}_canva_{type}.csv` with the event name underscore-mapped
    /// for any non-alphanumeric char, matching web's `(state.event?.name||'seating').replace(/[^a-z0-9]/gi,'_')`.
    static func filename(plan: SeatingPlan, type: CanvaExportType) -> String {
        let allowed = CharacterSet.alphanumerics
        let mapped = plan.name.unicodeScalars.map { allowed.contains($0) ? Character($0) : "_" }
        let safe = String(mapped).isEmpty ? "seating" : String(mapped)
        return "\(safe)_canva_\(type.rawValue).csv"
    }

    /// Per-guest CSV: `GuestName, TableName, TableNumber`. TableNumber is
    /// the first run of digits in the table name (e.g. "Table 12" → "12");
    /// if the name has no digits, the full name is used as a fallback.
    static func placeCardsCSV(plan: SeatingPlan) -> String {
        let header = ["GuestName", "TableName", "TableNumber"]
        var rows: [[String]] = [header]

        let guestById = Dictionary(uniqueKeysWithValues: plan.guests.map { ($0.id, $0) })
        let sortedTables = plan.tables.sorted { naturalCompare($0.name, $1.name) }

        for table in sortedTables {
            let tNumber = extractTableNumber(table.name)
            // Stable seat-order within table so two consecutive exports
            // produce identical CSVs.
            let assigned = table.assignments
                .sorted { $0.value < $1.value }
                .compactMap { guestById[$0.key] }
                .filter { $0.rsvp != .no }
            for g in assigned {
                rows.append([
                    g.displayName.isEmpty ? g.name : g.displayName,
                    table.name,
                    tNumber,
                ])
            }
        }
        return csvString(rows)
    }

    /// Per-table CSV: `TableName, TableNumber, Guest1...Guest10`. Fixed 10
    /// guest columns to match the Canva templates' bulk-create field count;
    /// extra guests beyond 10 are dropped (matches web behaviour, surfaced
    /// in the modal's preview text).
    static func tableCardsCSV(plan: SeatingPlan) -> String {
        var header = ["TableName", "TableNumber"]
        for i in 1...10 { header.append("Guest\(i)") }
        var rows: [[String]] = [header]

        let guestById = Dictionary(uniqueKeysWithValues: plan.guests.map { ($0.id, $0) })
        let sortedTables = plan.tables.sorted { naturalCompare($0.name, $1.name) }

        for table in sortedTables {
            let assigned = table.assignments
                .sorted { $0.value < $1.value }
                .compactMap { guestById[$0.key] }
                .filter { $0.rsvp != .no }
            guard !assigned.isEmpty else { continue }

            var row: [String] = [table.name, extractTableNumber(table.name)]
            for i in 0..<10 {
                if i < assigned.count {
                    let g = assigned[i]
                    row.append(g.displayName.isEmpty ? g.name : g.displayName)
                } else {
                    row.append("")
                }
            }
            rows.append(row)
        }
        return csvString(rows)
    }

    // MARK: - Internals

    private static func extractTableNumber(_ name: String) -> String {
        if let range = name.range(of: #"\d+"#, options: .regularExpression) {
            return String(name[range])
        }
        return name
    }

    /// Numeric-aware case-insensitive compare so "Table 2" sorts before
    /// "Table 10" (same as web's `localeCompare(b, undefined, {numeric:true})`).
    private static func naturalCompare(_ a: String, _ b: String) -> Bool {
        a.compare(b, options: [.caseInsensitive, .numeric]) == .orderedAscending
    }

    private static func csvString(_ rows: [[String]]) -> String {
        rows.map { row in
            row.map { cell in
                let escaped = cell.replacingOccurrences(of: "\"", with: "\"\"")
                return "\"\(escaped)\""
            }
            .joined(separator: ",")
        }
        .joined(separator: "\n")
    }
}

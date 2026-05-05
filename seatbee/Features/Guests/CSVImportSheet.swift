import SwiftUI
import UniformTypeIdentifiers

struct CSVImportSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var showFilePicker = false
    @State private var parsedGuests: [Guest] = []
    @State private var rawText = ""
    @State private var detectedPlatform = ""
    @State private var isProcessing = false
    @State private var errorMessage: String?
    @State private var tierLimitMessage: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Header
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Import Guest List")
                            .font(SBFont.displayLarge)
                            .foregroundStyle(Color.sbCharcoal)
                        Text("Import from CSV, Excel, or paste from Joy, Zola, The Knot, and more.")
                            .font(SBFont.bodySmall)
                            .foregroundStyle(Color.sbWarm)
                    }

                    // File picker button
                    SBButton(title: "Choose CSV or Excel file", icon: "doc.badge.plus", variant: .primary, fullWidth: true) {
                        showFilePicker = true
                    }

                    SBOrnament(label: "OR PASTE")

                    // Paste area
                    ZStack(alignment: .topLeading) {
                        RoundedRectangle(cornerRadius: SBRadius.button)
                            .strokeBorder(Color.sbWarm2, style: StrokeStyle(lineWidth: 1, dash: [6, 4]))
                            .background(
                                RoundedRectangle(cornerRadius: SBRadius.button)
                                    .fill(Color.sbIvory2)
                            )

                        if rawText.isEmpty {
                            Text("Name, Email, Side, Dietary\nSarah Chen, sarah@email.com, Bride, Vegetarian\nJon Park, jon@email.com, Groom,\n...")
                                .font(SBFont.bodySmall)
                                .foregroundStyle(Color.sbWarm2)
                                .padding(16)
                        }

                        TextEditor(text: $rawText)
                            .font(SBFont.bodySmall)
                            .scrollContentBackground(.hidden)
                            .padding(12)
                    }
                    .frame(height: 160)

                    if !rawText.isEmpty {
                        SBButton(title: "Parse pasted text", icon: "sparkles", variant: .gold, fullWidth: true) {
                            parseCSVText(rawText)
                        }
                    }

                    // Detected platform
                    if !detectedPlatform.isEmpty {
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(Color.sbSage)
                            Text("Detected: \(detectedPlatform)")
                                .font(SBFont.bodySemibold)
                                .foregroundStyle(Color.sbCharcoal)
                        }
                    }

                    // Processing
                    if isProcessing {
                        HStack(spacing: 8) {
                            ProgressView()
                            Text("Parsing guests...")
                                .font(SBFont.body)
                                .foregroundStyle(Color.sbWarm)
                        }
                        .frame(maxWidth: .infinity)
                    }

                    // Error
                    if let errorMessage {
                        Text(errorMessage)
                            .font(SBFont.caption)
                            .foregroundStyle(Color.sbError)
                    }

                    // Preview
                    if !parsedGuests.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("\(parsedGuests.count) GUESTS FOUND")
                                .font(SBFont.capsLabel)
                                .foregroundStyle(Color.sbGoldDk)
                                .letterSpacing(1.5)

                            ForEach(parsedGuests.prefix(10)) { guest in
                                HStack(spacing: 10) {
                                    SBAvatar(name: guest.displayName, size: 28)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(guest.displayName)
                                            .font(SBFont.bodySmallBold)
                                            .foregroundStyle(Color.sbCharcoal)
                                        if let dietary = guest.dietary {
                                            Text(dietary)
                                                .font(SBFont.caption)
                                                .foregroundStyle(Color.sbWarm)
                                        }
                                    }
                                    Spacer()
                                    if guest.side != .none {
                                        SBChip(text: guest.side.rawValue.capitalized, variant: .gold)
                                    }
                                }
                            }

                            if parsedGuests.count > 10 {
                                Text("+ \(parsedGuests.count - 10) more")
                                    .font(SBFont.caption)
                                    .foregroundStyle(Color.sbWarm)
                            }
                        }

                        SBButton(title: "Import \(parsedGuests.count) guests", icon: "person.badge.plus", variant: .gold, fullWidth: true) {
                            importGuests()
                        }
                    }

                    Spacer(minLength: 40)
                }
                .padding(.horizontal, SBSpacing.screenMargin)
                .padding(.top, 16)
            }
            .background(Color.sbIvory)
            .navigationTitle("Import")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Color.sbWarm)
                }
            }
            .fileImporter(isPresented: $showFilePicker, allowedContentTypes: [.commaSeparatedText, .plainText, .data]) { result in
                switch result {
                case .success(let url):
                    loadFile(url)
                case .failure(let error):
                    errorMessage = error.localizedDescription
                }
            }
            .alert(
                "Guest Limit Reached",
                isPresented: Binding(get: { tierLimitMessage != nil }, set: { if !$0 { tierLimitMessage = nil } })
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(tierLimitMessage ?? "")
            }
        }
    }

    // MARK: - File Loading

    private func loadFile(_ url: URL) {
        guard url.startAccessingSecurityScopedResource() else {
            errorMessage = "Can't access file"
            return
        }
        defer { url.stopAccessingSecurityScopedResource() }

        do {
            let text = try String(contentsOf: url, encoding: .utf8)
            rawText = text
            parseCSVText(text)
        } catch {
            errorMessage = "Failed to read file: \(error.localizedDescription)"
        }
    }

    // MARK: - CSV Parsing

    private func parseCSVText(_ text: String) {
        isProcessing = true
        errorMessage = nil

        let lines = text.components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard lines.count > 1 else {
            errorMessage = "File appears empty or has no data rows"
            isProcessing = false
            return
        }

        // Detect platform
        let header = lines[0].lowercased()
        if header.contains("party") && header.contains("tags") && header.contains("rsvp status") {
            detectedPlatform = "Joy (WithJoy)"
        } else if header.contains("meal choice") || header.contains("plus one") {
            detectedPlatform = "Zola"
        } else if header.contains("attending") && header.contains("party name") {
            detectedPlatform = "The Knot"
        } else if header.contains("ticket type") && header.contains("order") {
            detectedPlatform = "Eventbrite"
        } else {
            detectedPlatform = "Generic CSV"
        }

        // Parse header columns. Web's guestCsvParser.js (FIELD_SYNONYMS)
        // uses partial-match against a wider synonym list — mirror that
        // here so iOS recognizes the same column headers web does.
        let headerCols = parseCSVRow(lines[0])
        func find(_ needles: [String]) -> Int? {
            headerCols.firstIndex { col in
                let lc = col.lowercased()
                return needles.contains { lc.contains($0) }
            }
        }
        let nameIdx = find(["name", "guest"]) ?? 0
        let emailIdx = find(["email", "e-mail", "e mail"])
        let sideIdx = find(["side"])
        let mealIdx = find(["meal", "entree", "entrée", "dinner choice", "food choice", "dinner selection"])
        // The dietary column drops "meal" matching here so a separate meal
        // column is parsed cleanly — web does the same split.
        let dietaryIdx = find(["dietary", "allergies", "allergy", "restrictions"])
        let rsvpIdx = find(["rsvp", "attending", "attendance", "response"])
        let categoryIdx = find(["tag", "categor", "groups"])
        let partyIdx = find(["party", "household"])
        let vipIdx = find(["vip"])
        let childIdx = find(["child", "kid", "minor", "youth"])
        let highChairIdx = find(["high chair", "highchair", "high-chair"])
        let notesIdx = find(["note", "comment", "message"])

        func col(_ idx: Int?, _ row: [String]) -> String? {
            guard let idx, row.count > idx else { return nil }
            let v = row[idx].trimmingCharacters(in: .whitespaces)
            return v.isEmpty ? nil : v
        }
        func boolCol(_ idx: Int?, _ row: [String]) -> Bool {
            guard let raw = col(idx, row)?.lowercased() else { return false }
            return ["yes", "y", "true", "1", "✓", "✔", "x", "star"].contains(raw)
        }
        // Web parity (src/lib/guestCsvParser.js inferDietaryTags): infer
        // structured tags from the dietary free-text column using
        // case-insensitive keyword matching.
        func inferDietaryTags(from text: String?) -> [String] {
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
            if dl.contains("shellfish") || dl.contains("shrimp") || dl.contains("prawn") || dl.contains("lobster") || dl.contains("crab") {
                tags.append("shellfish-allergy")
            }
            return tags
        }

        var guests: [Guest] = []

        for line in lines.dropFirst() {
            let cols = parseCSVRow(line)
            guard cols.count > nameIdx else { continue }

            let name = cols[nameIdx].trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty else { continue }

            let parts = name.split(separator: " ", maxSplits: 1)

            let side: Guest.GuestSide = {
                guard let s = col(sideIdx, cols)?.lowercased() else { return .none }
                if s.contains("bride") { return .bride }
                if s.contains("groom") { return .groom }
                if s.contains("both")  { return .both }
                return .none
            }()

            let rsvp: Guest.RSVPStatus = {
                guard let r = col(rsvpIdx, cols)?.lowercased() else { return .unknown }
                if r.contains("yes") || r.contains("accept") || r.contains("attending") { return .yes }
                if r.contains("no") || r.contains("decline") { return .no }
                return .pending
            }()

            let categories = col(categoryIdx, cols)?
                .split(separator: ",")
                .map { String($0).trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty } ?? []

            let dietaryText = col(dietaryIdx, cols)
            let inferredTags = inferDietaryTags(from: dietaryText)

            guests.append(Guest(
                id: UUID().uuidString,
                name: name,
                firstName: String(parts.first ?? ""),
                lastName: parts.count > 1 ? String(parts.last ?? "") : nil,
                email: col(emailIdx, cols),
                categories: categories,
                dietary: dietaryText,
                notes: col(notesIdx, cols),
                rsvp: rsvp,
                side: side,
                vip: boolCol(vipIdx, cols),
                accessibility: nil,
                plusOne: nil,
                party: col(partyIdx, cols),
                display: nil,
                dietaryTags: inferredTags.isEmpty ? nil : inferredTags,
                highChair: highChairIdx == nil ? nil : boolCol(highChairIdx, cols),
                isChild: childIdx == nil ? nil : boolCol(childIdx, cols),
                groupIds: nil,
                isBride: nil,
                isGroom: nil,
                meal: col(mealIdx, cols),
                guestCreatedAt: nil
            ))
        }

        parsedGuests = guests
        isProcessing = false

        if guests.isEmpty {
            errorMessage = "No guests found in the file"
        }
    }

    private func parseCSVRow(_ line: String) -> [String] {
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

    // MARK: - Import

    private func importGuests() {
        guard var plan = appState.activePlan else { return }

        // Tier-limit guard: block if importing this batch would exceed the cap.
        if appState.wouldExceedGuestLimit(adding: parsedGuests.count) {
            let limits = appState.activePlanLimits
            let tier = appState.activePlanTier
            let remaining = max(0, limits.seatedGuests - plan.guests.count)
            tierLimitMessage = "Your \(tier.displayName) plan supports up to \(limits.seatedGuests) guests. You can add \(remaining) more — this CSV has \(parsedGuests.count). Apply an Event Pass in Settings to import the full list."
            HapticEngine.error()
            return
        }

        plan.guests.append(contentsOf: parsedGuests)
        appState.activePlan = plan
        HapticEngine.success()

        Task {
            try? await appState.database.savePlanData(plan: plan)
        }

        dismiss()
    }
}

private extension String {
    var nilIfEmpty: String? {
        trimmingCharacters(in: .whitespaces).isEmpty ? nil : self
    }
}

#Preview {
    CSVImportSheet()
        .environment(AppState())
}

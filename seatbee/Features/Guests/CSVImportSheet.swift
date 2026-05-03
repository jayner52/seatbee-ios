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

        // Parse header columns
        let headerCols = parseCSVRow(lines[0])
        let nameIdx = headerCols.firstIndex { $0.lowercased().contains("name") } ?? 0
        let emailIdx = headerCols.firstIndex { $0.lowercased().contains("email") }
        let sideIdx = headerCols.firstIndex { $0.lowercased().contains("side") }
        let dietaryIdx = headerCols.firstIndex { $0.lowercased().contains("diet") || $0.lowercased().contains("meal") }
        let rsvpIdx = headerCols.firstIndex { $0.lowercased().contains("rsvp") || $0.lowercased().contains("attending") }
        let categoryIdx = headerCols.firstIndex { $0.lowercased().contains("tag") || $0.lowercased().contains("group") || $0.lowercased().contains("category") }

        var guests: [Guest] = []

        for line in lines.dropFirst() {
            let cols = parseCSVRow(line)
            guard cols.count > nameIdx else { continue }

            let name = cols[nameIdx].trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty else { continue }

            let parts = name.split(separator: " ", maxSplits: 1)
            let side: Guest.GuestSide
            if let sideIdx, cols.count > sideIdx {
                let sideStr = cols[sideIdx].lowercased().trimmingCharacters(in: .whitespaces)
                if sideStr.contains("bride") { side = .bride }
                else if sideStr.contains("groom") { side = .groom }
                else { side = .none }
            } else { side = .none }

            let rsvp: Guest.RSVPStatus
            if let rsvpIdx, cols.count > rsvpIdx {
                let r = cols[rsvpIdx].lowercased().trimmingCharacters(in: .whitespaces)
                if r.contains("yes") || r.contains("accept") || r.contains("attending") { rsvp = .yes }
                else if r.contains("no") || r.contains("decline") { rsvp = .no }
                else { rsvp = .pending }
            } else { rsvp = .unknown }

            let categories: [String]
            if let categoryIdx, cols.count > categoryIdx {
                categories = cols[categoryIdx].split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            } else { categories = [] }

            guests.append(Guest(
                id: UUID().uuidString,
                name: name,
                firstName: String(parts.first ?? ""),
                lastName: parts.count > 1 ? String(parts.last ?? "") : nil,
                email: emailIdx.flatMap { cols.count > $0 ? cols[$0].trimmingCharacters(in: .whitespaces) : nil },
                categories: categories,
                dietary: dietaryIdx.flatMap { cols.count > $0 ? cols[$0].trimmingCharacters(in: .whitespaces) : nil }?.nilIfEmpty,
                notes: nil,
                rsvp: rsvp,
                side: side,
                vip: false,
                accessibility: nil,
                plusOne: nil,
                party: nil
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

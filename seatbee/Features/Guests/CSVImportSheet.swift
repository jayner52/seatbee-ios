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
                Button("Upgrade") { appState.showUpgrade = true }
                Button("Not now", role: .cancel) {}
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
        // Delegated to GuestCSVParser so the same column-detection +
        // dietary-tag inference is shared with onboarding.
        let result = GuestCSVParser.parse(text)
        detectedPlatform = result.detectedPlatform
        parsedGuests = result.guests
        errorMessage = result.error
        isProcessing = false
    }

    private func parseCSVRow(_ line: String) -> [String] {
        // Kept for any legacy callers — delegates to the shared parser.
        return GuestCSVParser.parseRow(line)
    }

    // MARK: - Import

    private func importGuests() {
        guard var plan = appState.activePlan else { return }

        // Web parity: importing guests is never blocked by the tier limit.
        // The limit only applies when SEATING guests (assigning to tables).
        // Users should be able to build their full guest list on the free
        // tier and only hit the gate when they try to seat more than the cap.
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

import SwiftUI
import UniformTypeIdentifiers

// Brought to parity with the onboarding upload surface (web parity
// goal: same paste / template / CSV experience whether you land
// here from onboarding or from the Guests tab post-creation):
//   - File button now shows the same platform subtitle used in
//     onboarding (Joy, Zola, The Knot, Eventbrite, generic CSV).
//   - "Download CSV template" link below — picks the template
//     flavour from the active plan's event type (wedding /
//     celebration) and falls back to wedding when no plan is open.
//   - Paste textarea uses the same example as onboarding
//     ("Sarah Chen, vegetarian") instead of intimidating CSV
//     header copy. Auto-parses on every keystroke via the shared
//     `GuestCSVParser.parseFlexible` — no "Parse pasted text"
//     button needed.
//   - Same dietary-syntax tip line so users discover the inline
//     comma-separator pattern.
// MARK: - Duplicate detection diff
//
// Web parity: when a re-import contains guests already in the plan,
// match by normalised name (lowercase, trimmed, whitespace collapsed —
// App.jsx:10884) and bucket each row as new / changed / unchanged so
// the user doesn't get duplicate guest entries every time they pull
// down a fresh export from Joy / Zola / The Knot.

struct CSVImportFieldFlags: OptionSet {
    let rawValue: Int
    static let rsvp     = CSVImportFieldFlags(rawValue: 1 << 0)
    static let meal     = CSVImportFieldFlags(rawValue: 1 << 1)
    static let dietary  = CSVImportFieldFlags(rawValue: 1 << 2)   // covers both dietary + dietaryTags
    static let email    = CSVImportFieldFlags(rawValue: 1 << 3)
    static let allByDefault: CSVImportFieldFlags = [.rsvp, .meal, .dietary, .email]
}

private struct CSVImportDiff {
    var newGuests: [Guest] = []
    var changed: [(existingId: String, incoming: Guest, fields: CSVImportFieldFlags)] = []
    var unchangedCount: Int = 0
    var totalRows: Int { newGuests.count + changed.count + unchangedCount }
}

private func normaliseName(_ s: String?) -> String {
    guard let s else { return "" }
    let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    return trimmed.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
}

struct CSVImportSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var showFilePicker = false
    @State private var parsedGuests: [Guest] = []
    @State private var rawText = ""
    @State private var detectedPlatform = ""
    @State private var errorMessage: String?
    @State private var tierLimitMessage: String?
    @State private var csvTemplateURL: URL?
    /// Which fields to overwrite on duplicate-name matches. Defaults
    /// to all four — same default web uses (App.jsx:10862).
    @State private var updateFields: CSVImportFieldFlags = .allByDefault

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

                    // CSV upload — gold pill button mirroring onboarding's
                    // visual treatment so the two surfaces feel like one
                    // flow.
                    Button {
                        errorMessage = nil
                        showFilePicker = true
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "tray.and.arrow.down")
                                .font(.system(size: 14, weight: .semibold))
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Upload CSV or Excel")
                                    .font(SBFont.bodySemibold)
                                Text("Joy, Zola, The Knot, Eventbrite, generic CSV")
                                    .font(SBFont.caption)
                                    .foregroundStyle(Color.white.opacity(0.85))
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .foregroundStyle(Color.white)
                        .padding(14)
                        .background(LinearGradient(colors: [Color.sbGold, Color.sbGoldDk],
                                                   startPoint: .top, endPoint: .bottom))
                        .clipShape(RoundedRectangle(cornerRadius: SBRadius.button))
                    }
                    .buttonStyle(.plain)

                    // Template download — picks wedding / general based
                    // on the active plan's event type. Same template
                    // bytes as onboarding's, generated by GuestCSVParser.
                    if let csvTemplateURL {
                        ShareLink(item: csvTemplateURL) {
                            HStack(spacing: 6) {
                                Image(systemName: "arrow.down.doc")
                                    .font(.system(size: 12, weight: .semibold))
                                Text("Download CSV template")
                                    .font(SBFont.caption)
                            }
                            .foregroundStyle(Color.sbGoldDk)
                        }
                    }

                    SBOrnament(label: "OR PASTE")

                    // Paste area — same plain-text-friendly placeholder
                    // as onboarding so the two surfaces don't disagree
                    // on what's pasteable. Auto-parses on every change.
                    ZStack(alignment: .topLeading) {
                        TextEditor(text: $rawText)
                            .font(SBFont.body)
                            .scrollContentBackground(.hidden)
                            .padding(8)
                            .onChange(of: rawText) { _, _ in parseAuto() }

                        if rawText.isEmpty {
                            Text("Sarah Chen, vegetarian\nJon Park\nAmir Patel, gluten-free\n…")
                                .font(SBFont.body)
                                .foregroundStyle(Color.sbWarm2)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 16)
                                .allowsHitTesting(false)
                        }
                    }
                    .frame(height: 160)
                    .background(Color.sbIvory2)
                    .clipShape(RoundedRectangle(cornerRadius: SBRadius.button))

                    // Inline syntax hint — same copy as onboarding so
                    // discovery of the dietary-after-comma syntax
                    // happens on either surface.
                    HStack(spacing: 4) {
                        Image(systemName: "lightbulb")
                            .font(.system(size: 11))
                            .foregroundStyle(Color.sbGoldDk)
                        Text("Tip: add a comma + dietary note (e.g. \"Sarah Chen, vegetarian\"). Add meals and parties after.")
                            .font(SBFont.caption)
                            .foregroundStyle(Color.sbWarm)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    // Detected platform
                    if !detectedPlatform.isEmpty && !parsedGuests.isEmpty {
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(Color.sbSage)
                            Text("Detected: \(detectedPlatform)")
                                .font(SBFont.bodySemibold)
                                .foregroundStyle(Color.sbCharcoal)
                        }
                    }

                    // Error
                    if let errorMessage {
                        Text(errorMessage)
                            .font(SBFont.caption)
                            .foregroundStyle(Color.sbError)
                    }

                    // Preview
                    if !parsedGuests.isEmpty {
                        let diff = computeDiff()
                        VStack(alignment: .leading, spacing: 12) {
                            Text("\(parsedGuests.count) GUESTS FOUND")
                                .font(SBFont.capsLabel)
                                .foregroundStyle(Color.sbGoldDk)
                                .letterSpacing(1.5)

                            if !diff.changed.isEmpty || diff.unchangedCount > 0 {
                                duplicateBreakdown(diff)
                                if !diff.changed.isEmpty {
                                    fieldUpdateToggles
                                }
                            }

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

                        SBButton(title: importButtonTitle(diff: diff),
                                 icon: "person.badge.plus", variant: .gold, fullWidth: true) {
                            importGuests(diff: diff)
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
            .task {
                // Build the right CSV template for this plan's event
                // type. Wedding by default for plans with no type.
                let evt = appState.activePlan?.eventType
                let templateType: GuestCSVParser.TemplateType =
                    (evt == .wedding) ? .wedding : .general
                csvTemplateURL = GuestCSVParser.writeCSVTemplate(for: templateType)
            }
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
                Button("Upgrade") {
                    dismiss()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                        appState.showUpgrade = true
                    }
                }
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

        // Try UTF-8 first; fall back to Windows-1252 then ISO Latin-1 for
        // CSVs exported by Windows Excel which often uses legacy encodings.
        let text: String
        if let utf8 = try? String(contentsOf: url, encoding: .utf8), !utf8.contains("\u{FFFD}") {
            text = utf8
        } else if let cp1252 = try? String(contentsOf: url, encoding: .windowsCP1252) {
            text = cp1252
        } else if let latin1 = try? String(contentsOf: url, encoding: .isoLatin1) {
            text = latin1
        } else {
            errorMessage = "Failed to read file: unsupported encoding"
            return
        }
        rawText = text
        // The .onChange on the TextEditor handles auto-parsing,
        // but file uploads bypass that path — explicit call here.
        parseAuto()
    }

    // MARK: - Parsing
    //
    // Same shared helper as the onboarding paste textarea so paste +
    // file flows produce identical Guest objects regardless of which
    // surface the user came in on. Header-row CSV uses the full
    // platform-detecting parser; plain-text-per-line goes through
    // the lightweight "Name, dietary" path.

    private func parseAuto() {
        let result = GuestCSVParser.parseFlexible(rawText)
        parsedGuests = result.guests
        detectedPlatform = result.guests.isEmpty ? "" : result.detectedPlatform
        // Only surface "no guests" errors when there's actual input —
        // an empty textarea isn't an error state.
        errorMessage = rawText.isEmpty ? nil : result.error
    }

    // MARK: - Duplicate detection

    /// Bucket every parsed guest as new / changed / unchanged against
    /// the active plan's guest list, matching by normalised full name
    /// (web parity: App.jsx:10884).
    private func computeDiff() -> CSVImportDiff {
        var diff = CSVImportDiff()
        guard let existing = appState.activePlan?.guests else {
            diff.newGuests = parsedGuests
            return diff
        }
        var byName: [String: Guest] = [:]
        for g in existing {
            let key = normaliseName(g.name)
            if !key.isEmpty { byName[key] = g }
        }
        for incoming in parsedGuests {
            let key = normaliseName(incoming.name)
            guard let match = byName[key] else {
                diff.newGuests.append(incoming)
                continue
            }
            var changed: CSVImportFieldFlags = []
            // Only flag fields where incoming is non-empty AND differs;
            // empty CSV cells shouldn't blow away existing data.
            if incoming.rsvp != .unknown && incoming.rsvp != match.rsvp {
                changed.insert(.rsvp)
            }
            if let m = incoming.meal?.nilIfEmpty,
               (match.meal?.trimmingCharacters(in: .whitespaces) ?? "") != m.trimmingCharacters(in: .whitespaces) {
                changed.insert(.meal)
            }
            let incomingDietary = incoming.dietary?.nilIfEmpty
            let incomingTags = incoming.dietaryTags ?? []
            let dietaryDiffers = (incomingDietary != nil && incomingDietary != match.dietary)
                || (!incomingTags.isEmpty && Set(incomingTags) != Set(match.dietaryTags ?? []))
            if dietaryDiffers { changed.insert(.dietary) }
            if let e = incoming.email?.nilIfEmpty, e != match.email {
                changed.insert(.email)
            }
            if changed.isEmpty {
                diff.unchangedCount += 1
            } else {
                diff.changed.append((existingId: match.id, incoming: incoming, fields: changed))
            }
        }
        return diff
    }

    @ViewBuilder
    private func duplicateBreakdown(_ diff: CSVImportDiff) -> some View {
        HStack(spacing: 8) {
            breakdownPill(count: diff.newGuests.count, label: "new", color: .sbSage)
            breakdownPill(count: diff.changed.count, label: "updated", color: .sbGoldDk)
            if diff.unchangedCount > 0 {
                breakdownPill(count: diff.unchangedCount, label: "unchanged", color: .sbWarm)
            }
        }
    }

    private func breakdownPill(count: Int, label: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Text("\(count)")
                .font(SBFont.bodySmallBold)
                .foregroundStyle(color)
            Text(label)
                .font(SBFont.caption)
                .foregroundStyle(Color.sbWarm)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(color.opacity(0.12))
        .clipShape(Capsule())
    }

    @ViewBuilder
    private var fieldUpdateToggles: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("UPDATE WHICH FIELDS?")
                .font(SBFont.capsLabel)
                .foregroundStyle(Color.sbWarm)
                .letterSpacing(1.5)
            HStack(spacing: 8) {
                fieldToggleChip(.rsvp, label: "RSVP")
                fieldToggleChip(.meal, label: "Meal")
                fieldToggleChip(.dietary, label: "Dietary")
                fieldToggleChip(.email, label: "Email")
            }
            Text("Existing guests with matching names update only the selected fields. Unselected fields keep their current value.")
                .font(SBFont.caption)
                .foregroundStyle(Color.sbWarm)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func fieldToggleChip(_ flag: CSVImportFieldFlags, label: String) -> some View {
        let on = updateFields.contains(flag)
        return Button {
            if on { updateFields.remove(flag) } else { updateFields.insert(flag) }
            HapticEngine.selection()
        } label: {
            Text(label)
                .font(SBFont.caption)
                .foregroundStyle(on ? Color.white : Color.sbCharcoal)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(on ? Color.sbGoldDk : Color.white)
                .overlay(
                    Capsule().strokeBorder(on ? Color.sbGoldDk : Color.sbLine, lineWidth: 1)
                )
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func importButtonTitle(diff: CSVImportDiff) -> String {
        let parts: [String] = [
            diff.newGuests.count > 0 ? "Add \(diff.newGuests.count)" : nil,
            diff.changed.count > 0 ? "Update \(diff.changed.count)" : nil,
        ].compactMap { $0 }
        if parts.isEmpty { return "No changes" }
        return parts.joined(separator: " · ")
    }

    // MARK: - Import

    private func importGuests(diff: CSVImportDiff) {
        guard var plan = appState.activePlan else { return }

        // Web parity: importing guests is never blocked by the tier limit.
        // The limit only applies when SEATING guests (assigning to tables).

        // Append truly new guests.
        plan.guests.append(contentsOf: diff.newGuests)

        // Patch matching guests in place. Only overwrite fields the
        // user opted in for via updateFields; this lets people pull in
        // a fresh RSVP-only export without nuking dietary notes etc.
        for entry in diff.changed {
            guard let idx = plan.guests.firstIndex(where: { $0.id == entry.existingId }) else { continue }
            if entry.fields.contains(.rsvp), updateFields.contains(.rsvp) {
                plan.guests[idx].rsvp = entry.incoming.rsvp
            }
            if entry.fields.contains(.meal), updateFields.contains(.meal) {
                plan.guests[idx].meal = entry.incoming.meal
            }
            if entry.fields.contains(.dietary), updateFields.contains(.dietary) {
                if let d = entry.incoming.dietary?.nilIfEmpty {
                    plan.guests[idx].dietary = d
                }
                let incomingTags = entry.incoming.dietaryTags ?? []
                if !incomingTags.isEmpty {
                    plan.guests[idx].dietaryTags = incomingTags
                }
            }
            if entry.fields.contains(.email), updateFields.contains(.email) {
                plan.guests[idx].email = entry.incoming.email
            }
        }

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

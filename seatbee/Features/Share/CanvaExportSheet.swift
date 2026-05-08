import SwiftUI

// MARK: - Export to Canva sheet (web parity)
//
// Mirrors web's ExportToCanvaModal (App.jsx ~13638): type picker, live
// preview, 5-step instruction flow. Premium-gated upstream — this sheet
// is only ever presented when the active plan is on a paid tier.

struct CanvaExportSheet: View {
    let plan: SeatingPlan
    @Environment(\.dismiss) private var dismiss

    @State private var exportType: CanvaExportType = .placeCards
    @State private var didDownload = false

    private var canvaTemplateURL: URL {
        switch exportType {
        case .placeCards:
            return URL(string: "https://www.canva.com/templates/?query=wedding+place+cards")!
        case .tableCards:
            return URL(string: "https://www.canva.com/templates/?query=seating+chart+table+cards")!
        }
    }

    private var typeLabel: String {
        exportType == .placeCards ? "Place Cards" : "Table Seating Cards"
    }

    private var rowCount: Int {
        let guestById = Dictionary(uniqueKeysWithValues: plan.guests.map { ($0.id, $0) })
        switch exportType {
        case .placeCards:
            var n = 0
            for t in plan.tables {
                for gid in t.assignments.keys {
                    if let g = guestById[gid], g.rsvp != .no { n += 1 }
                }
            }
            return n
        case .tableCards:
            var n = 0
            for t in plan.tables {
                let hasAssigned = t.assignments.keys.contains { gid in
                    guestById[gid].map { $0.rsvp != .no } ?? false
                }
                if hasAssigned { n += 1 }
            }
            return n
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    typePicker
                    if rowCount == 0 {
                        emptyState
                    } else {
                        previewBlock
                    }
                    instructionsBlock
                }
                .padding(20)
            }
            .background(Color.sbIvory)
            .navigationTitle("Export to Canva")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(SBFont.bodySemibold)
                        .foregroundStyle(Color.sbGoldDk)
                }
            }
        }
    }

    // MARK: - Type picker

    private var typePicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("CARD TYPE")
                .font(SBFont.capsLabel)
                .foregroundStyle(Color.sbWarm)
                .letterSpacing(1.5)
            HStack(spacing: 10) {
                typeChoice(.placeCards,
                           icon: "rectangle",
                           title: "Place Cards",
                           subtitle: "One card per guest with name & table")
                typeChoice(.tableCards,
                           icon: "rectangle.split.3x1",
                           title: "Table Seating Cards",
                           subtitle: "One card per table with all guests listed")
            }
        }
    }

    private func typeChoice(_ t: CanvaExportType, icon: String, title: String, subtitle: String) -> some View {
        let selected = exportType == t
        return Button {
            exportType = t
            didDownload = false
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(selected ? Color.white : Color.sbGoldDk)
                    .frame(width: 32, height: 32)
                    .background(selected ? Color.sbGoldDk : Color.sbChampagne.opacity(0.5))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                Text(title)
                    .font(SBFont.bodySmallBold)
                    .foregroundStyle(Color.sbCharcoal)
                    .multilineTextAlignment(.leading)
                Text(subtitle)
                    .font(SBFont.caption)
                    .foregroundStyle(Color.sbWarm)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(selected ? Color.sbChampagne.opacity(0.4) : Color.sbIvory2)
            .clipShape(RoundedRectangle(cornerRadius: SBRadius.card))
            .overlay(
                RoundedRectangle(cornerRadius: SBRadius.card)
                    .strokeBorder(selected ? Color.sbGoldDk : Color.sbLine,
                                  lineWidth: selected ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Preview / empty state

    private struct TablePreviewRow: Identifiable {
        let id: String
        let label: String
    }

    private var previewRows: [TablePreviewRow] {
        let guestById = Dictionary(uniqueKeysWithValues: plan.guests.map { ($0.id, $0) })
        return plan.tables.compactMap { table in
            let names = table.assignments.keys.compactMap { gid -> String? in
                guard let g = guestById[gid] else { return nil }
                let n = g.displayName.isEmpty ? g.name : g.displayName
                return n.isEmpty ? nil : n
            }
            guard !names.isEmpty else { return nil }
            let label = "\(table.name) (\(names.count)) · \(names.joined(separator: " · "))"
            return TablePreviewRow(id: table.id, label: label)
        }
    }

    private var previewBlock: some View {
        let totalSeated = plan.tables.reduce(0) { $0 + $1.assignments.count }
        let rows = previewRows
        return VStack(alignment: .leading, spacing: 8) {
            Text("PREVIEW")
                .font(SBFont.capsLabel)
                .foregroundStyle(Color.sbWarm)
                .letterSpacing(1.5)
            VStack(alignment: .leading, spacing: 6) {
                Text("\(totalSeated) guests · \(rows.count) tables")
                    .font(SBFont.bodySmallBold)
                    .foregroundStyle(Color.sbCharcoal)
                ForEach(Array(rows.prefix(6))) { row in
                    Text(row.label)
                        .font(SBFont.caption)
                        .foregroundStyle(Color.sbWarm)
                        .lineLimit(2)
                }
                if rows.count > 6 {
                    Text("…and \(rows.count - 6) more tables")
                        .font(SBFont.caption)
                        .foregroundStyle(Color.sbWarm2)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.sbIvory2)
            .clipShape(RoundedRectangle(cornerRadius: SBRadius.card))
        }
    }

    private var emptyState: some View {
        HStack(spacing: 10) {
            Image(systemName: "info.circle.fill")
                .foregroundStyle(Color.sbGoldDk)
            Text("Assign guests to tables first, then come back here to export.")
                .font(SBFont.caption)
                .foregroundStyle(Color.sbCharcoal)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.sbChampagne.opacity(0.4))
        .clipShape(RoundedRectangle(cornerRadius: SBRadius.card))
    }

    // MARK: - Instructions

    private var instructionsBlock: some View {
        VStack(alignment: .leading, spacing: 14) {
            instructionStep(
                num: 1,
                title: "Download your CSV",
                body: "We'll generate a CSV with one row per \(exportType == .placeCards ? "guest" : "table"). You'll upload it to Canva in step 4."
            ) {
                downloadButton
            }
            instructionStep(
                num: 2,
                title: "Open a Canva template",
                body: "Tap below to open Canva's \(exportType == .placeCards ? "wedding place card" : "table seating card") templates. Pick any one you like to open it in the Canva editor."
            ) {
                openCanvaButton
            }
            instructionStep(
                num: 3,
                title: "In the Canva editor: Apps → Bulk Create",
                body: "Click Apps in the left sidebar → scroll down to \"More from Canva\" → click Bulk Create.\n\nNote: Bulk Create requires Canva Pro (free 30-day trial available).",
                accessory: nil
            )
            instructionStep(
                num: 4,
                title: "Upload your CSV & generate",
                body: "In the Bulk Create panel, click Upload data and select the CSV from step 1. Match the columns to the template fields, then click Generate.",
                accessory: nil
            )
            instructionStep(
                num: 5,
                title: "Customize & print",
                body: "Customize fonts, colors, or sizes — then download and print.",
                accessory: nil
            )
        }
    }

    private func instructionStep<Accessory: View>(num: Int, title: String, body: String, @ViewBuilder accessory: () -> Accessory) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle().fill(Color.sbChampagne)
                Text("\(num)")
                    .font(SBFont.bodySmallBold)
                    .foregroundStyle(Color.sbGoldDk)
            }
            .frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(SBFont.bodySemibold)
                    .foregroundStyle(Color.sbCharcoal)
                Text(body)
                    .font(SBFont.caption)
                    .foregroundStyle(Color.sbWarm)
                    .fixedSize(horizontal: false, vertical: true)
                accessory()
            }
            Spacer(minLength: 0)
        }
    }

    // Convenience overload — steps without an accessory.
    private func instructionStep(num: Int, title: String, body: String, accessory: Void? = nil) -> some View {
        instructionStep(num: num, title: title, body: body) { EmptyView() }
    }

    private var downloadButton: some View {
        Button {
            shareCSV()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: didDownload ? "checkmark" : "arrow.down.to.line")
                    .font(.system(size: 12, weight: .semibold))
                Text(didDownload ? "Downloaded" : "Download \(rowCount) row\(rowCount == 1 ? "" : "s")")
                    .font(SBFont.bodySmallBold)
            }
            .foregroundStyle(didDownload ? Color.white : Color.sbGoldDk)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(didDownload ? Color(red: 0.61, green: 0.69, blue: 0.53) : Color.sbChampagne)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(rowCount == 0)
        .opacity(rowCount == 0 ? 0.5 : 1)
        .padding(.top, 4)
    }

    private var openCanvaButton: some View {
        Button {
            UIApplication.shared.open(canvaTemplateURL)
        } label: {
            HStack(spacing: 6) {
                // Canva logo — square viewBox so equal width/height keeps
                // it round; matches the brand mark on the web modal.
                Image("CanvaLogo")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 14, height: 14)
                Text("Open in Canva")
                    .font(SBFont.bodySmallBold)
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 11, weight: .semibold))
            }
            .foregroundStyle(Color.sbGoldDk)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Color.sbChampagne)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .padding(.top, 4)
    }

    // MARK: - Actions

    private func shareCSV() {
        let csv: String
        switch exportType {
        case .placeCards:
            csv = CanvaCSVBuilder.placeCardsCSV(plan: plan)
        case .tableCards:
            csv = CanvaCSVBuilder.tableCardsCSV(plan: plan)
        }
        let filename = CanvaCSVBuilder.filename(plan: plan, type: exportType)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        try? csv.write(to: url, atomically: true, encoding: .utf8)

        let activityVC = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let root = scene.windows.first?.rootViewController {
            // The Done button is in the sheet's nav bar; presenting the
            // activity sheet from the sheet's root keeps it on top.
            (root.presentedViewController ?? root).present(activityVC, animated: true)
        }
        didDownload = true
        HapticEngine.success()
    }
}

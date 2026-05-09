import SwiftUI

struct AddTableSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    let tableTypes: [(type: SeatTable.TableType, name: String, icon: String, seats: Int, description: String)] = [
        (.round, "Round Table", "circle", 8, "Classic round table"),
        (.oval, "Oval Table", "oval", 10, "Ellipse table"),
        (.rect, "Rectangular", "rectangle", 6, "Long table"),
        (.head, "Head Table", "person.2", 12, "Main table for the wedding party"),
        (.sweetheart, "Sweetheart", "heart", 2, "Intimate table for the couple"),
    ]

    var body: some View {
        VStack(spacing: 0) {
            // Custom header — avoids NavigationStack nav-bar/content overlap in sheets
            ZStack {
                Text("Add Table")
                    .font(SBFont.bodySemibold)
                    .foregroundStyle(Color.sbCharcoal)
                HStack {
                    Button("Cancel") { dismiss() }
                        .font(SBFont.body)
                        .foregroundStyle(Color.sbWarm)
                    Spacer()
                }
            }
            .padding(.horizontal, SBSpacing.screenMargin)
            .padding(.top, 16)
            .padding(.bottom, 12)

            Divider()

            ScrollView {
                VStack(spacing: 12) {
                    ForEach(tableTypes, id: \.type) { item in
                        TableTypeRow(
                            planId: appState.activePlan?.id,
                            type: item.type,
                            name: item.name,
                            icon: item.icon,
                            defaultSeats: item.seats,
                            description: item.description
                        ) { seats, sizeFt in
                            // Remember the user's last settings for this
                            // table type WITHIN this plan only — persisted
                            // before we dismiss so the next open of this
                            // sheet seeds with the same values.
                            AddTableSheet.persistLastSettings(
                                planId: appState.activePlan?.id,
                                type: item.type,
                                seats: seats,
                                sizeFt: sizeFt
                            )
                            addTable(type: item.type, seats: seats, name: item.name, sizeFt: sizeFt)
                            dismiss()
                        }
                    }
                }
                .padding(.horizontal, SBSpacing.screenMargin)
                .padding(.vertical, 16)
            }
        }
        .background(Color.sbIvory)
    }

    // MARK: - Per-plan persistence
    //
    // Each (planId, tableType) pair gets its own slot in
    // UserDefaults. Two keys per pair: ".seats" (Int) and
    // ".sizeFt" (Int, may be 0 to mean "no preset"). Scoped to
    // planId so per-event preferences don't leak across events
    // (Jayne explicitly asked for per-event scoping).

    fileprivate static func seatsKey(planId: String?, type: SeatTable.TableType) -> String? {
        guard let planId else { return nil }
        return "seatbee.addTable.\(planId).\(type.rawValue).seats"
    }

    fileprivate static func sizeFtKey(planId: String?, type: SeatTable.TableType) -> String? {
        guard let planId else { return nil }
        return "seatbee.addTable.\(planId).\(type.rawValue).sizeFt"
    }

    fileprivate static func loadLastSettings(planId: String?, type: SeatTable.TableType) -> (seats: Int?, sizeFt: Int?) {
        let defaults = UserDefaults.standard
        let savedSeats: Int? = {
            guard let key = seatsKey(planId: planId, type: type),
                  defaults.object(forKey: key) != nil else { return nil }
            let v = defaults.integer(forKey: key)
            return v > 0 ? v : nil
        }()
        let savedSizeFt: Int? = {
            guard let key = sizeFtKey(planId: planId, type: type),
                  defaults.object(forKey: key) != nil else { return nil }
            let v = defaults.integer(forKey: key)
            // 0 was used as a "no preset" sentinel for head /
            // sweetheart — treat as nil here so the row falls back
            // to its default sizing path.
            return v > 0 ? v : nil
        }()
        return (savedSeats, savedSizeFt)
    }

    fileprivate static func persistLastSettings(planId: String?, type: SeatTable.TableType, seats: Int, sizeFt: Int?) {
        let defaults = UserDefaults.standard
        if let key = seatsKey(planId: planId, type: type) {
            defaults.set(seats, forKey: key)
        }
        if let key = sizeFtKey(planId: planId, type: type) {
            defaults.set(sizeFt ?? 0, forKey: key)
        }
    }

    private func addTable(type: SeatTable.TableType, seats: Int, name: String, sizeFt: Int?) {
        guard var plan = appState.activePlan else { return }

        let tableCount = plan.tables.count
        let dims = TableDefaults.dimensions(for: type, sizeFt: sizeFt)
        // Default-name policy: shape-only types (round / oval / rect)
        // get the generic "Table N" — users were finding "Round Table 5"
        // wordy and shape-redundant since the canvas already shows the
        // shape. Functional types (head / sweetheart) keep their
        // descriptive names because they communicate role, not shape.
        let assignedName: String = {
            switch type {
            case .head:        return "Head Table"
            case .sweetheart:  return "Sweetheart"
            default:           return "Table \(tableCount + 1)"
            }
        }()
        let newTable = SeatTable(
            id: UUID().uuidString,
            name: assignedName,
            type: type,
            seats: seats,
            x: Double(100 + (tableCount % 3) * 150),
            y: Double(100 + (tableCount / 3) * 150),
            rotation: 0,
            assignments: [:],
            locked: false,
            // Web parity (App.jsx atmospheric redesign ad49273): all new
            // tables default to gold. The colour now reads as a thin inner
            // ring on top of the paper body, so monotone defaults give the
            // canvas a unified look — users can re-tint per table later.
            color: "#C9A961",
            width: dims.width,
            height: dims.height,
            diameter: dims.diameter,
            sweetShape: dims.sweetShape,
            oneSide: dims.oneSide
        )

        plan.tables.append(newTable)
        appState.activePlan = plan
        HapticEngine.success()

        Task {
            try? await appState.database.savePlanData(plan: plan)
        }
    }
}

// MARK: - One row per table type

/// Self-contained row with its own seat-count + size preset state.
/// Keeps the parent sheet a thin layout shell — and means each row's
/// stepper + preset chips are independent (changing the round
/// table's seat count doesn't reset the oval table's pick).
private struct TableTypeRow: View {
    let planId: String?
    let type: SeatTable.TableType
    let name: String
    let icon: String
    let defaultSeats: Int
    let description: String
    let onAdd: (_ seats: Int, _ sizeFt: Int?) -> Void

    @State private var seats: Int
    @State private var sizeFt: Int?

    init(planId: String?, type: SeatTable.TableType, name: String, icon: String,
         defaultSeats: Int, description: String,
         onAdd: @escaping (_ seats: Int, _ sizeFt: Int?) -> Void) {
        self.planId = planId
        self.type = type
        self.name = name
        self.icon = icon
        self.defaultSeats = defaultSeats
        self.description = description
        self.onAdd = onAdd
        // Seed from per-plan persisted values when present, so the
        // sheet remembers the last seats / size the user picked for
        // each table type within this event. Falls back to the
        // hardcoded defaults on first open of a fresh plan.
        let persisted = AddTableSheet.loadLastSettings(planId: planId, type: type)
        _seats = State(initialValue: persisted.seats ?? defaultSeats)
        _sizeFt = State(initialValue: persisted.sizeFt ?? TableDefaults.defaultSizeFt(for: type))
    }

    /// Sensible bounds for the seat stepper. Sweetheart caps at 2
    /// (it's a couple's table), the rest range 1–20 — matches what
    /// the post-create drawer allows.
    private var seatRange: ClosedRange<Int> {
        type == .sweetheart ? 2...2 : 1...20
    }

    private var sizePresets: [Int]? {
        TableDefaults.sizePresets(for: type)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(Color.sbChampagne)
                        .frame(width: 44, height: 44)
                    Image(systemName: icon)
                        .font(.system(size: 20))
                        .foregroundStyle(Color.sbGoldDk)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(name)
                        .font(SBFont.bodySemibold)
                        .foregroundStyle(Color.sbCharcoal)
                    Text(description)
                        .font(SBFont.caption)
                        .foregroundStyle(Color.sbWarm)
                }
                Spacer()
                Button {
                    onAdd(seats, sizeFt)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus")
                            .font(.system(size: 11, weight: .bold))
                        Text("Add")
                            .font(SBFont.inter(13, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(Color.sbGoldDk)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
            }

            // Seat stepper + (when applicable) size preset chip row.
            // Sweetheart locks at 2 → hide the stepper entirely so
            // users don't try to nudge it.
            HStack(spacing: 12) {
                if seatRange.upperBound > seatRange.lowerBound {
                    HStack(spacing: 6) {
                        Text("Seats")
                            .font(SBFont.caption)
                            .foregroundStyle(Color.sbWarm)
                        stepperButton(systemName: "minus", enabled: seats > seatRange.lowerBound) {
                            seats = max(seatRange.lowerBound, seats - 1)
                            HapticEngine.selection()
                        }
                        Text("\(seats)")
                            .font(SBFont.inter(13, weight: .semibold))
                            .foregroundStyle(Color.sbCharcoal)
                            .frame(minWidth: 18)
                            .contentTransition(.numericText())
                        stepperButton(systemName: "plus", enabled: seats < seatRange.upperBound) {
                            seats = min(seatRange.upperBound, seats + 1)
                            HapticEngine.selection()
                        }
                    }
                }

                if let presets = sizePresets {
                    if seatRange.upperBound > seatRange.lowerBound {
                        Spacer()
                    }
                    HStack(spacing: 6) {
                        Text("Size")
                            .font(SBFont.caption)
                            .foregroundStyle(Color.sbWarm)
                        ForEach(presets, id: \.self) { ft in
                            sizeChip(ft: ft, selected: sizeFt == ft) {
                                sizeFt = ft
                                HapticEngine.selection()
                            }
                        }
                    }
                }

                if sizePresets == nil { Spacer() }
            }
        }
        .padding(14)
        .background(Color.sbIvory2)
        .clipShape(RoundedRectangle(cornerRadius: SBRadius.card))
        .overlay(
            RoundedRectangle(cornerRadius: SBRadius.card)
                .strokeBorder(Color.sbLine, lineWidth: 1)
        )
    }

    private func stepperButton(systemName: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(enabled ? Color.sbCharcoal : Color.sbWarm2)
                .frame(width: 26, height: 26)
                .background(Color.white)
                .overlay(
                    Circle().strokeBorder(Color.sbLine, lineWidth: 1)
                )
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    private func sizeChip(ft: Int, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            // lineLimit(1) + fixedSize stops "10ft" from wrapping to
            // "10f / t" when the parent HStack runs tight; a non-
            // breaking space between the digits and "ft" keeps the
            // glyph cluster atomic for good measure.
            Text("\(ft)\u{00A0}ft")
                .font(SBFont.inter(11, weight: .semibold))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .foregroundStyle(selected ? Color.white : Color.sbCharcoal)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(selected ? Color.sbGoldDk : Color.white)
                .overlay(
                    Capsule().strokeBorder(selected ? Color.sbGoldDk : Color.sbLine, lineWidth: 1)
                )
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Web-parity table dimensions
// Mirrors web `TABLE_SIZES` in src/App.jsx (15px per foot). See PARITY.md.

enum TableDefaults {
    struct Dimensions {
        var width: Double?
        var height: Double?
        var diameter: Double?
        var sweetShape: String?
        var oneSide: Bool?
    }

    /// 15 px per foot — same scale web uses everywhere.
    static let pxPerFoot: Double = 15

    /// Size-preset options surfaced on the AddTable card. Round and
    /// oval take a "table size" preset (long-axis feet for oval,
    /// diameter for round); rectangular takes a length preset. Head
    /// / sweetheart use semantic dimensions and have no presets.
    static func sizePresets(for type: SeatTable.TableType) -> [Int]? {
        switch type {
        case .round, .oval, .rect:  return [4, 6, 8, 10]
        case .head, .sweetheart:    return nil
        }
    }

    /// Default size preset to seed the picker — matches the existing
    /// hardcoded dimensions for that type so the user lands on the
    /// most likely choice.
    static func defaultSizeFt(for type: SeatTable.TableType) -> Int? {
        switch type {
        case .round: return 5  // existing default 75px diameter ≈ 5ft, but presets are 4/6/8/10 — pick 6 as nearest
        case .oval:  return 8  // existing default 120×60 ≈ 8ft long
        case .rect:  return 6  // existing default 90×37.5 ≈ 6ft long
        case .head, .sweetheart: return nil
        }
    }

    static func dimensions(for type: SeatTable.TableType, sizeFt: Int? = nil) -> Dimensions {
        switch type {
        case .round:
            // Default 5ft (75px) when no preset selected, else the
            // selected feet value × 15 px/ft for the diameter.
            let ft = Double(sizeFt ?? 5)
            return Dimensions(diameter: ft * pxPerFoot)
        case .rect:
            // Length scales with the preset; height stays 2.5ft so
            // proportions stay banquet-style.
            let lenFt = Double(sizeFt ?? 6)
            return Dimensions(width: lenFt * pxPerFoot, height: 2.5 * pxPerFoot)
        case .head:
            return Dimensions(width: 270, height: 37.5, oneSide: true) // 18ft × 2.5ft
        case .sweetheart:
            return Dimensions(width: 60, height: 45, sweetShape: "heart") // 4ft × 3ft
        case .oval:
            // Long axis scales with preset; short axis follows a
            // ~2:1 ratio (web's existing 8ft × 4ft default).
            let longFt = Double(sizeFt ?? 8)
            return Dimensions(width: longFt * pxPerFoot, height: longFt * pxPerFoot / 2)
        }
    }
}

#Preview {
    AddTableSheet()
        .environment(AppState())
}

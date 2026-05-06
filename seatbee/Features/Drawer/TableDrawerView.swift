import SwiftUI

struct TableDrawerView: View {
    let table: SeatTable
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var selectedTab = "Layout"
    @State private var showRenameAlert = false
    @State private var renameText = ""

    private let tabs = ["Layout", "Seats", "Notes", "Tags"]

    // Web parity (src/App.jsx): SCALE = 15 px / foot.
    private let pxPerFoot: Double = 15

    var body: some View {
        VStack(spacing: 0) {
            // Header — table name + seated count (web parity, mirrors the
            // "4/8 guests seated" stat at the top of web's edit-table panel)
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(table.name)
                        .font(SBFont.displayMedium)
                        .foregroundStyle(Color.sbCharcoal)
                    Text("\(table.assignments.count)/\(table.seats) guests seated")
                        .font(SBFont.caption)
                        .foregroundStyle(table.assignments.count > 0 ? Color.sbGoldDk : Color.sbWarm)
                }
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color.sbWarm)
                        .frame(width: 32, height: 32)
                        .background(Color.sbIvory2)
                        .clipShape(Circle())
                }
            }
            .padding(.horizontal, SBSpacing.cardPadding)
            .padding(.top, SBSpacing.screenMargin)

            // Seat count stepper + table type
            HStack(spacing: 16) {
                // Seat stepper
                HStack(spacing: 0) {
                    Button { changeSeatCount(-1) } label: {
                        Image(systemName: "minus")
                            .font(.system(size: 14, weight: .bold))
                            .frame(width: 32, height: 32)
                            .background(Color.sbIvory2)
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)

                    Text("\(table.seats)")
                        .font(SBFont.statNumberSmall)
                        .foregroundStyle(Color.sbCharcoal)
                        .frame(width: 40)
                        .contentTransition(.numericText())

                    Button { changeSeatCount(1) } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 14, weight: .bold))
                            .frame(width: 32, height: 32)
                            .background(Color.sbIvory2)
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)

                    Text("seats")
                        .font(SBFont.caption)
                        .foregroundStyle(Color.sbWarm)
                        .padding(.leading, 4)
                }

                Spacer()

                // Table type
                Menu {
                    ForEach(SeatTable.TableType.allCases, id: \.self) { type in
                        Button {
                            changeTableType(type)
                        } label: {
                            Label(type.rawValue.capitalized, systemImage: typeIcon(type))
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: typeIcon(table.type))
                            .font(.system(size: 12))
                        Text(table.type.rawValue.capitalized)
                            .font(SBFont.inter(12, weight: .semibold))
                    }
                    .foregroundStyle(Color.sbGoldDk)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.sbChampagne)
                    .clipShape(RoundedRectangle(cornerRadius: SBRadius.small))
                }
            }
            .padding(.horizontal, SBSpacing.cardPadding)
            .padding(.top, 12)

            // Action strip
            actionStrip
                .padding(.top, 12)

            // Tabs
            tabRow
                .padding(.top, SBSpacing.screenMargin)

            // Content
            ScrollView {
                switch selectedTab {
                case "Seats":
                    seatsContent
                case "Layout":
                    layoutContent
                case "Notes":
                    notesContent
                case "Tags":
                    tagsContent
                default:
                    EmptyView()
                }
            }
            .padding(.top, SBSpacing.lg)
        }
        .background(Color.sbIvory)
        .alert("Rename Table", isPresented: $showRenameAlert) {
            TextField("Table name", text: $renameText)
            Button("Save") { renameTable() }
            Button("Cancel", role: .cancel) {}
        }
        .onAppear { renameText = table.name }
    }

    // MARK: - Action Strip

    private var actionStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                actionButton(icon: "pencil", label: "Rename") {
                    showRenameAlert = true
                }
                actionButton(icon: table.locked == true ? "lock.fill" : "lock", label: table.locked == true ? "Unlock" : "Lock") {
                    toggleLock()
                }
                actionButton(icon: "doc.on.doc", label: "Duplicate") {
                    duplicateTable()
                }
                actionButton(icon: "plus.circle", label: "Add Seat") {
                    addSeat()
                }
                actionButton(icon: "trash", label: "Delete") {
                    deleteTable()
                }
            }
            .padding(.horizontal, SBSpacing.cardPadding)
        }
    }

    private func actionButton(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button {
            action()
            HapticEngine.light()
        } label: {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 18))
                    .foregroundStyle(Color.sbCharcoal)
                Text(label.uppercased())
                    .font(SBFont.capsLabel)
                    .foregroundStyle(Color.sbWarm)
            }
            .frame(width: 64, height: 56)
            .background(Color.sbIvory2)
            .clipShape(RoundedRectangle(cornerRadius: SBRadius.small))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Tabs

    private var tabRow: some View {
        HStack(spacing: 24) {
            ForEach(tabs, id: \.self) { tab in
                Button {
                    withAnimation(.seatbee) { selectedTab = tab }
                } label: {
                    VStack(spacing: 6) {
                        Text(tab)
                            .font(SBFont.bodySemibold)
                            .foregroundStyle(selectedTab == tab ? Color.sbCharcoal : Color.sbWarm)
                        Rectangle()
                            .fill(selectedTab == tab ? Color.sbGold : Color.clear)
                            .frame(height: 2)
                    }
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(.horizontal, SBSpacing.cardPadding)
    }

    // MARK: - Seats Content

    private var seatsContent: some View {
        VStack(spacing: 6) {
            ForEach(0..<table.seats, id: \.self) { index in
                HStack(spacing: 10) {
                    Image(systemName: "line.3.horizontal")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.sbWarm2)

                    ZStack {
                        Circle()
                            .fill(Color.sbGold)
                            .frame(width: 22, height: 22)
                        Text("\(index + 1)")
                            .font(SBFont.inter(10, weight: .bold))
                            .foregroundStyle(.white)
                    }

                    // Show assigned guest name or "Seat N"
                    let guestId = table.assignments.first { $0.value == index }?.key
                    let guest = appState.activePlan?.guests.first { $0.id == guestId }

                    Text(guest?.displayName ?? "Seat \(index + 1)")
                        .font(SBFont.bodySmall)
                        .foregroundStyle(guest != nil ? Color.sbCharcoal : Color.sbWarm)

                    Spacer()
                }
                .padding(.vertical, 8)
                .padding(.horizontal, SBSpacing.cardPadding)
            }

            // Add seat button
            Button {
                addSeat()
                HapticEngine.light()
            } label: {
                HStack {
                    Image(systemName: "plus")
                    Text("Add seat")
                }
                .font(SBFont.bodySemibold)
                .foregroundStyle(Color.sbGoldDk)
                .frame(maxWidth: .infinity)
                .padding(12)
                .overlay(
                    RoundedRectangle(cornerRadius: SBRadius.button)
                        .strokeBorder(Color.sbLine2, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                )
            }
            .buttonStyle(.plain)
            .padding(.horizontal, SBSpacing.cardPadding)
            .padding(.top, SBSpacing.lg)
        }
    }

    // MARK: - Notes & Tags

    private var notesContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("No notes yet")
                .font(SBFont.body)
                .foregroundStyle(Color.sbWarm)
                .padding(SBSpacing.cardPadding)
        }
    }

    private var tagsContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("No tags yet")
                .font(SBFont.body)
                .foregroundStyle(Color.sbWarm)
                .padding(SBSpacing.cardPadding)
        }
    }

    // MARK: - Layout Tab Content (web parity)

    private var layoutContent: some View {
        VStack(alignment: .leading, spacing: SBSpacing.lg) {
            shapeSection
            if table.type == .sweetheart {
                sweetheartShapeSection
            }
            if table.type == .rect || table.type == .head {
                seatingLayoutSection
            }
            sizeSection
            rotationSection
        }
        .padding(.horizontal, SBSpacing.cardPadding)
        .padding(.bottom, SBSpacing.lg)
    }

    private var shapeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("SHAPE")
            // Two rows of three: keeps everything readable on narrow phones.
            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    shapeButton("Round", type: .round)
                    shapeButton("Oval", type: .oval)
                    shapeButton("Rect", type: .rect)
                }
                HStack(spacing: 8) {
                    shapeButton("Head", type: .head)
                    shapeButton("Sweet", type: .sweetheart)
                    Spacer().frame(maxWidth: .infinity)
                }
            }
        }
    }

    private func shapeButton(_ label: String, type: SeatTable.TableType) -> some View {
        let active = table.type == type
        return Button {
            changeTableType(type)
        } label: {
            Text(label)
                .font(SBFont.bodySemibold)
                .foregroundStyle(active ? Color.white : Color.sbCharcoal)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(active ? Color.sbGold : Color.sbIvory2)
                .clipShape(RoundedRectangle(cornerRadius: SBRadius.small))
        }
        .buttonStyle(.plain)
    }

    private var sweetheartShapeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("SWEETHEART STYLE")
            HStack(spacing: 8) {
                sweetShapeButton("Heart", value: "heart")
                sweetShapeButton("Oval", value: "oval")
                sweetShapeButton("Rect", value: "rect")
            }
        }
    }

    private func sweetShapeButton(_ label: String, value: String) -> some View {
        let active = (table.sweetShape ?? "heart").lowercased() == value
        return Button {
            mutateTable { $0.sweetShape = value }
        } label: {
            Text(label)
                .font(SBFont.bodySemibold)
                .foregroundStyle(active ? Color.white : Color.sbCharcoal)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(active ? Color.sbGold : Color.sbIvory2)
                .clipShape(RoundedRectangle(cornerRadius: SBRadius.small))
        }
        .buttonStyle(.plain)
    }

    private var seatingLayoutSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("SEATING LAYOUT")
            HStack(spacing: 8) {
                seatingLayoutButton("One Side", oneSide: true)
                seatingLayoutButton("Two Sides", oneSide: false)
            }
            // All Sides / Banquet require the `seatingLayout` field which iOS
            // doesn't model yet. See PARITY.md outstanding gaps.
        }
    }

    private func seatingLayoutButton(_ label: String, oneSide: Bool) -> some View {
        let active = (table.oneSide ?? false) == oneSide
        return Button {
            mutateTable { $0.oneSide = oneSide }
        } label: {
            Text(label)
                .font(SBFont.bodySemibold)
                .foregroundStyle(active ? Color.white : Color.sbCharcoal)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(active ? Color.sbGold : Color.sbIvory2)
                .clipShape(RoundedRectangle(cornerRadius: SBRadius.small))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var sizeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel("SIZE")
            switch table.type {
            case .round:
                // Discrete size presets — mirrors web (App.jsx GenPanel /
                // table edit screenshot). 4–8ft covers the realistic range
                // for round tables. Tapping a preset snaps the slider.
                sizePresetButtons(footValues: [4, 5, 6, 7, 8],
                                  currentPx: Double(table.diameter ?? 90)) { v in
                    mutateTable { $0.diameter = v }
                }
                sizeSlider(label: "D",
                           value: bindingNoSave(get: { Double(table.diameter ?? 90) },
                                                set: { v in mutateTable(save: false) { $0.diameter = v } }),
                           range: 60...200, step: 5)
            case .oval:
                // Oval size: presets snap the WIDTH; height is adjusted
                // separately via slider below.
                sizePresetButtons(footValues: [6, 7, 8, 9, 10],
                                  currentPx: Double(table.width ?? 120)) { v in
                    mutateTable { $0.width = v }
                }
                sizeSlider(label: "W",
                           value: bindingNoSave(get: { Double(table.width ?? 120) },
                                                set: { v in mutateTable(save: false) { $0.width = v } }),
                           range: 60...300, step: 10)
                sizeSlider(label: "H",
                           value: bindingNoSave(get: { Double(table.height ?? 60) },
                                                set: { v in mutateTable(save: false) { $0.height = v } }),
                           range: 40...200, step: 5)
            case .rect, .head, .sweetheart:
                sizeSlider(label: "W",
                           value: bindingNoSave(get: { Double(table.width ?? 100) },
                                                set: { v in mutateTable(save: false) { $0.width = v } }),
                           range: 60...2000, step: 10)
                sizeSlider(label: "H",
                           value: bindingNoSave(get: { Double(table.height ?? 50) },
                                                set: { v in mutateTable(save: false) { $0.height = v } }),
                           range: 30...150, step: 5)
                if table.type == .rect {
                    Button {
                        let size = max(table.width ?? 100, table.height ?? 50)
                        mutateTable { $0.width = size; $0.height = size }
                    } label: {
                        Text("Make Square")
                            .font(SBFont.bodySemibold)
                            .foregroundStyle(Color.sbCharcoal)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(Color.sbIvory2)
                            .clipShape(RoundedRectangle(cornerRadius: SBRadius.small))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    /// Row of preset-foot buttons that snap the active size dimension.
    /// Selected when `currentPx` matches the foot value (within ±2px to
    /// account for slider increments).
    private func sizePresetButtons(footValues: [Int], currentPx: Double, onSelect: @escaping (Double) -> Void) -> some View {
        HStack(spacing: 6) {
            ForEach(footValues, id: \.self) { ft in
                let targetPx = Double(ft) * pxPerFoot
                let isActive = abs(currentPx - targetPx) < 2
                Button {
                    onSelect(targetPx)
                    HapticEngine.selection()
                } label: {
                    Text("\(ft)ft")
                        .font(SBFont.bodySemibold)
                        .foregroundStyle(isActive ? Color.white : Color.sbCharcoal)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(isActive ? Color.sbGold : Color.sbIvory2)
                        .clipShape(RoundedRectangle(cornerRadius: SBRadius.small))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func sizeSlider(label: String, value: Binding<Double>, range: ClosedRange<Double>, step: Double) -> some View {
        HStack(spacing: 12) {
            Text(label)
                .font(SBFont.bodySemibold)
                .foregroundStyle(Color.sbWarm)
                .frame(width: 18, alignment: .leading)
            Slider(value: value, in: range, step: step,
                   onEditingChanged: { editing in
                       if !editing, let plan = appState.activePlan { savePlan(plan) }
                   })
            .tint(Color.sbGold)
            Text("\((value.wrappedValue / pxPerFoot).formatted(.number.precision(.fractionLength(1)))) ft")
                .font(SBFont.bodySmall)
                .foregroundStyle(Color.sbCharcoal)
                .frame(width: 56, alignment: .trailing)
                .monospacedDigit()
        }
    }

    private var rotationSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                sectionLabel("ROTATION")
                Spacer()
                Text("\(Int(table.rotation ?? 0))°")
                    .font(SBFont.bodySemibold)
                    .foregroundStyle(Color.sbCharcoal)
                    .monospacedDigit()
            }
            HStack(spacing: 8) {
                rotationStepButton("−15°") { adjustRotation(by: -15) }
                Slider(value: bindingNoSave(get: { table.rotation ?? 0 },
                                            set: { v in mutateTable(save: false) { $0.rotation = v } }),
                       in: 0...360, step: 5,
                       onEditingChanged: { editing in
                           if !editing, let plan = appState.activePlan { savePlan(plan) }
                       })
                .tint(Color.sbGold)
                rotationStepButton("+15°") { adjustRotation(by: 15) }
            }
        }
    }

    private func rotationStepButton(_ label: String, action: @escaping () -> Void) -> some View {
        Button {
            action()
            HapticEngine.selection()
        } label: {
            Text(label)
                .font(SBFont.bodySemibold)
                .foregroundStyle(Color.sbCharcoal)
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
                .background(Color.sbIvory2)
                .clipShape(RoundedRectangle(cornerRadius: SBRadius.small))
        }
        .buttonStyle(.plain)
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(SBFont.capsLabel)
            .foregroundStyle(Color.sbWarm)
    }

    // MARK: - Mutation helpers

    private func mutateTable(save: Bool = true, _ change: (inout SeatTable) -> Void) {
        guard var plan = appState.activePlan,
              let idx = plan.tables.firstIndex(where: { $0.id == table.id }) else { return }
        change(&plan.tables[idx])
        appState.activePlan = plan
        if save { savePlan(plan) }
    }

    private func bindingNoSave(get: @escaping () -> Double, set: @escaping (Double) -> Void) -> Binding<Double> {
        Binding(get: get, set: set)
    }

    private func adjustRotation(by delta: Double) {
        let current = table.rotation ?? 0
        let next = ((current + delta).truncatingRemainder(dividingBy: 360) + 360)
            .truncatingRemainder(dividingBy: 360)
        mutateTable { $0.rotation = next }
    }

    // MARK: - Actions

    private func renameTable() {
        guard var plan = appState.activePlan,
              let idx = plan.tables.firstIndex(where: { $0.id == table.id }) else { return }
        plan.tables[idx].name = renameText
        appState.activePlan = plan
        savePlan(plan)
    }

    private func toggleLock() {
        guard var plan = appState.activePlan,
              let idx = plan.tables.firstIndex(where: { $0.id == table.id }) else { return }
        plan.tables[idx].locked = !(plan.tables[idx].locked ?? false)
        appState.activePlan = plan
        savePlan(plan)
    }

    private func duplicateTable() {
        guard var plan = appState.activePlan,
              let idx = plan.tables.firstIndex(where: { $0.id == table.id }) else { return }
        var newTable = plan.tables[idx]
        newTable = SeatTable(
            id: UUID().uuidString,
            name: "\(table.name) copy",
            type: table.type,
            seats: table.seats,
            x: table.x + 80,
            y: table.y + 80,
            rotation: table.rotation,
            assignments: [:],
            locked: false,
            color: table.color,
            width: table.width,
            height: table.height,
            diameter: table.diameter,
            sweetShape: table.sweetShape,
            oneSide: table.oneSide
        )
        plan.tables.append(newTable)
        appState.activePlan = plan
        savePlan(plan)
        HapticEngine.success()
    }

    private func addSeat() {
        guard var plan = appState.activePlan,
              let idx = plan.tables.firstIndex(where: { $0.id == table.id }) else { return }
        plan.tables[idx].seats += 1
        appState.activePlan = plan
        savePlan(plan)
    }

    private func changeSeatCount(_ delta: Int) {
        guard var plan = appState.activePlan,
              let idx = plan.tables.firstIndex(where: { $0.id == table.id }) else { return }
        var t = plan.tables[idx]
        // Web parity: min 2; max 12 round, 200 rect/head, 2 sweetheart.
        let maxSeats: Int = {
            switch t.type {
            case .sweetheart: return 2
            case .round:      return 12
            case .oval:       return 14   // ellipse perimeter > round, slightly higher
            case .rect, .head: return 200
            }
        }()
        let newCount = max(2, min(maxSeats, t.seats + delta))
        guard newCount != t.seats else { return }
        t.seats = newCount

        // Web parity: when growing seats on rect/head, expand width to keep
        // ~1.5 ft (22.5 px at 15 px/ft) per person per side.
        if delta > 0, t.type == .rect || t.type == .head {
            let seatsPerSide: Int = (t.oneSide == true) ? newCount : Int(ceil(Double(newCount) / 2.0))
            let minWidth = Double(seatsPerSide) * 22.5
            t.width = max(t.width ?? 100, min(2000, minWidth))
        }

        plan.tables[idx] = t
        appState.activePlan = plan
        savePlan(plan)
        HapticEngine.selection()
    }

    // Web parity: src/App.jsx SHAPE button onClick handlers preserve dimensions
    // across type changes (e.g. round→rect uses diameter as new width) and
    // clear fields that don't apply to the new type. HEAD also defaults
    // oneSide=true if previously unset.
    private func changeTableType(_ type: SeatTable.TableType) {
        guard var plan = appState.activePlan,
              let idx = plan.tables.firstIndex(where: { $0.id == table.id }) else { return }
        var t = plan.tables[idx]
        t.type = type
        switch type {
        case .round:
            t.diameter = t.width ?? t.diameter ?? 90
            t.width = nil
            t.height = nil
            t.oneSide = nil
        case .rect:
            t.width = t.diameter ?? t.width ?? 100
            t.height = t.height ?? 50
            t.diameter = nil
            t.oneSide = nil
        case .head:
            t.width = t.diameter ?? t.width ?? 280
            t.height = t.height ?? 50
            t.diameter = nil
            if t.oneSide == nil { t.oneSide = true }
        case .sweetheart:
            t.width = t.width ?? 60
            t.height = t.height ?? 45
            t.diameter = nil
            t.oneSide = nil
            if t.sweetShape == nil { t.sweetShape = "heart" }
        case .oval:
            // Oval default 8ft × 4ft (=120×60 at scale 15) — App.jsx:8453.
            // Reuse existing diameter as width if present so converting
            // round → oval feels continuous.
            t.width = t.diameter ?? t.width ?? 120
            t.height = t.height ?? 60
            t.diameter = nil
            t.oneSide = nil
        }
        plan.tables[idx] = t
        appState.activePlan = plan
        savePlan(plan)
        HapticEngine.selection()
    }

    private func typeIcon(_ type: SeatTable.TableType) -> String {
        switch type {
        case .round:      return "circle"
        case .rect:       return "rectangle"
        case .head:       return "person.2"
        case .sweetheart: return "heart"
        case .oval:       return "oval"
        }
    }

    private func deleteTable() {
        guard var plan = appState.activePlan else { return }
        plan.tables.removeAll { $0.id == table.id }
        appState.activePlan = plan
        savePlan(plan)
        dismiss()
    }

    private func savePlan(_ plan: SeatingPlan) {
        Task {
            do {
                try await appState.database.savePlanData(plan: plan)
            } catch {
                print("[Drawer] Save failed: \(error)")
            }
        }
    }
}

#Preview {
    TableDrawerView(table: SeatTable(
        id: "1", name: "Table 5", type: .round, seats: 8,
        x: 100, y: 100, assignments: [:], color: "#9CAF88"
    ))
    .environment(AppState())
}

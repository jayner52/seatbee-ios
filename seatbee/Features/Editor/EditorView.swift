import SwiftUI

struct EditorView: View {
    @Environment(AppState.self) private var appState
    @State private var selectedTableId: String?
    @State private var selectedObjectId: String?
    @State private var showDrawer = false
    @State private var showGuestPicker = false
    @State private var showAddTable = false
    @State private var showAddVenueObject = false
    @State private var showRoomSetup = false
    @State private var showDetailSheet = false
    @State private var showDeleteConfirm = false
    @State private var assigningSeatIndex: Int?

    // Canvas viewport — use CGPoint for cleaner math
    @State private var viewOffset: CGPoint = .zero
    @State private var viewScale: CGFloat = 0.8
    @State private var gestureStartOffset: CGPoint = .zero
    @State private var gestureStartScale: CGFloat = 0.8

    // Drag tracking — store position at drag start to avoid cumulative bugs
    @State private var isDraggingItem = false
    @State private var dragItemId: String?
    @State private var dragItemType: String? // "table" or "object"
    @State private var dragStartPos: CGPoint = .zero

    private var plan: SeatingPlan? { appState.activePlan }
    private var tables: [SeatTable] { plan?.tables ?? [] }
    private var objects: [RoomObject] { plan?.objects ?? [] }
    private var selectedTable: SeatTable? {
        tables.first { $0.id == selectedTableId }
    }

    var body: some View {
        ZStack {
            if plan == nil {
                emptyState
            } else {
                canvas
                    .ignoresSafeArea(.all, edges: .bottom)

                VStack {
                    topBar
                    Spacer()
                }

                VStack {
                    Spacer()
                    bottomBar
                }
            }
        }
        .background(Color.sbIvory2)
        .sheet(isPresented: $showDetailSheet) {
            if let table = selectedTable {
                tableDetailSheet(table)
                    .presentationDetents([.fraction(0.45), .large])
                    .presentationDragIndicator(.visible)
                    .presentationBackgroundInteraction(.enabled(upThrough: .fraction(0.45)))
                    .presentationCornerRadius(24)
            }
        }
        .sheet(isPresented: $showDrawer) {
            if let table = selectedTable {
                TableDrawerView(table: table)
                    .environment(appState)
                    .presentationDetents([.fraction(0.82)])
                    .presentationDragIndicator(.visible)
                    .presentationCornerRadius(24)
            }
        }
        .sheet(isPresented: $showGuestPicker) {
            if let plan {
                GuestPickerSheet(guests: plan.guests, tables: plan.tables) { guest in
                    assignGuest(guest)
                }
                .environment(appState)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
            }
        }
        .sheet(isPresented: $showAddTable) {
            AddTableSheet()
                .environment(appState)
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showAddVenueObject) {
            VenueObjectsSheet()
                .environment(appState)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showRoomSetup) {
            RoomSetupSheet()
                .environment(appState)
        }
        .alert("Delete object?", isPresented: $showDeleteConfirm) {
            Button("Delete", role: .destructive) {
                if let id = selectedObjectId { deleteObjectById(id) }
            }
            Button("Cancel", role: .cancel) {}
        }
        .task {
            if appState.activePlan == nil {
                let plans = (try? await appState.database.fetchPlans()) ?? []
                if let first = plans.first { appState.activePlan = first }
            }
            if selectedTableId == nil, let first = tables.first {
                selectedTableId = first.id
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .selectTable)) { notification in
            if let tableId = notification.userInfo?["tableId"] as? String {
                withAnimation(.seatbee) {
                    selectedTableId = tableId
                    showDetailSheet = true
                }
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "square.grid.2x2")
                .font(.system(size: 40))
                .foregroundStyle(Color.sbWarm2)
            Text("Select a plan from the Plans tab")
                .font(SBFont.body)
                .foregroundStyle(Color.sbWarm)
            SBButton(title: "Go to Plans", icon: "square.grid.2x2", variant: .gold) {
                appState.selectedTab = .plans
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .background(Color.sbIvory)
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack(spacing: 10) {
            Text(plan?.name ?? "")
                .font(SBFont.displayNav)
                .foregroundStyle(Color.sbCharcoal)
                .lineLimit(1)

            Spacer()

            Button { appState.undo(); HapticEngine.light() } label: {
                Image(systemName: "arrow.uturn.backward")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(appState.undoManager.canUndo ? Color.sbCharcoal : Color.sbWarm2)
                    .frame(width: 34, height: 34)
                    .background(.ultraThinMaterial)
                    .clipShape(Circle())
            }
            .disabled(!appState.undoManager.canUndo)

            Button { appState.redo(); HapticEngine.light() } label: {
                Image(systemName: "arrow.uturn.forward")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(appState.undoManager.canRedo ? Color.sbCharcoal : Color.sbWarm2)
                    .frame(width: 34, height: 34)
                    .background(.ultraThinMaterial)
                    .clipShape(Circle())
            }
            .disabled(!appState.undoManager.canRedo)

            Button { showRoomSetup = true } label: {
                Image(systemName: "square.dashed")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color.sbGoldDk)
                    .frame(width: 34, height: 34)
                    .background(.ultraThinMaterial)
                    .clipShape(Circle())
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 6)
        .background(
            LinearGradient(colors: [Color.sbIvory2, Color.sbIvory2.opacity(0)], startPoint: .top, endPoint: .bottom)
        )
    }

    // MARK: - Bottom Bar

    private var bottomBar: some View {
        VStack(spacing: 0) {
            // Selected item pill
            if let table = selectedTable {
                Button { showDetailSheet = true } label: {
                    HStack(spacing: 10) {
                        SBTableGraphic(totalSeats: table.seats, filledSeats: table.filledCount, size: 36)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(table.name)
                                .font(SBFont.bodySmallBold)
                                .foregroundStyle(Color.sbCharcoal)
                            Text("\(table.filledCount)/\(table.seats) seated")
                                .font(SBFont.caption)
                                .foregroundStyle(Color.sbWarm)
                        }
                        Spacer()
                        Image(systemName: "chevron.up")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(Color.sbGoldDk)
                    }
                    .padding(14)
                    .background(.regularMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: SBRadius.card))
                    .shadow(color: Color.black.opacity(0.08), radius: 12, x: 0, y: -4)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
            } else if let objId = selectedObjectId, let obj = objects.first(where: { $0.id == objId }) {
                HStack(spacing: 10) {
                    let def = venueObjectTypes.first { $0.type == obj.type }
                    Image(systemName: def?.icon ?? "square")
                        .font(.system(size: 18))
                        .foregroundStyle(Color.sbGoldDk)
                    Text(obj.name)
                        .font(SBFont.bodySmallBold)
                        .foregroundStyle(Color.sbCharcoal)
                    Spacer()
                    Button {
                        showDeleteConfirm = true
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 14))
                            .foregroundStyle(Color.sbError)
                            .frame(width: 34, height: 34)
                            .background(.regularMaterial)
                            .clipShape(Circle())
                    }
                }
                .padding(14)
                .background(.regularMaterial)
                .clipShape(RoundedRectangle(cornerRadius: SBRadius.card))
                .shadow(color: Color.black.opacity(0.08), radius: 12, x: 0, y: -4)
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
            }

            // Action bar
            HStack(spacing: 16) {
                Menu {
                    Button { showAddTable = true } label: {
                        Label("Add Table", systemImage: "circle")
                    }
                    Button { showAddVenueObject = true } label: {
                        Label("Venue Object", systemImage: "square.on.square")
                    }
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(Color.sbCharcoal)
                        .clipShape(Circle())
                        .shadow(color: Color.black.opacity(0.15), radius: 8, x: 0, y: 4)
                }

                Spacer()

                // Zoom
                HStack(spacing: 4) {
                    Button {
                        withAnimation(.seatbee) { viewScale = max(0.3, viewScale / 1.3); gestureStartScale = viewScale }
                    } label: {
                        Image(systemName: "minus").font(.system(size: 13, weight: .bold))
                            .frame(width: 34, height: 34).background(.regularMaterial).clipShape(Circle())
                    }
                    Text("\(Int(viewScale * 100))%")
                        .font(SBFont.capsLabel).foregroundStyle(Color.sbWarm).frame(width: 40)
                    Button {
                        withAnimation(.seatbee) { viewScale = min(3.0, viewScale * 1.3); gestureStartScale = viewScale }
                    } label: {
                        Image(systemName: "plus").font(.system(size: 13, weight: .bold))
                            .frame(width: 34, height: 34).background(.regularMaterial).clipShape(Circle())
                    }
                    Button {
                        withAnimation(.seatbee) { viewScale = 0.8; gestureStartScale = 0.8; viewOffset = .zero; gestureStartOffset = .zero }
                    } label: {
                        Image(systemName: "arrow.counterclockwise").font(.system(size: 11, weight: .medium))
                            .frame(width: 34, height: 34).background(.regularMaterial).clipShape(Circle())
                    }
                }
                .buttonStyle(.plain)

                Spacer()

                // AI pill
                Button { appState.selectedTab = .ai } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "sparkles").font(.system(size: 11, weight: .semibold))
                        Text("AI seat \(unseatedCount)").font(SBFont.inter(11, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(Color.sbGold)
                    .clipShape(Capsule())
                    .shadow(color: Color.sbGold.opacity(0.3), radius: 8, x: 0, y: 3)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 90)
        }
    }

    // MARK: - Canvas

    private var canvas: some View {
        GeometryReader { geo in
            let cx = geo.size.width / 2
            let cy = geo.size.height / 2

            ZStack {
                Color.sbIvory2.overlay(dotPattern)

                // --- Tables ---
                ForEach(tables) { table in
                    let pos = worldToScreen(x: table.x, y: table.y, cx: cx, cy: cy)
                    let size = max(40, 70 * viewScale)

                    SBTableGraphic(
                        totalSeats: table.seats,
                        filledSeats: table.filledCount,
                        label: table.name,
                        size: size,
                        isSelected: table.id == selectedTableId
                    )
                    .position(x: pos.x, y: pos.y)
                    .highPriorityGesture(
                        DragGesture(minimumDistance: 8)
                            .onChanged { value in
                                if !isDraggingItem || dragItemId != table.id {
                                    // Drag started — capture start position
                                    isDraggingItem = true
                                    dragItemId = table.id
                                    dragItemType = "table"
                                    dragStartPos = CGPoint(x: table.x, y: table.y)
                                }
                                // Calculate new position from start + delta
                                let newX = dragStartPos.x + Double(value.translation.width / viewScale)
                                let newY = dragStartPos.y + Double(value.translation.height / viewScale)
                                updateTablePosition(id: table.id, x: newX, y: newY)
                            }
                            .onEnded { _ in
                                isDraggingItem = false
                                dragItemId = nil
                                savePositions()
                                HapticEngine.light()
                            }
                    )
                    .simultaneousGesture(
                        TapGesture().onEnded {
                            guard !isDraggingItem else { return }
                            selectedObjectId = nil
                            withAnimation(.seatbee) {
                                selectedTableId = table.id
                                showDetailSheet = true
                            }
                            HapticEngine.selection()
                        }
                    )
                    .zIndex(table.id == dragItemId ? 100 : (table.id == selectedTableId ? 10 : 1))
                }

                // --- Venue Objects ---
                ForEach(objects) { obj in
                    let pos = worldToScreen(x: obj.x, y: obj.y, cx: cx, cy: cy)
                    let w = max(30, obj.width * viewScale)
                    let h = max(20, obj.height * viewScale)
                    let def = venueObjectTypes.first { $0.type == obj.type }
                    let isSelected = obj.id == selectedObjectId

                    venueObjectView(obj: obj, def: def, width: w, height: h, selected: isSelected)
                        .position(x: pos.x, y: pos.y)
                        .highPriorityGesture(
                            DragGesture(minimumDistance: 8)
                                .onChanged { value in
                                    if !isDraggingItem || dragItemId != obj.id {
                                        isDraggingItem = true
                                        dragItemId = obj.id
                                        dragItemType = "object"
                                        dragStartPos = CGPoint(x: obj.x, y: obj.y)
                                    }
                                    let newX = dragStartPos.x + Double(value.translation.width / viewScale)
                                    let newY = dragStartPos.y + Double(value.translation.height / viewScale)
                                    updateObjectPosition(id: obj.id, x: newX, y: newY)
                                }
                                .onEnded { _ in
                                    isDraggingItem = false
                                    dragItemId = nil
                                    savePositions()
                                    HapticEngine.light()
                                }
                        )
                        .simultaneousGesture(
                            TapGesture().onEnded {
                                guard !isDraggingItem else { return }
                                selectedTableId = nil
                                withAnimation(.seatbee) {
                                    selectedObjectId = obj.id
                                }
                                HapticEngine.selection()
                            }
                        )
                        .zIndex(obj.id == dragItemId ? 100 : (isSelected ? 10 : 0))
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 15)
                    .onChanged { value in
                        guard !isDraggingItem else { return }
                        viewOffset = CGPoint(
                            x: gestureStartOffset.x + value.translation.width,
                            y: gestureStartOffset.y + value.translation.height
                        )
                    }
                    .onEnded { _ in
                        gestureStartOffset = viewOffset
                    }
            )
            .simultaneousGesture(
                MagnifyGesture()
                    .onChanged { value in
                        viewScale = max(0.3, min(3.0, gestureStartScale * value.magnification))
                    }
                    .onEnded { _ in
                        gestureStartScale = viewScale
                    }
            )
            .onTapGesture {
                // Tap on empty canvas — deselect everything
                withAnimation(.seatbee) {
                    selectedTableId = nil
                    selectedObjectId = nil
                    showDetailSheet = false
                }
            }
        }
    }

    // MARK: - Coordinate Conversion

    private func worldToScreen(x: Double, y: Double, cx: CGFloat, cy: CGFloat) -> CGPoint {
        CGPoint(
            x: (x - 200) * viewScale + cx + viewOffset.x,
            y: (y - 200) * viewScale + cy + viewOffset.y
        )
    }

    // MARK: - Venue Object View

    private func venueObjectView(obj: RoomObject, def: VenueObjectDef?, width: CGFloat, height: CGFloat, selected: Bool) -> some View {
        RoundedRectangle(cornerRadius: max(4, 8 * viewScale))
            .fill(Color(hex: def?.color ?? "#8B8680").opacity(0.85))
            .frame(width: width, height: height)
            .overlay(
                VStack(spacing: 2) {
                    Image(systemName: def?.icon ?? "square")
                        .font(.system(size: max(8, 16 * viewScale)))
                        .foregroundStyle(def?.color == "#2D2D2D" ? .white : Color.sbCharcoal.opacity(0.7))
                    if viewScale > 0.5 {
                        Text(obj.name)
                            .font(.system(size: max(6, 10 * viewScale), weight: .medium))
                            .foregroundStyle(def?.color == "#2D2D2D" ? .white : Color.sbCharcoal)
                            .lineLimit(1)
                    }
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: max(4, 8 * viewScale))
                    .strokeBorder(Color.sbGold, lineWidth: selected ? 2 : 0)
            )
            .shadow(color: Color.black.opacity(selected ? 0.2 : 0.1), radius: selected ? 8 : 4, x: 0, y: 2)
    }

    // MARK: - Dot Pattern

    private var dotPattern: some View {
        Canvas { context, size in
            let spacing: CGFloat = 18
            let dotSize: CGFloat = 2
            for x in stride(from: spacing, through: size.width, by: spacing) {
                for y in stride(from: spacing, through: size.height, by: spacing) {
                    let rect = CGRect(x: x - dotSize/2, y: y - dotSize/2, width: dotSize, height: dotSize)
                    context.fill(Path(ellipseIn: rect), with: .color(.sbGold.opacity(0.12)))
                }
            }
        }
    }

    // MARK: - Table Detail Sheet

    private func tableDetailSheet(_ table: SeatTable) -> some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Text(table.name)
                            .font(SBFont.displaySmall)
                            .foregroundStyle(Color.sbCharcoal)
                        Spacer()
                        Text("\(table.type.rawValue) · \(table.seats) seats")
                            .font(SBFont.small)
                            .foregroundStyle(Color.sbWarm)
                    }

                    Button {
                        showDetailSheet = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { showDrawer = true }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "slider.horizontal.3")
                            Text("Edit Table")
                        }
                        .font(SBFont.inter(12, weight: .semibold))
                        .foregroundStyle(Color.sbGoldDk)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.sbChampagne)
                        .clipShape(RoundedRectangle(cornerRadius: SBRadius.small))
                    }
                    .buttonStyle(.plain)

                    seatList(table: table)
                }
                .padding(.horizontal, SBSpacing.screenMargin)
                .padding(.top, 12)
            }
            .background(Color.sbIvory)
        }
    }

    // MARK: - Seat List

    private func seatList(table: SeatTable) -> some View {
        VStack(spacing: 6) {
            ForEach(0..<table.seats, id: \.self) { index in
                let guestId = table.assignments.first { $0.value == index }?.key
                let guest = plan?.guests.first { $0.id == guestId }
                if let guest {
                    filledSeatRow(index: index, guest: guest)
                } else {
                    emptySeatRow(index: index)
                }
            }
        }
    }

    private func filledSeatRow(index: Int, guest: Guest) -> some View {
        HStack(spacing: 10) {
            ZStack {
                Circle().fill(Color.sbGold).frame(width: 22, height: 22)
                Text("\(index + 1)").font(SBFont.inter(10, weight: .bold)).foregroundStyle(.white)
            }
            SBAvatar(name: guest.displayName, size: 30)
            VStack(alignment: .leading, spacing: 1) {
                Text(guest.displayName).font(SBFont.bodySmallBold).foregroundStyle(Color.sbCharcoal)
                if !guest.categories.isEmpty {
                    Text(guest.categories.first ?? "").font(SBFont.capsLabel).foregroundStyle(Color.sbWarm)
                }
            }
            Spacer()
            Button { unassignGuest(guest) } label: {
                Image(systemName: "xmark.circle.fill").font(.system(size: 16)).foregroundStyle(Color.sbWarm2)
            }
            .buttonStyle(.plain)
        }
        .padding(8)
        .background(guest.side == .bride || guest.side == .groom ? Color.sbChampagne.opacity(0.4) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func emptySeatRow(index: Int) -> some View {
        Button {
            assigningSeatIndex = index
            showGuestPicker = true
            HapticEngine.light()
        } label: {
            HStack(spacing: 10) {
                Circle().strokeBorder(Color.sbWarm2, style: StrokeStyle(lineWidth: 1, dash: [3, 2])).frame(width: 22, height: 22)
                Text("Empty seat · tap to assign").font(SBFont.meta).foregroundStyle(Color.sbWarm)
                Spacer()
                Image(systemName: "plus").font(.system(size: 12, weight: .medium)).foregroundStyle(Color.sbWarm2)
            }
            .padding(8)
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.sbLine, style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Data Mutations

    private var unseatedCount: Int {
        guard let plan else { return 0 }
        return max(0, plan.guests.count - plan.tables.reduce(0) { $0 + $1.filledCount })
    }

    private func updateTablePosition(id: String, x: Double, y: Double) {
        guard var p = appState.activePlan,
              let idx = p.tables.firstIndex(where: { $0.id == id }) else { return }
        p.tables[idx].x = x
        p.tables[idx].y = y
        appState.activePlan = p
    }

    private func updateObjectPosition(id: String, x: Double, y: Double) {
        guard var p = appState.activePlan,
              let idx = p.objects.firstIndex(where: { $0.id == id }) else { return }
        p.objects[idx].x = x
        p.objects[idx].y = y
        appState.activePlan = p
    }

    private func deleteObjectById(_ id: String) {
        guard var p = appState.activePlan else { return }
        p.objects.removeAll { $0.id == id }
        appState.activePlan = p
        selectedObjectId = nil
        HapticEngine.medium()
        Task { try? await appState.database.savePlanData(plan: p) }
    }

    private func savePositions() {
        guard let plan = appState.activePlan else { return }
        Task { try? await appState.database.savePlanData(plan: plan) }
    }

    private func unassignGuest(_ guest: Guest) {
        guard let tableId = selectedTableId,
              var p = appState.activePlan,
              let ti = p.tables.firstIndex(where: { $0.id == tableId }) else { return }
        p.tables[ti].assignments.removeValue(forKey: guest.id)
        appState.activePlan = p
        HapticEngine.medium()
        Task { try? await appState.database.savePlanData(plan: p) }
    }

    private func assignGuest(_ guest: Guest) {
        guard let seatIndex = assigningSeatIndex,
              let tableId = selectedTableId,
              var p = appState.activePlan,
              let ti = p.tables.firstIndex(where: { $0.id == tableId }) else { return }
        p.tables[ti].assignments[guest.id] = seatIndex
        appState.activePlan = p
        HapticEngine.success()
        Task { try? await appState.database.savePlanData(plan: p) }
    }
}

#Preview {
    EditorView()
        .environment(AppState())
}

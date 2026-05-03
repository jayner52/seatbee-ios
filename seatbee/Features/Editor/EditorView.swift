import SwiftUI

struct EditorView: View {
    @Environment(AppState.self) private var appState
    @State private var selectedTableId: String?
    @State private var showDrawer = false
    @State private var showGuestPicker = false
    @State private var showAddTable = false
    @State private var showAddVenueObject = false
    @State private var showRoomSetup = false
    @State private var showDetailSheet = false
    @State private var assigningSeatIndex: Int?

    // Canvas viewport
    @State private var canvasOffset: CGSize = .zero
    @State private var canvasScale: CGFloat = 0.8
    @State private var lastCanvasOffset: CGSize = .zero
    @State private var lastCanvasScale: CGFloat = 0.8
    @State private var draggingTableId: String?

    private var plan: SeatingPlan? { appState.activePlan }
    private var tables: [SeatTable] { plan?.tables ?? [] }
    private var selectedTable: SeatTable? {
        tables.first { $0.id == selectedTableId }
    }

    var body: some View {
        ZStack {
            if plan == nil {
                emptyState
            } else {
                // Full-screen canvas
                canvasView
                    .ignoresSafeArea(.all, edges: .bottom)

                // Top bar overlay
                VStack {
                    topBar
                    Spacer()
                }

                // Bottom controls overlay
                VStack {
                    Spacer()
                    bottomControls
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
        .task {
            // Auto-load plan if none selected
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
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .background(Color.sbIvory)
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack(spacing: 10) {
            // Plan name
            Text(plan?.name ?? "")
                .font(SBFont.displayNav)
                .foregroundStyle(Color.sbCharcoal)
                .lineLimit(1)

            Spacer()

            // Undo
            Button { appState.undo(); HapticEngine.light() } label: {
                Image(systemName: "arrow.uturn.backward")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(appState.undoManager.canUndo ? Color.sbCharcoal : Color.sbWarm2)
                    .frame(width: 34, height: 34)
                    .background(.ultraThinMaterial)
                    .clipShape(Circle())
            }
            .disabled(!appState.undoManager.canUndo)

            // Redo
            Button { appState.redo(); HapticEngine.light() } label: {
                Image(systemName: "arrow.uturn.forward")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(appState.undoManager.canRedo ? Color.sbCharcoal : Color.sbWarm2)
                    .frame(width: 34, height: 34)
                    .background(.ultraThinMaterial)
                    .clipShape(Circle())
            }
            .disabled(!appState.undoManager.canRedo)

            // Room setup
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

    // MARK: - Bottom Controls

    private var bottomControls: some View {
        VStack(spacing: 0) {
            // Selected table pill
            if let table = selectedTable {
                Button {
                    showDetailSheet = true
                } label: {
                    HStack(spacing: 10) {
                        SBTableGraphic(totalSeats: table.seats, filledSeats: table.filledCount, size: 36)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(table.name)
                                .font(SBFont.bodySmallBold)
                                .foregroundStyle(Color.sbCharcoal)
                            Text("\(table.filledCount)/\(table.seats) seated · \(table.type.rawValue)")
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
            }

            // Action bar
            HStack(spacing: 16) {
                // Add menu
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

                // Zoom controls
                HStack(spacing: 4) {
                    Button {
                        withAnimation(.seatbee) {
                            canvasScale = max(0.3, canvasScale / 1.3)
                            lastCanvasScale = canvasScale
                        }
                    } label: {
                        Image(systemName: "minus")
                            .font(.system(size: 13, weight: .bold))
                            .frame(width: 34, height: 34)
                            .background(.regularMaterial)
                            .clipShape(Circle())
                    }

                    Text("\(Int(canvasScale * 100))%")
                        .font(SBFont.capsLabel)
                        .foregroundStyle(Color.sbWarm)
                        .frame(width: 40)

                    Button {
                        withAnimation(.seatbee) {
                            canvasScale = min(3.0, canvasScale * 1.3)
                            lastCanvasScale = canvasScale
                        }
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 13, weight: .bold))
                            .frame(width: 34, height: 34)
                            .background(.regularMaterial)
                            .clipShape(Circle())
                    }

                    Button {
                        withAnimation(.seatbee) {
                            canvasScale = 0.8
                            lastCanvasScale = 0.8
                            canvasOffset = .zero
                            lastCanvasOffset = .zero
                        }
                    } label: {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 11, weight: .medium))
                            .frame(width: 34, height: 34)
                            .background(.regularMaterial)
                            .clipShape(Circle())
                    }
                }
                .buttonStyle(.plain)

                Spacer()

                // AI pill
                aiPill
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 90) // Tab bar clearance
        }
    }

    // MARK: - Full-Screen Canvas

    private var canvasView: some View {
        GeometryReader { geo in
            ZStack {
                // Background
                Color.sbIvory2
                    .overlay(dotPattern)

                // Center offset for initial view
                let centerX = geo.size.width / 2
                let centerY = geo.size.height / 2

                // Tables
                ForEach(tables) { table in
                    let posX = (table.x - 200) * canvasScale + centerX + canvasOffset.width
                    let posY = (table.y - 200) * canvasScale + centerY + canvasOffset.height
                    let size = max(40, 70 * canvasScale)

                    SBTableGraphic(
                        totalSeats: table.seats,
                        filledSeats: table.filledCount,
                        label: table.name,
                        size: size,
                        isSelected: table.id == selectedTableId
                    )
                    .position(x: posX, y: posY)
                    .gesture(tableDragGesture(table))
                    .simultaneousGesture(tableTapGesture(table))
                    .zIndex(table.id == selectedTableId ? 10 : (table.id == draggingTableId ? 5 : 1))
                }

                // Venue objects
                ForEach(plan?.objects ?? []) { obj in
                    let posX = (obj.x - 200) * canvasScale + centerX + canvasOffset.width
                    let posY = (obj.y - 200) * canvasScale + centerY + canvasOffset.height
                    let objW = max(30, obj.width * canvasScale)
                    let objH = max(20, obj.height * canvasScale)
                    let def = venueObjectTypes.first { $0.type == obj.type }

                    venueObjectView(obj: obj, def: def, width: objW, height: objH)
                        .position(x: posX, y: posY)
                        .gesture(objectDragGesture(obj))
                        .onLongPressGesture { deleteObject(obj) }
                }
            }
            .contentShape(Rectangle())
            .gesture(canvasPanGesture)
            .simultaneousGesture(canvasZoomGesture)
        }
    }

    private func venueObjectView(obj: RoomObject, def: VenueObjectDef?, width: CGFloat, height: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: max(4, 8 * canvasScale))
            .fill(Color(hex: def?.color ?? "#8B8680").opacity(0.8))
            .frame(width: width, height: height)
            .overlay(
                VStack(spacing: 2) {
                    Image(systemName: def?.icon ?? "square")
                        .font(.system(size: max(8, 16 * canvasScale)))
                        .foregroundStyle(def?.color == "#2D2D2D" ? .white : Color.sbCharcoal.opacity(0.7))
                    if canvasScale > 0.5 {
                        Text(obj.name)
                            .font(.system(size: max(6, 10 * canvasScale), weight: .medium))
                            .foregroundStyle(def?.color == "#2D2D2D" ? .white : Color.sbCharcoal)
                            .lineLimit(1)
                    }
                }
            )
            .shadow(color: Color.black.opacity(0.1), radius: 4, x: 0, y: 2)
    }

    // MARK: - Gestures

    private func tableDragGesture(_ table: SeatTable) -> some Gesture {
        DragGesture(minimumDistance: 5)
            .onChanged { value in
                draggingTableId = table.id
                moveTable(table, by: value.translation)
            }
            .onEnded { _ in
                draggingTableId = nil
                savePositions()
                HapticEngine.light()
            }
    }

    private func tableTapGesture(_ table: SeatTable) -> some Gesture {
        TapGesture()
            .onEnded {
                withAnimation(.seatbee) {
                    selectedTableId = table.id
                    showDetailSheet = true
                }
                HapticEngine.selection()
            }
    }

    private func objectDragGesture(_ obj: RoomObject) -> some Gesture {
        DragGesture(minimumDistance: 5)
            .onChanged { value in
                moveObject(obj, by: value.translation)
            }
            .onEnded { _ in
                savePositions()
                HapticEngine.light()
            }
    }

    private var canvasPanGesture: some Gesture {
        DragGesture(minimumDistance: 10)
            .onChanged { value in
                guard draggingTableId == nil else { return }
                canvasOffset = CGSize(
                    width: lastCanvasOffset.width + value.translation.width,
                    height: lastCanvasOffset.height + value.translation.height
                )
            }
            .onEnded { _ in
                lastCanvasOffset = canvasOffset
            }
    }

    private var canvasZoomGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                canvasScale = max(0.3, min(3.0, lastCanvasScale * value.magnification))
            }
            .onEnded { _ in
                lastCanvasScale = canvasScale
            }
    }

    // MARK: - Table Detail Sheet

    private func tableDetailSheet(_ table: SeatTable) -> some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    // Header
                    HStack {
                        Text(table.name)
                            .font(SBFont.displaySmall)
                            .foregroundStyle(Color.sbCharcoal)
                        Spacer()
                        Text("\(table.type.rawValue) · \(table.seats) seats")
                            .font(SBFont.small)
                            .foregroundStyle(Color.sbWarm)
                    }

                    // Action buttons
                    HStack(spacing: 8) {
                        Button {
                            showDetailSheet = false
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                showDrawer = true
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "slider.horizontal.3")
                                Text("Edit")
                            }
                            .font(SBFont.inter(12, weight: .semibold))
                            .foregroundStyle(Color.sbGoldDk)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.sbChampagne)
                            .clipShape(RoundedRectangle(cornerRadius: SBRadius.small))
                        }
                        .buttonStyle(.plain)

                        Spacer()
                    }

                    // Seat list
                    seatList(table: table)
                }
                .padding(.horizontal, SBSpacing.screenMargin)
                .padding(.top, 12)
            }
            .background(Color.sbIvory)
        }
    }

    // MARK: - Shared Components

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

    private var aiPill: some View {
        Button {
            appState.selectedTab = .ai
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "sparkles")
                    .font(.system(size: 11, weight: .semibold))
                Text("AI seat \(unseatedCount)")
                    .font(SBFont.inter(11, weight: .semibold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.sbGold)
            .clipShape(Capsule())
            .shadow(color: Color.sbGold.opacity(0.3), radius: 8, x: 0, y: 3)
        }
        .buttonStyle(.plain)
    }

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
                Circle()
                    .fill(Color.sbGold)
                    .frame(width: 22, height: 22)
                Text("\(index + 1)")
                    .font(SBFont.inter(10, weight: .bold))
                    .foregroundStyle(.white)
            }
            SBAvatar(name: guest.displayName, size: 30)
            VStack(alignment: .leading, spacing: 1) {
                Text(guest.displayName)
                    .font(SBFont.bodySmallBold)
                    .foregroundStyle(Color.sbCharcoal)
                if !guest.categories.isEmpty {
                    Text(guest.categories.first ?? "")
                        .font(SBFont.capsLabel)
                        .foregroundStyle(Color.sbWarm)
                }
            }
            Spacer()
            Button { unassignGuest(guest) } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(Color.sbWarm2)
            }
            .buttonStyle(.plain)
        }
        .padding(8)
        .background(
            guest.side == .bride || guest.side == .groom
                ? Color.sbChampagne.opacity(0.4) : Color.clear
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func emptySeatRow(index: Int) -> some View {
        Button {
            assigningSeatIndex = index
            showGuestPicker = true
            HapticEngine.light()
        } label: {
            HStack(spacing: 10) {
                Circle()
                    .strokeBorder(Color.sbWarm2, style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
                    .frame(width: 22, height: 22)
                Text("Empty seat · tap to assign")
                    .font(SBFont.meta)
                    .foregroundStyle(Color.sbWarm)
                Spacer()
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.sbWarm2)
            }
            .padding(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color.sbLine, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Data Actions

    private var unseatedCount: Int {
        guard let plan else { return 0 }
        let seated = plan.tables.reduce(0) { $0 + $1.filledCount }
        return max(0, plan.guests.count - seated)
    }

    private func moveTable(_ table: SeatTable, by translation: CGSize) {
        guard var p = appState.activePlan,
              let idx = p.tables.firstIndex(where: { $0.id == table.id }) else { return }
        p.tables[idx].x = table.x + Double(translation.width / canvasScale)
        p.tables[idx].y = table.y + Double(translation.height / canvasScale)
        appState.activePlan = p
    }

    private func moveObject(_ obj: RoomObject, by translation: CGSize) {
        guard var p = appState.activePlan,
              let idx = p.objects.firstIndex(where: { $0.id == obj.id }) else { return }
        p.objects[idx].x = obj.x + Double(translation.width / canvasScale)
        p.objects[idx].y = obj.y + Double(translation.height / canvasScale)
        appState.activePlan = p
    }

    private func deleteObject(_ obj: RoomObject) {
        guard var p = appState.activePlan else { return }
        p.objects.removeAll { $0.id == obj.id }
        appState.activePlan = p
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

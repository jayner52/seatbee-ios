import SwiftUI

struct EditorView: View {
    @Environment(AppState.self) private var appState
    @State private var selectedTableId: String?
    @State private var showDrawer = false
    @State private var showGuestPicker = false
    @State private var showAddTable = false
    @State private var showAddVenueObject = false
    @State private var showRoomSetup = false
    @State private var assigningSeatIndex: Int?

    // Canvas viewport state
    @State private var canvasOffset: CGSize = .zero
    @State private var canvasScale: CGFloat = 1.0
    @State private var lastCanvasOffset: CGSize = .zero
    @State private var lastCanvasScale: CGFloat = 1.0
    @State private var draggingTableId: String?

    private var plan: SeatingPlan? { appState.activePlan }
    private var tables: [SeatTable] { plan?.tables ?? [] }
    private var selectedTable: SeatTable? {
        tables.first { $0.id == selectedTableId }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Nav header
                SBNavHeader(
                    title: plan?.name ?? "Editor",
                    rightContent: AnyView(
                        HStack(spacing: 12) {
                            // Undo/Redo
                            Button { appState.undo(); HapticEngine.light() } label: {
                                Image(systemName: "arrow.uturn.backward")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundStyle(appState.undoManager.canUndo ? Color.sbCharcoal : Color.sbWarm2)
                            }
                            .disabled(!appState.undoManager.canUndo)

                            Button { appState.redo(); HapticEngine.light() } label: {
                                Image(systemName: "arrow.uturn.forward")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundStyle(appState.undoManager.canRedo ? Color.sbCharcoal : Color.sbWarm2)
                            }
                            .disabled(!appState.undoManager.canRedo)

                            // Room setup
                            Button { showRoomSetup = true } label: {
                                Image(systemName: "square.dashed")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundStyle(Color.sbGoldDk)
                            }
                        }
                    )
                )

                if plan == nil {
                    // Empty state
                    Spacer()
                    VStack(spacing: 12) {
                        Image(systemName: "square.grid.2x2")
                            .font(.system(size: 40))
                            .foregroundStyle(Color.sbWarm2)
                        Text("Select a plan from the Plans tab")
                            .font(SBFont.body)
                            .foregroundStyle(Color.sbWarm)
                    }
                    Spacer()
                } else {
                    // Split view: canvas top, detail bottom
                    GeometryReader { geo in
                        let canvasHeight = max(100, geo.size.height * 0.38)
                        let detailHeight = max(100, geo.size.height - canvasHeight - 18)

                        VStack(spacing: 0) {
                            // Canvas region — clipped and scrollable
                            canvasView
                                .frame(height: canvasHeight)
                                .clipped()

                            // Drag handle
                            dragHandle

                            // Detail panel — takes remaining space
                            detailPanel
                                .frame(height: detailHeight)
                                .clipped()
                        }
                    }
                }
            }
            .background(Color.sbIvory)
        }
        .sheet(isPresented: $showDrawer) {
            if let table = selectedTable {
                TableDrawerView(table: table)
                    .presentationDetents([.fraction(0.82)])
                    .presentationDragIndicator(.visible)
                    .presentationCornerRadius(24)
            }
        }
        .sheet(isPresented: $showGuestPicker) {
            if let plan {
                GuestPickerSheet(
                    guests: plan.guests,
                    tables: plan.tables
                ) { guest in
                    assignGuest(guest)
                }
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
        .onAppear {
            if selectedTableId == nil, let firstTable = tables.first {
                selectedTableId = firstTable.id
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .selectTable)) { notification in
            if let tableId = notification.userInfo?["tableId"] as? String {
                withAnimation(.seatbee) {
                    selectedTableId = tableId
                }
            }
        }
    }

    // MARK: - Canvas

    private var canvasView: some View {
        GeometryReader { geo in
            ZStack {
                // Background with dot pattern
                Color.sbIvory2
                    .overlay(dotPattern)

                // Tables positioned by their x,y coordinates
                ForEach(tables) { table in
                    let tableSize: CGFloat = 70
                    let posX = table.x * canvasScale + canvasOffset.width
                    let posY = table.y * canvasScale + canvasOffset.height

                    SBTableGraphic(
                        totalSeats: table.seats,
                        filledSeats: table.filledCount,
                        label: table.name,
                        size: tableSize * canvasScale,
                        isSelected: table.id == selectedTableId
                    )
                    .position(x: posX, y: posY)
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                draggingTableId = table.id
                                moveTable(table, by: value.translation)
                            }
                            .onEnded { _ in
                                draggingTableId = nil
                                saveTablePositions()
                            }
                    )
                    .onTapGesture {
                        withAnimation(.seatbee) {
                            selectedTableId = table.id
                        }
                        HapticEngine.selection()
                    }
                    .zIndex(table.id == selectedTableId ? 10 : (table.id == draggingTableId ? 5 : 1))
                }

                // Venue objects
                ForEach(plan?.objects ?? []) { obj in
                    let posX = obj.x * canvasScale + canvasOffset.width
                    let posY = obj.y * canvasScale + canvasOffset.height
                    let objW = obj.width * canvasScale
                    let objH = obj.height * canvasScale
                    let def = venueObjectTypes.first { $0.type == obj.type }

                    RoundedRectangle(cornerRadius: 8 * canvasScale)
                        .fill(Color(hex: def?.color ?? "#8B8680").opacity(0.7))
                        .frame(width: objW, height: objH)
                        .overlay(
                            VStack(spacing: 2) {
                                Image(systemName: def?.icon ?? "square")
                                    .font(.system(size: 14 * canvasScale))
                                    .foregroundStyle(def?.color == "#2D2D2D" ? .white : Color.sbCharcoal.opacity(0.6))
                                if canvasScale > 0.6 {
                                    Text(obj.name)
                                        .font(.system(size: 9 * canvasScale, weight: .medium))
                                        .foregroundStyle(def?.color == "#2D2D2D" ? .white : Color.sbCharcoal)
                                }
                            }
                        )
                        .position(x: posX, y: posY)
                        .gesture(
                            DragGesture()
                                .onChanged { value in
                                    moveObject(obj, by: value.translation)
                                }
                                .onEnded { _ in
                                    saveTablePositions()
                                }
                        )
                        .onLongPressGesture {
                            deleteObject(obj)
                        }
                }
            }
            .clipped()
            .contentShape(Rectangle())
            // Pan gesture on canvas background
            .gesture(
                DragGesture()
                    .onChanged { value in
                        if draggingTableId == nil {
                            canvasOffset = CGSize(
                                width: lastCanvasOffset.width + value.translation.width,
                                height: lastCanvasOffset.height + value.translation.height
                            )
                        }
                    }
                    .onEnded { _ in
                        lastCanvasOffset = canvasOffset
                    }
            )
            // Pinch to zoom
            .gesture(
                MagnifyGesture()
                    .onChanged { value in
                        canvasScale = max(0.3, min(3.0, lastCanvasScale * value.magnification))
                    }
                    .onEnded { _ in
                        lastCanvasScale = canvasScale
                    }
            )
            .overlay(alignment: .bottomLeading) {
                // Add menu
                Menu {
                    Button {
                        showAddTable = true
                    } label: {
                        Label("Add Table", systemImage: "circle")
                    }
                    Button {
                        showAddVenueObject = true
                    } label: {
                        Label("Add Venue Object", systemImage: "square.on.square")
                    }
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 40, height: 40)
                        .background(Color.sbCharcoal)
                        .clipShape(Circle())
                        .shadow(color: Color.sbCharcoal.opacity(0.3), radius: 8, x: 0, y: 4)
                }
                .padding(12)
            }
            .overlay(alignment: .bottomTrailing) {
                // AI pill
                aiPill
                    .padding(12)
            }
            .overlay(alignment: .topTrailing) {
                // Zoom controls
                VStack(spacing: 6) {
                    Button {
                        withAnimation(.seatbee) {
                            canvasScale = min(3.0, canvasScale * 1.3)
                            lastCanvasScale = canvasScale
                        }
                    } label: {
                        Image(systemName: "plus.magnifyingglass")
                            .font(.system(size: 14))
                            .foregroundStyle(Color.sbCharcoal)
                            .frame(width: 32, height: 32)
                            .background(.ultraThinMaterial)
                            .clipShape(Circle())
                    }
                    Button {
                        withAnimation(.seatbee) {
                            canvasScale = max(0.3, canvasScale / 1.3)
                            lastCanvasScale = canvasScale
                        }
                    } label: {
                        Image(systemName: "minus.magnifyingglass")
                            .font(.system(size: 14))
                            .foregroundStyle(Color.sbCharcoal)
                            .frame(width: 32, height: 32)
                            .background(.ultraThinMaterial)
                            .clipShape(Circle())
                    }
                    Button {
                        withAnimation(.seatbee) {
                            canvasScale = 1.0
                            lastCanvasScale = 1.0
                            canvasOffset = .zero
                            lastCanvasOffset = .zero
                        }
                    } label: {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 12))
                            .foregroundStyle(Color.sbWarm)
                            .frame(width: 32, height: 32)
                            .background(.ultraThinMaterial)
                            .clipShape(Circle())
                    }
                }
                .buttonStyle(.plain)
                .padding(8)
            }
        }
    }

    private func moveTable(_ table: SeatTable, by translation: CGSize) {
        guard var updatedPlan = appState.activePlan,
              let idx = updatedPlan.tables.firstIndex(where: { $0.id == table.id }) else { return }

        updatedPlan.tables[idx].x = table.x + Double(translation.width / canvasScale)
        updatedPlan.tables[idx].y = table.y + Double(translation.height / canvasScale)
        appState.activePlan = updatedPlan
    }

    private func saveTablePositions() {
        guard let plan = appState.activePlan else { return }
        Task {
            try? await appState.database.savePlanData(plan: plan)
        }
    }

    private func moveObject(_ obj: RoomObject, by translation: CGSize) {
        guard var updatedPlan = appState.activePlan,
              let idx = updatedPlan.objects.firstIndex(where: { $0.id == obj.id }) else { return }
        updatedPlan.objects[idx].x = obj.x + Double(translation.width / canvasScale)
        updatedPlan.objects[idx].y = obj.y + Double(translation.height / canvasScale)
        appState.activePlan = updatedPlan
    }

    private func deleteObject(_ obj: RoomObject) {
        guard var plan = appState.activePlan else { return }
        plan.objects.removeAll { $0.id == obj.id }
        appState.activePlan = plan
        HapticEngine.medium()
        Task { try? await appState.database.savePlanData(plan: plan) }
    }

    private var dotPattern: some View {
        Canvas { context, size in
            let spacing: CGFloat = 18
            let dotSize: CGFloat = 2
            for x in stride(from: spacing, through: size.width, by: spacing) {
                for y in stride(from: spacing, through: size.height, by: spacing) {
                    let rect = CGRect(x: x - dotSize/2, y: y - dotSize/2, width: dotSize, height: dotSize)
                    context.fill(Path(ellipseIn: rect), with: .color(.sbGold.opacity(0.15)))
                }
            }
        }
    }

    private var aiPill: some View {
        Button {
            appState.selectedTab = .ai
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.system(size: 12, weight: .semibold))
                Text("AI seat \(unseatedCount)")
                    .font(SBFont.inter(12, weight: .semibold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Color.sbGold)
            .clipShape(Capsule())
            .shadow(color: Color.sbGold.opacity(0.3), radius: 12, x: 0, y: 4)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Drag Handle

    private var dragHandle: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(Color.sbLine)
                .frame(height: 0.5)
            HStack {
                Spacer()
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.sbWarm2)
                    .frame(width: 36, height: 4)
                Spacer()
            }
            .padding(.vertical, 7)
            Rectangle()
                .fill(Color.sbLine)
                .frame(height: 0.5)
        }
        .background(Color.sbIvory)
    }

    // MARK: - Detail Panel

    private var detailPanel: some View {
        ScrollView {
            if let table = selectedTable {
                VStack(alignment: .leading, spacing: 14) {
                    // Table header
                    HStack {
                        Text(table.name)
                            .font(SBFont.displaySmall)
                            .foregroundStyle(Color.sbCharcoal)
                        Spacer()
                        Text("\(table.type.rawValue) · \(table.seats) seats")
                            .font(SBFont.small)
                            .foregroundStyle(Color.sbWarm)
                    }

                    // Open full detail link
                    Button {
                        showDrawer = true
                    } label: {
                        Text("Open full detail →")
                            .font(SBFont.caption)
                            .foregroundStyle(Color.sbGoldDk)
                    }

                    // Seat list
                    seatList(table: table)

                    // Bottom padding for tab bar
                    Spacer().frame(height: 80)
                }
                .padding(.horizontal, SBSpacing.screenMargin)
                .padding(.top, 12)
            } else {
                VStack(spacing: 12) {
                    Spacer().frame(height: 40)
                    Image(systemName: "hand.tap")
                        .font(.system(size: 32))
                        .foregroundStyle(Color.sbWarm2)
                    Text("Tap a table to see details")
                        .font(SBFont.body)
                        .foregroundStyle(Color.sbWarm)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .background(Color.sbIvory)
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

            // Unassign button
            Button {
                unassignGuest(guest)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(Color.sbWarm2)
            }
            .buttonStyle(.plain)
        }
        .padding(8)
        .background(
            guest.side == .bride || guest.side == .groom
                ? Color.sbChampagne.opacity(0.5)
                : Color.clear
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

    // MARK: - Helpers

    private var unseatedCount: Int {
        guard let plan else { return 0 }
        let seated = plan.tables.reduce(0) { $0 + $1.filledCount }
        return max(0, plan.guests.count - seated)
    }

    private func unassignGuest(_ guest: Guest) {
        guard let tableId = selectedTableId,
              var updatedPlan = appState.activePlan,
              let tableIndex = updatedPlan.tables.firstIndex(where: { $0.id == tableId }) else { return }

        updatedPlan.tables[tableIndex].assignments.removeValue(forKey: guest.id)
        appState.activePlan = updatedPlan
        HapticEngine.medium()

        Task {
            try? await appState.database.savePlanData(plan: updatedPlan)
        }
    }

    private func assignGuest(_ guest: Guest) {
        guard let seatIndex = assigningSeatIndex,
              let tableId = selectedTableId,
              var updatedPlan = appState.activePlan,
              let tableIndex = updatedPlan.tables.firstIndex(where: { $0.id == tableId }) else { return }

        updatedPlan.tables[tableIndex].assignments[guest.id] = seatIndex
        appState.activePlan = updatedPlan
        HapticEngine.success()

        // Persist full plan data to Supabase
        Task {
            do {
                try await appState.database.savePlanData(plan: updatedPlan)
            } catch {
                print("[Editor] Failed to save assignment: \(error)")
            }
        }
    }
}

#Preview {
    EditorView()
        .environment(AppState())
}

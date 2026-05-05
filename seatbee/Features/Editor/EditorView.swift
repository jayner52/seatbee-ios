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

    // Selection tracking

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
                // UIKit-based canvas — rock solid gestures
                CanvasViewRepresentable(
                    tables: tables,
                    objects: objects,
                    guests: plan?.guests ?? [],
                    selectedTableId: selectedTableId,
                    selectedObjectId: selectedObjectId,
                    roomShape: plan?.roomShape,
                    roomWidth: plan?.roomWidth,
                    roomHeight: plan?.roomHeight,
                    customRoomPoints: plan?.customRoomPoints,
                    roomFlipH: plan?.roomFlipH,
                    roomFlipV: plan?.roomFlipV,
                    roomZones: plan?.roomZones,
                    floorPlanBase64: plan?.rawFloorPlanImage?.value as? String,
                    floorPlanOpacity: plan?.rawFloorPlanOpacity,
                    onSelectTable: { id in
                        selectedObjectId = nil
                        selectedTableId = id
                        showDetailSheet = true
                        HapticEngine.selection()
                    },
                    onSelectObject: { id in
                        selectedTableId = nil
                        selectedObjectId = id
                        HapticEngine.selection()
                    },
                    onDeselectAll: {
                        selectedTableId = nil
                        selectedObjectId = nil
                        showDetailSheet = false
                    },
                    onMoveTable: { id, x, y in
                        updateTablePosition(id: id, x: x, y: y)
                        savePositions()
                    },
                    onMoveObject: { id, x, y in
                        updateObjectPosition(id: id, x: x, y: y)
                        savePositions()
                    }
                )
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

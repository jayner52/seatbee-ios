import SwiftUI

struct EditorView: View {
    @Environment(AppState.self) private var appState
    @State private var selectedTableId: String?
    @State private var showDrawer = false
    @State private var showGuestPicker = false
    @State private var assigningSeatIndex: Int?

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
                        Button {
                            appState.selectedTab = .share
                        } label: {
                            Text("Share")
                                .font(SBFont.bodySmallBold)
                                .foregroundStyle(Color.sbGoldDk)
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
                        let canvasHeight = geo.size.height * 0.38
                        let detailHeight = geo.size.height - canvasHeight - 18 // 18 for drag handle

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
        ZStack {
            // Background with dot pattern
            Color.sbIvory2
                .overlay(dotPattern)

            // Scrollable table grid
            ScrollView([.vertical, .horizontal], showsIndicators: false) {
                let columns = min(3, max(1, tables.count))
                let tableSize: CGFloat = tables.count > 12 ? 56 : 70
                let gridSpacing: CGFloat = tables.count > 12 ? 10 : 14

                LazyVGrid(
                    columns: Array(repeating: GridItem(.fixed(tableSize), spacing: gridSpacing), count: columns),
                    spacing: gridSpacing
                ) {
                    ForEach(tables) { table in
                        SBTableGraphic(
                            totalSeats: table.seats,
                            filledSeats: table.filledCount,
                            label: "\(table.filledCount)",
                            size: tableSize,
                            isSelected: table.id == selectedTableId
                        )
                        .onTapGesture {
                            withAnimation(.seatbee) {
                                selectedTableId = table.id
                            }
                            HapticEngine.selection()
                        }
                    }
                }
                .padding(16)
            }

            // Floating AI pill — bottom right
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    aiPill
                        .padding(.trailing, 12)
                        .padding(.bottom, 8)
                }
            }

            // Pinch/drag hint — top right
            VStack {
                HStack {
                    Spacer()
                    Text("pinch · drag")
                        .font(SBFont.capsLabel)
                        .foregroundStyle(Color.sbWarm)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .padding(8)
                }
                Spacer()
            }
        }
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

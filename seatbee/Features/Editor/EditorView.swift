import SwiftUI

struct EditorView: View {
    @Environment(AppState.self) private var appState
    @State private var selectedTableId: String?
    @State private var showDrawer = false

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

                // Split view: 40% canvas, 60% detail
                GeometryReader { geo in
                    VStack(spacing: 0) {
                        // Canvas region (40%)
                        canvasView
                            .frame(height: geo.size.height * 0.4)

                        // Drag handle
                        dragHandle

                        // Detail panel (60%)
                        detailPanel
                            .frame(maxHeight: .infinity)
                    }
                }

                // Tab bar space
                Spacer().frame(height: 0)
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
    }

    // MARK: - Canvas

    private var canvasView: some View {
        ZStack {
            // Background with dot pattern
            Color.sbIvory2
                .overlay(dotPattern)

            // Tables grid
            let columns = min(3, tables.count)
            let spacing: CGFloat = 14
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: spacing), count: max(1, columns)), spacing: spacing) {
                ForEach(tables) { table in
                    SBTableGraphic(
                        totalSeats: table.seats,
                        filledSeats: table.filledCount,
                        label: "\(table.filledCount)",
                        size: 70,
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
            .padding(20)

            // Floating AI pill
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    aiPill
                        .padding(16)
                }
            }

            // Pinch/drag hint
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
                        .padding(12)
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
                let unseated = unseatedCount
                Text("AI seat \(unseated)")
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
        }
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

                    // Tags row
                    HStack(spacing: 8) {
                        SBChip(text: "Family", variant: .gold)
                        SBChip(text: "+ tag", variant: .muted)
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
                }
                .padding(SBSpacing.screenMargin)
            } else {
                VStack(spacing: 12) {
                    Spacer().frame(height: 60)
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
            // Seat number badge
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

    // MARK: - Helpers

    private var unseatedCount: Int {
        guard let plan else { return 0 }
        let seated = plan.tables.reduce(0) { $0 + $1.filledCount }
        return max(0, plan.guests.count - seated)
    }
}

#Preview {
    EditorView()
        .environment(AppState())
}

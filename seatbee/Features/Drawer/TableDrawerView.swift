import SwiftUI

struct TableDrawerView: View {
    let table: SeatTable
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var selectedTab = "Seats"
    @State private var showRenameAlert = false
    @State private var renameText = ""

    private let tabs = ["Seats", "Notes", "Tags"]

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text(table.name)
                    .font(SBFont.displayMedium)
                    .foregroundStyle(Color.sbCharcoal)
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
            color: table.color
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
        let minSeats = table.type == .sweetheart ? 2 : 2
        let maxSeats = table.type == .sweetheart ? 2 : (table.type == .round ? 16 : 20)
        let newCount = max(minSeats, min(maxSeats, table.seats + delta))
        guard newCount != table.seats else { return }
        plan.tables[idx].seats = newCount
        appState.activePlan = plan
        savePlan(plan)
        HapticEngine.selection()
    }

    private func changeTableType(_ type: SeatTable.TableType) {
        guard var plan = appState.activePlan,
              let idx = plan.tables.firstIndex(where: { $0.id == table.id }) else { return }
        plan.tables[idx].type = type
        appState.activePlan = plan
        savePlan(plan)
        HapticEngine.selection()
    }

    private func typeIcon(_ type: SeatTable.TableType) -> String {
        switch type {
        case .round: return "circle"
        case .rect: return "rectangle"
        case .head: return "person.2"
        case .sweetheart: return "heart"
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
        x: 100, y: 100, assignments: [:]
    ))
    .environment(AppState())
}

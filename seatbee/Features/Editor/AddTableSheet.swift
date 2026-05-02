import SwiftUI

struct AddTableSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    let tableTypes: [(type: SeatTable.TableType, name: String, icon: String, seats: Int, description: String)] = [
        (.round, "Round Table", "circle", 8, "Classic round table for 8 guests"),
        (.rect, "Rectangular", "rectangle", 6, "Long table for 6 guests"),
        (.head, "Head Table", "person.2", 12, "Main table for the wedding party"),
        (.sweetheart, "Sweetheart", "heart", 2, "Intimate table for the couple"),
    ]

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Text("Choose a table type")
                    .font(SBFont.displaySmall)
                    .foregroundStyle(Color.sbCharcoal)
                    .padding(.top, 8)

                ForEach(tableTypes, id: \.type) { item in
                    Button {
                        addTable(type: item.type, seats: item.seats, name: item.name)
                    } label: {
                        HStack(spacing: 16) {
                            ZStack {
                                Circle()
                                    .fill(Color.sbChampagne)
                                    .frame(width: 52, height: 52)
                                Image(systemName: item.icon)
                                    .font(.system(size: 22))
                                    .foregroundStyle(Color.sbGoldDk)
                            }

                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.name)
                                    .font(SBFont.bodySemibold)
                                    .foregroundStyle(Color.sbCharcoal)
                                Text(item.description)
                                    .font(SBFont.caption)
                                    .foregroundStyle(Color.sbWarm)
                            }

                            Spacer()

                            Text("\(item.seats) seats")
                                .font(SBFont.capsLabel)
                                .foregroundStyle(Color.sbGoldDk)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(Color.sbChampagne)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                        .padding(16)
                        .background(Color.sbIvory2)
                        .clipShape(RoundedRectangle(cornerRadius: SBRadius.card))
                        .overlay(
                            RoundedRectangle(cornerRadius: SBRadius.card)
                                .strokeBorder(Color.sbLine, lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }

                Spacer()
            }
            .padding(.horizontal, SBSpacing.screenMargin)
            .background(Color.sbIvory)
            .navigationTitle("Add Table")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Color.sbWarm)
                }
            }
        }
    }

    private func addTable(type: SeatTable.TableType, seats: Int, name: String) {
        guard var plan = appState.activePlan else { return }

        let tableCount = plan.tables.count
        let newTable = SeatTable(
            id: UUID().uuidString,
            name: "\(name) \(tableCount + 1)",
            type: type,
            seats: seats,
            x: Double(100 + (tableCount % 3) * 150),
            y: Double(100 + (tableCount / 3) * 150),
            rotation: 0,
            assignments: [:],
            locked: false,
            color: nil
        )

        plan.tables.append(newTable)
        appState.activePlan = plan
        HapticEngine.success()

        Task {
            try? await appState.database.savePlanData(plan: plan)
        }

        dismiss()
    }
}

#Preview {
    AddTableSheet()
        .environment(AppState())
}

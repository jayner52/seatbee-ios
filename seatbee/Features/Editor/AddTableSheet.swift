import SwiftUI

struct AddTableSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    let tableTypes: [(type: SeatTable.TableType, name: String, icon: String, seats: Int, description: String)] = [
        (.round, "Round Table", "circle", 8, "Classic round table for 8 guests"),
        (.oval, "Oval Table", "oval", 10, "Ellipse table for 10 guests"),
        (.rect, "Rectangular", "rectangle", 6, "Long table for 6 guests"),
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
                }
                .padding(.horizontal, SBSpacing.screenMargin)
                .padding(.vertical, 16)
            }
        }
        .background(Color.sbIvory)
    }

    private func addTable(type: SeatTable.TableType, seats: Int, name: String) {
        guard var plan = appState.activePlan else { return }

        let tableCount = plan.tables.count
        let dims = TableDefaults.dimensions(for: type)
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

        dismiss()
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

    static func dimensions(for type: SeatTable.TableType) -> Dimensions {
        switch type {
        case .round:
            return Dimensions(diameter: 75)            // 5ft
        case .rect:
            return Dimensions(width: 90, height: 37.5) // 6ft × 2.5ft
        case .head:
            return Dimensions(width: 270, height: 37.5, oneSide: true) // 18ft × 2.5ft
        case .sweetheart:
            return Dimensions(width: 60, height: 45, sweetShape: "heart") // 4ft × 3ft
        case .oval:
            return Dimensions(width: 120, height: 60)  // 8ft × 4ft (App.jsx:8453)
        }
    }
}

#Preview {
    AddTableSheet()
        .environment(AppState())
}

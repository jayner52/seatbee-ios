import SwiftUI

struct VenueObjectDef {
    let type: String
    let name: String
    let icon: String
    let color: String
    let width: Double
    let height: Double
}

let venueObjectTypes: [VenueObjectDef] = [
    .init(type: "dance", name: "Dance Floor", icon: "music.note", color: "#F7E7CE", width: 140, height: 140),
    .init(type: "bar", name: "Bar", icon: "wineglass", color: "#8B8680", width: 100, height: 40),
    .init(type: "entrance", name: "Entrance", icon: "door.left.hand.open", color: "#2D2D2D", width: 40, height: 60),
    .init(type: "stage", name: "Stage", icon: "star", color: "#D4A5A5", width: 160, height: 60),
    .init(type: "photobooth", name: "Photo Booth", icon: "camera", color: "#DDA0DD", width: 80, height: 80),
    .init(type: "podium", name: "Podium", icon: "mic", color: "#8B9DC3", width: 50, height: 50),
    .init(type: "gift", name: "Gift Table", icon: "gift", color: "#98D8C8", width: 100, height: 50),
    .init(type: "cake", name: "Cake Table", icon: "birthday.cake", color: "#FFE4E1", width: 70, height: 70),
    .init(type: "dj", name: "DJ Booth", icon: "headphones", color: "#2D2D2D", width: 80, height: 50),
    .init(type: "checkin", name: "Check-in", icon: "clipboard", color: "#87CEEB", width: 120, height: 40),
]

struct VenueObjectsSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    Text("Add a venue element to your floor plan")
                        .font(SBFont.body)
                        .foregroundStyle(Color.sbWarm)
                        .padding(.top, 8)

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        ForEach(venueObjectTypes, id: \.type) { obj in
                            Button {
                                addObject(obj)
                            } label: {
                                VStack(spacing: 8) {
                                    ZStack {
                                        RoundedRectangle(cornerRadius: 12)
                                            .fill(Color(hex: obj.color).opacity(0.2))
                                            .frame(width: 48, height: 48)
                                        Image(systemName: obj.icon)
                                            .font(.system(size: 20))
                                            .foregroundStyle(Color(hex: obj.color))
                                    }
                                    Text(obj.name)
                                        .font(SBFont.bodySmallBold)
                                        .foregroundStyle(Color.sbCharcoal)
                                }
                                .frame(maxWidth: .infinity)
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

                    Spacer(minLength: 40)
                }
                .padding(.horizontal, SBSpacing.screenMargin)
            }
            .background(Color.sbIvory)
            .navigationTitle("Venue Objects")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Color.sbWarm)
                }
            }
        }
    }

    private func addObject(_ def: VenueObjectDef) {
        guard var plan = appState.activePlan else { return }
        let obj = RoomObject(
            id: UUID().uuidString,
            type: def.type,
            name: def.name,
            x: 200 + Double.random(in: -50...50),
            y: 200 + Double.random(in: -50...50),
            width: def.width,
            height: def.height,
            rotation: 0,
            color: def.color,
            icon: def.icon
        )
        plan.objects.append(obj)
        appState.activePlan = plan
        HapticEngine.success()
        Task { try? await appState.database.savePlanData(plan: plan) }
        dismiss()
    }
}

#Preview {
    VenueObjectsSheet()
        .environment(AppState())
}

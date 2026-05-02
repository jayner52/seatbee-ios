import SwiftUI

struct EditPlanSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var planName = ""
    @State private var venue = ""
    @State private var eventDate = Date()
    @State private var hasDate = false
    @State private var eventType: SeatingPlan.EventType = .wedding

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Plan name
                    formSection("EVENT NAME") {
                        TextField("Sarah & Jon's Wedding", text: $planName)
                            .font(SBFont.body)
                            .padding(14)
                            .background(Color.sbIvory2)
                            .clipShape(RoundedRectangle(cornerRadius: SBRadius.button))
                    }

                    // Event type
                    formSection("EVENT TYPE") {
                        HStack(spacing: 8) {
                            ForEach(SeatingPlan.EventType.allCases, id: \.self) { type in
                                Button {
                                    eventType = type
                                    HapticEngine.selection()
                                } label: {
                                    Text(type.rawValue.capitalized)
                                        .font(SBFont.inter(13, weight: .semibold))
                                        .foregroundStyle(eventType == type ? Color.sbGoldDk : Color.sbWarm)
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 8)
                                        .background(eventType == type ? Color.sbChampagne : Color.sbIvory2)
                                        .clipShape(RoundedRectangle(cornerRadius: SBRadius.small))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    // Date
                    formSection("DATE") {
                        DatePicker("Event date", selection: $eventDate, displayedComponents: .date)
                            .datePickerStyle(.compact)
                            .font(SBFont.body)
                            .tint(Color.sbGold)
                            .onChange(of: eventDate) { _, _ in hasDate = true }
                    }

                    // Venue
                    formSection("VENUE") {
                        TextField("The Garden House", text: $venue)
                            .font(SBFont.body)
                            .padding(14)
                            .background(Color.sbIvory2)
                            .clipShape(RoundedRectangle(cornerRadius: SBRadius.button))
                    }

                    Spacer(minLength: 40)
                }
                .padding(.horizontal, SBSpacing.screenMargin)
                .padding(.top, 16)
            }
            .background(Color.sbIvory)
            .navigationTitle("Edit Event")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Color.sbWarm)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { saveChanges() }
                        .font(SBFont.bodySemibold)
                        .foregroundStyle(Color.sbGoldDk)
                }
            }
        }
        .onAppear { loadPlan() }
    }

    private func formSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(SBFont.capsLabel)
                .foregroundStyle(Color.sbWarm)
                .letterSpacing(1.5)
            content()
        }
    }

    private func loadPlan() {
        guard let plan = appState.activePlan else { return }
        planName = plan.name
        venue = plan.venue ?? ""
        eventType = plan.eventType
        if let date = plan.eventDate {
            eventDate = date
            hasDate = true
        }
    }

    private func saveChanges() {
        guard var plan = appState.activePlan else { return }
        plan.name = planName.isEmpty ? plan.name : planName
        plan.venue = venue.isEmpty ? nil : venue
        plan.eventType = eventType
        if hasDate { plan.eventDate = eventDate }

        appState.activePlan = plan
        HapticEngine.success()

        Task {
            try? await appState.database.savePlanData(plan: plan)
        }

        dismiss()
    }
}

#Preview {
    EditPlanSheet()
        .environment(AppState())
}

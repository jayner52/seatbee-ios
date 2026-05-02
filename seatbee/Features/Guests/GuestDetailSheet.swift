import SwiftUI

struct GuestDetailSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    let guest: Guest?  // nil = adding new guest
    var onSave: ((Guest) -> Void)?

    @State private var name = ""
    @State private var email = ""
    @State private var dietary = ""
    @State private var notes = ""
    @State private var side: Guest.GuestSide = .none
    @State private var rsvp: Guest.RSVPStatus = .unknown
    @State private var vip = false
    @State private var plusOne = false
    @State private var accessibility = ""
    @State private var selectedCategories: Set<String> = []
    @State private var showDeleteConfirm = false

    private var isEditing: Bool { guest != nil }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Name
                    formSection("NAME") {
                        TextField("Guest name", text: $name)
                            .font(SBFont.body)
                            .padding(14)
                            .background(Color.sbIvory2)
                            .clipShape(RoundedRectangle(cornerRadius: SBRadius.button))
                    }

                    // Side (Bride / Groom)
                    formSection("SIDE") {
                        HStack(spacing: 8) {
                            sideButton("Bride", side: .bride)
                            sideButton("Groom", side: .groom)
                            sideButton("Both", side: .both)
                            sideButton("None", side: .none)
                        }
                    }

                    // RSVP
                    formSection("RSVP STATUS") {
                        HStack(spacing: 8) {
                            rsvpButton("Yes", status: .yes, color: Color.sbSage)
                            rsvpButton("Pending", status: .pending, color: Color.sbBlush)
                            rsvpButton("No", status: .no, color: Color.sbError)
                        }
                    }

                    // Categories
                    formSection("CATEGORIES") {
                        let categories = appState.activePlan?.guests
                            .flatMap { $0.categories }
                            .reduce(into: Set<String>()) { $0.insert($1) }
                            ?? []

                        FlowLayout(spacing: 8) {
                            ForEach(Array(categories).sorted(), id: \.self) { cat in
                                Button {
                                    if selectedCategories.contains(cat) {
                                        selectedCategories.remove(cat)
                                    } else {
                                        selectedCategories.insert(cat)
                                    }
                                } label: {
                                    SBChip(
                                        text: cat,
                                        variant: selectedCategories.contains(cat) ? .gold : .default
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    // Details
                    formSection("DETAILS") {
                        VStack(spacing: 12) {
                            HStack {
                                Image(systemName: "envelope")
                                    .foregroundStyle(Color.sbWarm)
                                    .frame(width: 24)
                                TextField("Email", text: $email)
                                    .font(SBFont.body)
                                    .keyboardType(.emailAddress)
                                    .textInputAutocapitalization(.never)
                            }
                            .padding(12)
                            .background(Color.sbIvory2)
                            .clipShape(RoundedRectangle(cornerRadius: SBRadius.small))

                            HStack {
                                Image(systemName: "leaf")
                                    .foregroundStyle(Color.sbWarm)
                                    .frame(width: 24)
                                TextField("Dietary needs", text: $dietary)
                                    .font(SBFont.body)
                            }
                            .padding(12)
                            .background(Color.sbIvory2)
                            .clipShape(RoundedRectangle(cornerRadius: SBRadius.small))

                            HStack {
                                Image(systemName: "figure.roll")
                                    .foregroundStyle(Color.sbWarm)
                                    .frame(width: 24)
                                TextField("Accessibility needs", text: $accessibility)
                                    .font(SBFont.body)
                            }
                            .padding(12)
                            .background(Color.sbIvory2)
                            .clipShape(RoundedRectangle(cornerRadius: SBRadius.small))

                            HStack {
                                Image(systemName: "note.text")
                                    .foregroundStyle(Color.sbWarm)
                                    .frame(width: 24)
                                TextField("Notes", text: $notes)
                                    .font(SBFont.body)
                            }
                            .padding(12)
                            .background(Color.sbIvory2)
                            .clipShape(RoundedRectangle(cornerRadius: SBRadius.small))
                        }
                    }

                    // Toggles
                    formSection("OPTIONS") {
                        VStack(spacing: 0) {
                            Toggle(isOn: $vip) {
                                HStack(spacing: 8) {
                                    Image(systemName: "star.fill")
                                        .foregroundStyle(Color.sbGold)
                                    Text("VIP Guest")
                                        .font(SBFont.body)
                                }
                            }
                            .tint(Color.sbGold)
                            .padding(.vertical, 8)

                            Divider()

                            Toggle(isOn: $plusOne) {
                                HStack(spacing: 8) {
                                    Image(systemName: "person.badge.plus")
                                        .foregroundStyle(Color.sbWarm)
                                    Text("Has +1")
                                        .font(SBFont.body)
                                }
                            }
                            .tint(Color.sbGold)
                            .padding(.vertical, 8)
                        }
                    }

                    // Delete button (only for editing)
                    if isEditing {
                        Button {
                            showDeleteConfirm = true
                        } label: {
                            HStack {
                                Image(systemName: "trash")
                                Text("Delete Guest")
                            }
                            .font(SBFont.bodySemibold)
                            .foregroundStyle(Color.sbError)
                            .frame(maxWidth: .infinity)
                            .padding(14)
                            .overlay(
                                RoundedRectangle(cornerRadius: SBRadius.button)
                                    .strokeBorder(Color.sbError.opacity(0.3), lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                    }

                    Spacer(minLength: 40)
                }
                .padding(.horizontal, SBSpacing.screenMargin)
                .padding(.top, 16)
            }
            .background(Color.sbIvory)
            .navigationTitle(isEditing ? "Edit Guest" : "Add Guest")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Color.sbWarm)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { saveGuest() }
                        .font(SBFont.bodySemibold)
                        .foregroundStyle(Color.sbGoldDk)
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .alert("Delete Guest?", isPresented: $showDeleteConfirm) {
                Button("Delete", role: .destructive) { deleteGuest() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will remove \(guest?.displayName ?? "this guest") from the plan.")
            }
        }
        .onAppear { loadGuest() }
    }

    // MARK: - Form Helpers

    private func formSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(SBFont.capsLabel)
                .foregroundStyle(Color.sbWarm)
                .letterSpacing(1.5)
            content()
        }
    }

    private func sideButton(_ label: String, side value: Guest.GuestSide) -> some View {
        Button {
            side = value
            HapticEngine.selection()
        } label: {
            Text(label)
                .font(SBFont.inter(13, weight: .semibold))
                .foregroundStyle(side == value ? Color.sbGoldDk : Color.sbWarm)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(side == value ? Color.sbChampagne : Color.sbIvory2)
                .clipShape(RoundedRectangle(cornerRadius: SBRadius.small))
        }
        .buttonStyle(.plain)
    }

    private func rsvpButton(_ label: String, status: Guest.RSVPStatus, color: Color) -> some View {
        Button {
            rsvp = status
            HapticEngine.selection()
        } label: {
            HStack(spacing: 6) {
                Circle()
                    .fill(rsvp == status ? color : Color.sbWarm2)
                    .frame(width: 8, height: 8)
                Text(label)
                    .font(SBFont.inter(13, weight: .semibold))
                    .foregroundStyle(rsvp == status ? Color.sbCharcoal : Color.sbWarm)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(rsvp == status ? color.opacity(0.15) : Color.sbIvory2)
            .clipShape(RoundedRectangle(cornerRadius: SBRadius.small))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Actions

    private func loadGuest() {
        guard let guest else { return }
        name = guest.displayName
        email = guest.email ?? ""
        dietary = guest.dietary ?? ""
        notes = guest.notes ?? ""
        side = guest.side
        rsvp = guest.rsvp
        vip = guest.vip
        plusOne = guest.plusOne ?? false
        accessibility = guest.accessibility ?? ""
        selectedCategories = Set(guest.categories)
    }

    private func saveGuest() {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty else { return }

        let parts = trimmedName.split(separator: " ", maxSplits: 1)
        let firstName = String(parts.first ?? "")
        let lastName = parts.count > 1 ? String(parts.last ?? "") : nil

        let updatedGuest = Guest(
            id: guest?.id ?? UUID().uuidString,
            name: trimmedName,
            firstName: firstName,
            lastName: lastName,
            email: email.isEmpty ? nil : email,
            categories: Array(selectedCategories),
            dietary: dietary.isEmpty ? nil : dietary,
            notes: notes.isEmpty ? nil : notes,
            rsvp: rsvp,
            side: side,
            vip: vip,
            accessibility: accessibility.isEmpty ? nil : accessibility,
            plusOne: plusOne,
            party: guest?.party
        )

        guard var plan = appState.activePlan else { return }

        if isEditing {
            if let idx = plan.guests.firstIndex(where: { $0.id == updatedGuest.id }) {
                plan.guests[idx] = updatedGuest
            }
        } else {
            plan.guests.append(updatedGuest)
        }

        appState.activePlan = plan
        HapticEngine.success()

        Task {
            try? await appState.database.savePlanData(plan: plan)
        }

        onSave?(updatedGuest)
        dismiss()
    }

    private func deleteGuest() {
        guard let guest, var plan = appState.activePlan else { return }

        plan.guests.removeAll { $0.id == guest.id }
        // Also remove any seat assignments for this guest
        for i in plan.tables.indices {
            plan.tables[i].assignments.removeValue(forKey: guest.id)
        }

        appState.activePlan = plan
        HapticEngine.medium()

        Task {
            try? await appState.database.savePlanData(plan: plan)
        }

        dismiss()
    }
}

// MARK: - Flow Layout (for category chips)

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = layout(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = layout(proposal: proposal, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y), proposal: .unspecified)
        }
    }

    private func layout(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth && x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            positions.append(CGPoint(x: x, y: y))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
        }

        return (CGSize(width: maxWidth, height: y + rowHeight), positions)
    }
}

#Preview {
    GuestDetailSheet(guest: nil)
        .environment(AppState())
}

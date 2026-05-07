import SwiftUI

struct GuestDetailSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    let guest: Guest?  // nil = adding new guest
    var onSave: ((Guest) -> Void)?

    @State private var name = ""
    @State private var email = ""
    @State private var meal = ""
    @State private var dietary = ""
    @State private var notes = ""
    @State private var side: Guest.GuestSide = .none
    @State private var rsvp: Guest.RSVPStatus = .unknown
    @State private var vip = false
    @State private var plusOne = false
    @State private var isChild = false
    @State private var highChair = false
    @State private var accessibility = ""
    @State private var selectedCategories: Set<String> = []
    @State private var selectedDietaryTags: Set<String> = []
    @State private var showDeleteConfirm = false
    @State private var showTierLimitAlert = false
    @State private var showSoftWarningAlert = false

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

                    // Categories — pull from the plan's canonical category list
                    // (web stores categories as IDs; iOS preserves the raw
                    // category objects via SeatingPlan.rawCategories). Fall
                    // back to whatever's already on guests if no canonical
                    // list exists.
                    formSection("CATEGORIES") {
                        let categories = canonicalCategories()
                        FlowLayout(spacing: 8) {
                            ForEach(categories, id: \.id) { cat in
                                Button {
                                    if selectedCategories.contains(cat.id) {
                                        selectedCategories.remove(cat.id)
                                    } else {
                                        selectedCategories.insert(cat.id)
                                    }
                                } label: {
                                    SBChip(
                                        text: cat.name,
                                        variant: selectedCategories.contains(cat.id) ? .gold : .default
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    // Meal
                    formSection("MEAL") {
                        TextField("e.g. Beef, Fish, Vegetarian", text: $meal)
                            .font(SBFont.body)
                            .padding(14)
                            .background(Color.sbIvory2)
                            .clipShape(RoundedRectangle(cornerRadius: SBRadius.button))
                    }

                    // Dietary & Allergies (chips + free-text fallback)
                    formSection("DIETARY & ALLERGIES") {
                        VStack(alignment: .leading, spacing: 10) {
                            FlowLayout(spacing: 8) {
                                ForEach(DietaryTag.all, id: \.id) { tag in
                                    Button {
                                        if selectedDietaryTags.contains(tag.id) {
                                            selectedDietaryTags.remove(tag.id)
                                        } else {
                                            selectedDietaryTags.insert(tag.id)
                                        }
                                        HapticEngine.selection()
                                    } label: {
                                        Text("\(tag.emoji) \(tag.label)")
                                            .font(SBFont.bodySmall)
                                            .foregroundStyle(selectedDietaryTags.contains(tag.id) ? Color.white : Color.sbCharcoal)
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 6)
                                            .background(selectedDietaryTags.contains(tag.id) ? Color.sbCharcoal : Color.sbIvory2)
                                            .clipShape(Capsule())
                                    }
                                    .buttonStyle(.plain)
                                }
                            }

                            TextField("Other restriction or allergy note…", text: $dietary)
                                .font(SBFont.body)
                                .padding(12)
                                .background(Color.sbIvory2)
                                .clipShape(RoundedRectangle(cornerRadius: SBRadius.small))
                        }
                    }

                    // Contact / Notes
                    formSection("CONTACT & NOTES") {
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
                                    Text("VIP Guest").font(SBFont.body)
                                }
                            }
                            .tint(Color.sbGold)
                            .padding(.vertical, 8)

                            Divider()

                            Toggle(isOn: $isChild) {
                                HStack(spacing: 8) {
                                    Text("🧒")
                                    Text("Child").font(SBFont.body)
                                }
                            }
                            .tint(Color.sbGold)
                            .padding(.vertical, 8)

                            Divider()

                            Toggle(isOn: $highChair) {
                                HStack(spacing: 8) {
                                    Text("🪑")
                                    Text("High Chair (Baby)").font(SBFont.body)
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
            .alert("Guest Limit Reached", isPresented: $showTierLimitAlert) {
                Button("Upgrade") { appState.showUpgrade = true }
                Button("Not now", role: .cancel) {}
            } message: {
                let limits = appState.activePlanLimits
                let tier = appState.activePlanTier
                if appState.isActivePlanExpired {
                    Text("This event's pass has expired. Upgrade to keep seating guests.")
                } else {
                    Text("Your \(tier.displayName) plan supports seating up to \(limits.seatedGuests) guests. Upgrade for more.")
                }
            }
            .alert("You're at \(appState.activePlanLimits.seatedGuests * 8 / 10) of \(appState.activePlanLimits.seatedGuests) free guests", isPresented: $showSoftWarningAlert) {
                Button("Upgrade") { appState.showUpgrade = true }
                Button("Got it", role: .cancel) {}
            } message: {
                Text("Upgrade to seat up to 250 guests with AI seating included.")
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

    // MARK: - Categories source

    private func canonicalCategories() -> [(id: String, name: String)] {
        // Prefer the canonical list preserved on the plan via rawCategories
        // (matches what web authors). Fall back to ad-hoc strings on guests
        // for plans that have no rawCategories yet.
        if let raw = appState.activePlan?.rawCategories, !raw.isEmpty {
            return raw.compactMap { entry in
                guard let id = entry["id"]?.value as? String else { return nil }
                let name = (entry["name"]?.value as? String) ?? id
                return (id, name)
            }
        }
        let allStrings = appState.activePlan?.guests.flatMap(\.categories) ?? []
        let unique = Array(Set(allStrings)).sorted()
        return unique.map { (id: $0, name: $0) }
    }

    // MARK: - Actions

    private func loadGuest() {
        guard let guest else { return }
        name = guest.displayName
        email = guest.email ?? ""
        meal = guest.meal ?? ""
        dietary = guest.dietary ?? ""
        notes = guest.notes ?? ""
        side = guest.side
        rsvp = guest.rsvp
        vip = guest.vip
        plusOne = guest.plusOne ?? false
        isChild = guest.isChild ?? false
        highChair = guest.highChair ?? false
        accessibility = guest.accessibility ?? ""
        selectedCategories = Set(guest.categories)
        selectedDietaryTags = Set(guest.dietaryTags ?? [])
    }

    private func saveGuest() {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty else { return }

        let parts = trimmedName.split(separator: " ", maxSplits: 1)
        let firstName = String(parts.first ?? "")
        let lastName = parts.count > 1 ? String(parts.last ?? "") : nil

        // Preserve fields iOS doesn't author here (display, isBride/Groom
        // cached flags, groupIds, guestCreatedAt) by reading from the
        // existing guest if we have one.
        let existing = guest

        let updatedGuest = Guest(
            id: existing?.id ?? UUID().uuidString,
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
            party: existing?.party,
            display: existing?.display,
            dietaryTags: selectedDietaryTags.isEmpty ? nil : Array(selectedDietaryTags),
            highChair: highChair ? true : (existing?.highChair == false ? false : nil),
            isChild: isChild ? true : (existing?.isChild == false ? false : nil),
            groupIds: existing?.groupIds,
            isBride: existing?.isBride,
            isGroom: existing?.isGroom,
            meal: meal.isEmpty ? nil : meal,
            guestCreatedAt: existing?.guestCreatedAt
        )

        guard var plan = appState.activePlan else { return }

        if isEditing {
            if let idx = plan.guests.firstIndex(where: { $0.id == updatedGuest.id }) {
                plan.guests[idx] = updatedGuest
            }
        } else {
            // Web parity: adding guests to the list is never blocked.
            // The tier limit only applies when SEATING (assigning to tables).
            plan.guests.append(updatedGuest)
        }

        appState.activePlan = plan
        HapticEngine.success()

        // After a successful add, fire the 80% soft-warning nudge once per
        // session if the user has crossed the threshold on a free-tier plan.
        // Mirrors web's nudge at App.jsx:6211.
        if !isEditing
            && appState.activePlanTier == .free
            && plan.guests.count >= Int(Double(appState.activePlanLimits.seatedGuests) * 0.8)
            && !appState.hasShownGuestSoftWarning {
            appState.hasShownGuestSoftWarning = true
            showSoftWarningAlert = true
        }

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

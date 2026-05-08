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
    // Party assignment is a cross-cutting structure (lives on
    // plan.rawParties, not just the guest), so we mutate immediately
    // instead of waiting for the Save button — matches PartiesSheet's
    // model and means cancelling the form doesn't accidentally orphan a
    // party membership.
    @State private var showPartyPicker = false

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

                    // Party — show current party + quick assign / leave.
                    // Source of truth is `plan.rawParties` (web parity);
                    // `guest.party` is just a denormalised cache.
                    if isEditing { partySection }

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
            .onChange(of: showTierLimitAlert) { _, show in
                if show { showTierLimitAlert = false; appState.showUpgrade = true }
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

    // MARK: - Party section
    //
    // Shows the guest's current party membership and lets the user
    // assign / leave / create a solo party right from this sheet.
    // Mutations write to plan.rawParties immediately and persist —
    // see top-of-file note on why this is intentional.

    private var partySection: some View {
        formSection("PARTY") {
            VStack(alignment: .leading, spacing: 8) {
                if let current = currentParty() {
                    // Current-party pill — tap X to leave, name shows
                    // who else is in the party as a sub-line so the
                    // user can see context without leaving the sheet.
                    HStack(spacing: 8) {
                        Image(systemName: "person.3.fill")
                            .font(.system(size: 13))
                            .foregroundStyle(Color.sbGoldDk)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(current.name)
                                .font(SBFont.bodySmallBold)
                                .foregroundStyle(Color.sbCharcoal)
                            let others = otherMemberNames(in: current)
                            if !others.isEmpty {
                                Text("With \(others)")
                                    .font(SBFont.caption)
                                    .foregroundStyle(Color.sbWarm)
                                    .lineLimit(2)
                            } else {
                                Text("Just this guest")
                                    .font(SBFont.caption)
                                    .foregroundStyle(Color.sbWarm)
                            }
                        }
                        Spacer()
                        Button {
                            leaveCurrentParty()
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 18))
                                .foregroundStyle(Color.sbWarm2)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(12)
                    .background(Color.sbChampagne.opacity(0.4))
                    .clipShape(RoundedRectangle(cornerRadius: SBRadius.button))
                } else if showPartyPicker {
                    partyPickerInline
                } else {
                    Button {
                        showPartyPicker = true
                        HapticEngine.light()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "plus.circle")
                                .font(.system(size: 14))
                            Text("Add to a party")
                                .font(SBFont.bodySmall)
                        }
                        .foregroundStyle(Color.sbGoldDk)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.sbIvory2)
                        .clipShape(RoundedRectangle(cornerRadius: SBRadius.button))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    /// Inline picker shown when the guest has no party. Lists every
    /// existing party (tap to join) plus a "create solo party" option.
    /// Switching parties is intentionally a two-step flow — leave then
    /// re-add — to keep the data model clean (one-party-per-guest).
    private var partyPickerInline: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("PICK A PARTY")
                    .font(SBFont.capsLabel)
                    .foregroundStyle(Color.sbWarm)
                    .letterSpacing(1.5)
                Spacer()
                Button("Cancel") { showPartyPicker = false }
                    .font(SBFont.caption)
                    .foregroundStyle(Color.sbWarm)
            }

            let parties = canonicalParties()
            if parties.isEmpty {
                Text("No parties yet — create one below or open Parties & Groups.")
                    .font(SBFont.caption)
                    .foregroundStyle(Color.sbWarm)
                    .padding(.vertical, 4)
            } else {
                ForEach(parties, id: \.id) { p in
                    Button {
                        joinParty(id: p.id)
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "person.3.fill")
                                .font(.system(size: 12))
                                .foregroundStyle(Color.sbGold)
                            Text(p.name)
                                .font(SBFont.bodySmall)
                                .foregroundStyle(Color.sbCharcoal)
                            Spacer()
                            Text("\(p.guestIds.count)")
                                .font(SBFont.caption)
                                .foregroundStyle(Color.sbWarm)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 11))
                                .foregroundStyle(Color.sbWarm2)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .background(Color.sbIvory2)
                        .clipShape(RoundedRectangle(cornerRadius: SBRadius.small))
                    }
                    .buttonStyle(.plain)
                }
            }

            Button {
                createSoloParty()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .semibold))
                    Text("Create new party with just \(name.isEmpty ? "this guest" : firstName(name))")
                        .font(SBFont.caption)
                }
                .foregroundStyle(Color.sbGoldDk)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.sbChampagne.opacity(0.5))
                .clipShape(RoundedRectangle(cornerRadius: SBRadius.small))
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Party data helpers

    private func canonicalParties() -> [(id: String, name: String, guestIds: [String])] {
        guard let raw = appState.activePlan?.rawParties else { return [] }
        return raw.compactMap { entry -> (String, String, [String])? in
            guard let id = entry["id"]?.value as? String else { return nil }
            let pname = (entry["name"]?.value as? String) ?? ""
            let ids = (entry["guestIds"]?.value as? [String]) ?? []
            return (id, pname, ids)
        }
        .sorted { $0.1.localizedCaseInsensitiveCompare($1.1) == .orderedAscending }
    }

    private func currentParty() -> (id: String, name: String, guestIds: [String])? {
        guard let gid = guest?.id else { return nil }
        return canonicalParties().first { $0.guestIds.contains(gid) }
    }

    private func otherMemberNames(in party: (id: String, name: String, guestIds: [String])) -> String {
        guard let gid = guest?.id, let plan = appState.activePlan else { return "" }
        let byId = Dictionary(uniqueKeysWithValues: plan.guests.map { ($0.id, $0) })
        let names = party.guestIds
            .filter { $0 != gid }
            .compactMap { byId[$0]?.displayName }
            .filter { !$0.isEmpty }
        if names.isEmpty { return "" }
        if names.count <= 3 { return names.joined(separator: ", ") }
        return "\(names.prefix(2).joined(separator: ", ")) & \(names.count - 2) others"
    }

    private func firstName(_ s: String) -> String {
        s.split(separator: " ").first.map(String.init) ?? s
    }

    // MARK: - Party mutations
    //
    // All three mutate plan.rawParties + the affected guest.party
    // string (denormalised cache) + persist immediately. Same pattern
    // as PartiesSheet so the two surfaces stay in lockstep.

    private func joinParty(id partyId: String) {
        guard let gid = guest?.id, var p = appState.activePlan else { return }
        guard var raw = p.rawParties else { return }
        var partyName = ""
        for i in raw.indices where (raw[i]["id"]?.value as? String) == partyId {
            var ids = (raw[i]["guestIds"]?.value as? [String]) ?? []
            if !ids.contains(gid) { ids.append(gid) }
            raw[i]["guestIds"] = AnyCodable(ids)
            partyName = (raw[i]["name"]?.value as? String) ?? ""
        }
        p.rawParties = raw
        for i in p.guests.indices where p.guests[i].id == gid {
            p.guests[i].party = partyName
        }
        appState.activePlan = p
        showPartyPicker = false
        HapticEngine.success()
        Task { try? await appState.database.savePlanData(plan: p) }
    }

    private func leaveCurrentParty() {
        guard let gid = guest?.id, var p = appState.activePlan else { return }
        guard var raw = p.rawParties else { return }
        for i in raw.indices {
            var ids = (raw[i]["guestIds"]?.value as? [String]) ?? []
            ids.removeAll { $0 == gid }
            raw[i]["guestIds"] = AnyCodable(ids)
        }
        p.rawParties = raw
        for i in p.guests.indices where p.guests[i].id == gid {
            p.guests[i].party = nil
        }
        appState.activePlan = p
        HapticEngine.medium()
        Task { try? await appState.database.savePlanData(plan: p) }
    }

    private func createSoloParty() {
        guard let gid = guest?.id, var p = appState.activePlan else { return }
        let partyName = name.isEmpty ? "Party" : firstName(name)
        let entry: [String: AnyCodable] = [
            "id": AnyCodable(randomPartyId()),
            "name": AnyCodable(partyName),
            "guestIds": AnyCodable([gid]),
        ]
        var raw = p.rawParties ?? []
        raw.append(entry)
        p.rawParties = raw
        for i in p.guests.indices where p.guests[i].id == gid {
            p.guests[i].party = partyName
        }
        appState.activePlan = p
        showPartyPicker = false
        HapticEngine.success()
        Task { try? await appState.database.savePlanData(plan: p) }
    }

    private func randomPartyId() -> String {
        let chars = Array("abcdefghijklmnopqrstuvwxyz0123456789")
        return String((0..<9).compactMap { _ in chars.randomElement() })
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

        // The 80% soft-warning nudge previously lived here, tied to
        // adding guests to the list. Web parity (App.jsx:4470) gates on
        // the SEATED count instead — the unsorted list is unmetered.
        // EditorView fires the nudge from `assignGuest` /
        // `assignGuestToNextEmpty` when the seated count crosses 80%.

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

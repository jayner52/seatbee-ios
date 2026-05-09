import SwiftUI

// MARK: - Parties & Groups sheet
//
// Web parity: parties are stored as a canonical list on the plan
// (`plan.rawParties = [{id, name, guestIds}]`). Each guest can belong
// to at most one party. iOS used to read parties from the
// denormalised `guest.party` string field only — that meant
// web-created parties showed up with weird names (or not at all) and
// iOS-created parties never round-tripped to web. This sheet now uses
// `rawParties` as the source of truth and writes the party name into
// `guest.party` as a denormalised cache so legacy iOS code paths
// (Guest CSV export's Party column, etc.) keep working.
//
// UX:
//   - Pinned "+ Create Party" at the top (no scroll-to-find)
//   - Inline guest picker expands in place — search box, tappable
//     rows for guests not in any party yet, selected guests appear as
//     gold chips. Auto-named ("Alice & Bob") with an editable name
//     field. Create commits the new party.
//   - Existing party cards below; tap the name to rename inline; tap
//     the + to add more members via the same picker.

struct PartiesSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var creatingParty = false
    @State private var selectedGuestIds = Set<String>()
    @State private var customName = ""
    @State private var nameWasManuallyEdited = false
    @State private var pickerSearch = ""

    @State private var editingPartyId: String?
    @State private var editPartyName: String = ""

    @State private var addingToPartyId: String?
    @State private var addToPartySelected = Set<String>()
    @State private var addPickerSearch = ""

    private var plan: SeatingPlan? { appState.activePlan }
    private var allGuests: [Guest] { plan?.guests ?? [] }

    /// Canonical id → {name, guestIds} list, sorted alphabetically by
    /// name. Mirrors the lookup pattern from RulesView / CategoriesSheet.
    private var canonicalParties: [(id: String, name: String, guestIds: [String])] {
        guard let raw = plan?.rawParties else { return [] }
        return raw.compactMap { entry -> (String, String, [String])? in
            guard let id = entry["id"]?.value as? String else { return nil }
            let name = (entry["name"]?.value as? String) ?? ""
            let ids = (entry["guestIds"]?.value as? [String]) ?? []
            return (id, name, ids)
        }
        .sorted { $0.1.localizedCaseInsensitiveCompare($1.1) == .orderedAscending }
    }

    /// All guest IDs that belong to ANY party — used to filter the
    /// "create party" picker so a guest can only ever be in one party.
    private var assignedToPartyIds: Set<String> {
        var out = Set<String>()
        for p in canonicalParties { out.formUnion(p.guestIds) }
        return out
    }

    /// Parties whose `guestIds` is empty OR whose IDs all reference
    /// guests that no longer exist on the plan. These are leftovers
    /// from older iOS writes / prior web normalisation passes that
    /// dropped member references — they show "0 guests" and have no
    /// way to "fill" themselves, so they're noise the user wants
    /// cleared. We surface them explicitly + offer a one-tap purge.
    private var orphanParties: [(id: String, name: String, guestIds: [String])] {
        let livingIds = Set(allGuests.map(\.id))
        return canonicalParties.filter { p in
            p.guestIds.isEmpty || p.guestIds.allSatisfy { !livingIds.contains($0) }
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    // Always-visible Create CTA / inline picker
                    if creatingParty {
                        createPartyPicker
                    } else {
                        Button {
                            beginCreatingParty()
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "plus.circle.fill")
                                    .font(.system(size: 18, weight: .semibold))
                                Text("Create Party")
                                    .font(SBFont.bodySemibold)
                            }
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color.sbGoldDk)
                            .clipShape(RoundedRectangle(cornerRadius: SBRadius.button))
                        }
                        .buttonStyle(.plain)
                    }

                    // One-tap cleanup banner for orphan parties (no
                    // members or members that no longer exist).
                    if !orphanParties.isEmpty {
                        cleanupBanner
                    }

                    if canonicalParties.isEmpty && !creatingParty {
                        emptyState
                    }

                    ForEach(canonicalParties, id: \.id) { party in
                        partyCard(id: party.id, name: party.name, members: members(for: party.guestIds))
                    }

                    Spacer(minLength: 40)
                }
                .padding(.horizontal, SBSpacing.screenMargin)
                .padding(.top, 16)
            }
            .background(Color.sbIvory)
            // Floating Create Party bar — only attached while the
            // picker is active so it doesn't sit there occupying the
            // home-indicator strip the rest of the time.
            .safeAreaInset(edge: .bottom) {
                if creatingParty {
                    floatingCreateBar
                }
            }
            .navigationTitle("Parties & Groups")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Color.sbGoldDk)
                }
            }
        }
    }

    /// Soft warning + one-tap purge for parties with no live members.
    /// Lets the user clean up historical noise without manually
    /// trash-tapping each card.
    private var cleanupBanner: some View {
        let count = orphanParties.count
        return Button {
            cleanUpOrphanParties()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "sparkles")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.sbGoldDk)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(count) empty part\(count == 1 ? "y" : "ies")")
                        .font(SBFont.bodySmallBold)
                        .foregroundStyle(Color.sbCharcoal)
                    Text("Tap to remove parties with no members")
                        .font(SBFont.caption)
                        .foregroundStyle(Color.sbWarm)
                }
                Spacer()
                Text("CLEAN UP")
                    .font(SBFont.capsLabel)
                    .foregroundStyle(Color.sbGoldDk)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.sbChampagne)
                    .clipShape(Capsule())
            }
            .padding(12)
            .background(Color.sbChampagne.opacity(0.4))
            .clipShape(RoundedRectangle(cornerRadius: SBRadius.card))
            .overlay(
                RoundedRectangle(cornerRadius: SBRadius.card)
                    .strokeBorder(Color.sbGoldDk.opacity(0.3), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func cleanUpOrphanParties() {
        guard var p = plan else { return }
        guard var raw = p.rawParties else { return }
        let livingIds = Set(allGuests.map(\.id))
        let orphanIds = Set(orphanParties.map(\.id))
        raw.removeAll { entry in
            guard let id = entry["id"]?.value as? String else { return true }
            return orphanIds.contains(id)
        }
        p.rawParties = raw
        // Also clear any stale guest.party strings that pointed at an
        // orphan party (defensive — shouldn't be possible but harmless).
        for i in p.guests.indices {
            if let pname = p.guests[i].party,
               !raw.contains(where: { ($0["name"]?.value as? String) == pname }) {
                p.guests[i].party = nil
            }
        }
        _ = livingIds // silence unused
        appState.activePlan = p
        HapticEngine.success()
        Task { try? await appState.database.savePlanData(plan: p) }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "person.3")
                .font(.system(size: 40))
                .foregroundStyle(Color.sbWarm2)
            Text("No parties yet")
                .font(SBFont.displaySmall)
                .foregroundStyle(Color.sbCharcoal)
            Text("Group guests so they always sit together.\nTap Create Party above to start.")
                .font(SBFont.body)
                .foregroundStyle(Color.sbWarm)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    // MARK: - Create-party inline picker

    private var createPartyPicker: some View {
        let unassigned = unassignedToAnyParty()
        let filtered = applySearch(to: unassigned, query: pickerSearch)

        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("New Party")
                    .font(SBFont.bodySemibold)
                    .foregroundStyle(Color.sbCharcoal)
                Spacer()
                Button("Cancel") { cancelCreate() }
                    .font(SBFont.bodySmall)
                    .foregroundStyle(Color.sbWarm)
            }

            // Selected chips — tap to deselect
            if !selectedGuestIds.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(selectedGuestObjects(), id: \.id) { g in
                            Button {
                                selectedGuestIds.remove(g.id)
                                refreshAutoName()
                            } label: {
                                HStack(spacing: 4) {
                                    Text(displayShort(g))
                                        .font(SBFont.caption)
                                    Image(systemName: "xmark")
                                        .font(.system(size: 9, weight: .semibold))
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .foregroundStyle(.white)
                                .background(Color.sbGoldDk)
                                .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            // Editable party name (auto-filled, user can override)
            HStack {
                Image(systemName: "pencil")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.sbWarm2)
                TextField("Party name", text: $customName)
                    .font(SBFont.body)
                    .onChange(of: customName) { old, new in
                        // Treat any divergence from the auto-name as a
                        // manual edit; once flagged, we stop overwriting
                        // when the selection changes.
                        if new != autoName(forIds: selectedGuestIds) {
                            nameWasManuallyEdited = true
                        }
                    }
            }
            .padding(12)
            .background(Color.sbIvory2)
            .clipShape(RoundedRectangle(cornerRadius: SBRadius.button))

            // Search box for the picker
            HStack {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.sbWarm2)
                TextField("Search guests", text: $pickerSearch)
                    .font(SBFont.bodySmall)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color.sbIvory2)
            .clipShape(RoundedRectangle(cornerRadius: SBRadius.button))

            // Guest picker rows
            if filtered.isEmpty {
                Text(pickerSearch.isEmpty
                     ? "Every guest is already in a party."
                     : "No matching guests not already in a party.")
                    .font(SBFont.caption)
                    .foregroundStyle(Color.sbWarm)
                    .padding(.vertical, 12)
            } else {
                VStack(spacing: 4) {
                    ForEach(filtered, id: \.id) { g in
                        pickerRow(guest: g, selected: selectedGuestIds.contains(g.id)) {
                            toggle(g)
                        }
                    }
                }
            }

            // Commit lives outside this card, in a floating
            // safeAreaInset bar — see `floatingCreateBar` below — so
            // it stays visible no matter how far the user has scrolled
            // through the guest list.
        }
        .padding(14)
        .background(Color.sbChampagne.opacity(0.35))
        .clipShape(RoundedRectangle(cornerRadius: SBRadius.card))
        .overlay(
            RoundedRectangle(cornerRadius: SBRadius.card)
                .strokeBorder(Color.sbGoldDk.opacity(0.3), lineWidth: 1)
        )
    }

    /// Sticky bottom bar that floats over the scroll content while the
    /// create-party picker is open. Mounted via `.safeAreaInset(edge:
    /// .bottom)` on the ScrollView so it sits above the home indicator
    /// and never scrolls out of view — fixes the "I have to scroll to
    /// the very bottom of 200 guests to find the Create button" trap.
    private var floatingCreateBar: some View {
        VStack(spacing: 0) {
            // Soft fade so the button doesn't visually collide with
            // guest rows scrolling underneath.
            LinearGradient(
                colors: [Color.sbIvory.opacity(0), Color.sbIvory],
                startPoint: .top, endPoint: .bottom
            )
            .frame(height: 14)
            .allowsHitTesting(false)

            Button {
                commitCreate()
            } label: {
                let n = selectedGuestIds.count
                HStack(spacing: 8) {
                    Image(systemName: n == 0 ? "person.crop.circle.badge.plus" : "checkmark.circle.fill")
                        .font(.system(size: 16, weight: .semibold))
                    Text(n == 0 ? "Pick at least one guest"
                         : "Create Party (\(n))")
                        .font(SBFont.bodySemibold)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .foregroundStyle(.white)
                .background(n == 0 ? Color.sbWarm2 : Color.sbGoldDk)
                .clipShape(RoundedRectangle(cornerRadius: SBRadius.button))
            }
            .buttonStyle(.plain)
            .disabled(selectedGuestIds.isEmpty)
            .padding(.horizontal, SBSpacing.screenMargin)
            .padding(.bottom, 8)
            .background(Color.sbIvory)
        }
    }

    private func pickerRow(guest: Guest, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .strokeBorder(selected ? Color.sbGoldDk : Color.sbWarm2,
                                      lineWidth: selected ? 2 : 1)
                        .background(
                            Circle().fill(selected ? Color.sbGoldDk : Color.clear)
                        )
                        .frame(width: 18, height: 18)
                    if selected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
                SBAvatar(name: guest.displayName, size: 26)
                Text(guest.displayName)
                    .font(SBFont.bodySmall)
                    .foregroundStyle(Color.sbCharcoal)
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(selected ? Color.sbChampagne.opacity(0.6) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Existing party card (with rename + add members)

    private func partyCard(id: String, name: String, members: [Guest]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "person.3.fill")
                    .foregroundStyle(Color.sbGold)

                if editingPartyId == id {
                    TextField("Party name", text: $editPartyName, onCommit: {
                        commitRename(id: id)
                    })
                    .font(SBFont.bodySemibold)
                    .foregroundStyle(Color.sbCharcoal)
                    .submitLabel(.done)
                    .onSubmit { commitRename(id: id) }
                    Button("Save") { commitRename(id: id) }
                        .font(SBFont.bodySmall)
                        .foregroundStyle(Color.sbGoldDk)
                } else {
                    Button {
                        editingPartyId = id
                        editPartyName = name
                    } label: {
                        Text(name)
                            .font(SBFont.bodySemibold)
                            .foregroundStyle(Color.sbCharcoal)
                            .lineLimit(1)
                    }
                    .buttonStyle(.plain)
                }

                Spacer()

                Text("\(members.count)")
                    .font(SBFont.capsLabel)
                    .foregroundStyle(Color.sbGoldDk)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.sbChampagne)
                    .clipShape(RoundedRectangle(cornerRadius: 6))

                Button {
                    deleteParty(id: id)
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.sbWarm2)
                }
                .buttonStyle(.plain)
            }

            if members.isEmpty {
                // Explicit empty-state row — without this, an orphan
                // party reads as just a name with no body and the
                // user has no idea what's going on.
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.circle")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.sbWarm2)
                    Text("No members yet — add some below or tap the trash to remove this party")
                        .font(SBFont.caption)
                        .foregroundStyle(Color.sbWarm)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                ForEach(members, id: \.id) { guest in
                    HStack(spacing: 8) {
                        SBAvatar(name: guest.displayName, size: 24)
                        Text(guest.displayName)
                            .font(SBFont.bodySmall)
                            .foregroundStyle(Color.sbCharcoal)
                        Spacer()
                        Button {
                            removeMember(partyId: id, guestId: guest.id)
                        } label: {
                            Image(systemName: "minus.circle")
                                .font(.system(size: 14))
                                .foregroundStyle(Color.sbWarm2)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            // Add members affordance — opens an inline picker just for
            // unassigned guests (each guest can only be in one party).
            if addingToPartyId == id {
                addMembersPicker(partyId: id)
            } else {
                Button {
                    addingToPartyId = id
                    addToPartySelected.removeAll()
                    addPickerSearch = ""
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "plus")
                            .font(.system(size: 11, weight: .semibold))
                        Text("Add members")
                            .font(SBFont.caption)
                    }
                    .foregroundStyle(Color.sbGoldDk)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.sbChampagne.opacity(0.4))
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .background(Color.sbIvory2)
        .clipShape(RoundedRectangle(cornerRadius: SBRadius.card))
    }

    private func addMembersPicker(partyId: String) -> some View {
        let unassigned = unassignedToAnyParty()
        let filtered = applySearch(to: unassigned, query: addPickerSearch)

        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.sbWarm2)
                TextField("Search guests", text: $addPickerSearch)
                    .font(SBFont.bodySmall)
                    .autocorrectionDisabled()
                Button("Cancel") {
                    addingToPartyId = nil
                    addToPartySelected.removeAll()
                }
                .font(SBFont.caption)
                .foregroundStyle(Color.sbWarm)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color.sbIvory)
            .clipShape(RoundedRectangle(cornerRadius: SBRadius.small))

            if filtered.isEmpty {
                Text("No unassigned guests left.")
                    .font(SBFont.caption)
                    .foregroundStyle(Color.sbWarm)
                    .padding(.vertical, 6)
            } else {
                VStack(spacing: 4) {
                    ForEach(filtered, id: \.id) { g in
                        pickerRow(
                            guest: g,
                            selected: addToPartySelected.contains(g.id)
                        ) {
                            if addToPartySelected.contains(g.id) {
                                addToPartySelected.remove(g.id)
                            } else {
                                addToPartySelected.insert(g.id)
                            }
                        }
                    }
                }
            }

            Button {
                commitAddMembers(partyId: partyId)
            } label: {
                Text(addToPartySelected.isEmpty
                     ? "Pick at least one"
                     : "Add \(addToPartySelected.count)")
                    .font(SBFont.bodySmallBold)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .foregroundStyle(.white)
                    .background(addToPartySelected.isEmpty ? Color.sbWarm2 : Color.sbGoldDk)
                    .clipShape(RoundedRectangle(cornerRadius: SBRadius.small))
            }
            .buttonStyle(.plain)
            .disabled(addToPartySelected.isEmpty)
        }
        .padding(8)
        .background(Color.sbChampagne.opacity(0.25))
        .clipShape(RoundedRectangle(cornerRadius: SBRadius.small))
    }

    // MARK: - Helpers

    private func unassignedToAnyParty() -> [Guest] {
        let assigned = assignedToPartyIds
        // Hide declined guests from the add-to-party picker — they
        // wouldn't be seated, so adding them would be misleading.
        // Existing party members who later decline stay in the party
        // (Option A — see displayMembers / declined-dim treatment in
        // partyRow), they just can't be newly added.
        return allGuests.filter { !assigned.contains($0.id) && $0.rsvp != .no }
    }

    private func applySearch(to guests: [Guest], query: String) -> [Guest] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        let base = guests.sorted {
            $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }
        if q.isEmpty { return base }
        return base.filter { $0.displayName.lowercased().contains(q) }
    }

    private func members(for ids: [String]) -> [Guest] {
        let byId = Dictionary(uniqueKeysWithValues: allGuests.map { ($0.id, $0) })
        return ids.compactMap { byId[$0] }
    }

    private func selectedGuestObjects() -> [Guest] {
        let byId = Dictionary(uniqueKeysWithValues: allGuests.map { ($0.id, $0) })
        return selectedGuestIds.compactMap { byId[$0] }
            .sorted { $0.displayName < $1.displayName }
    }

    /// First name for compact party-name building. Falls back to the
    /// full display name if there's no space (single-word names).
    private func displayShort(_ g: Guest) -> String {
        let name = g.displayName
        if let first = name.split(separator: " ").first {
            return String(first)
        }
        return name
    }

    /// Auto-name format for a set of selected guest IDs, ordered by
    /// display name to keep the result deterministic regardless of
    /// selection order.
    ///   - 0:   ""
    ///   - 1:   "Alice"
    ///   - 2:   "Alice & Bob"
    ///   - 3:   "Alice, Bob & Carol"
    ///   - 4+:  "Alice, Bob & 2 others"
    private func autoName(forIds ids: Set<String>) -> String {
        let byId = Dictionary(uniqueKeysWithValues: allGuests.map { ($0.id, $0) })
        let names = ids.compactMap { byId[$0] }
            .sorted { $0.displayName < $1.displayName }
            .map { displayShort($0) }
        switch names.count {
        case 0:  return ""
        case 1:  return names[0]
        case 2:  return "\(names[0]) & \(names[1])"
        case 3:  return "\(names[0]), \(names[1]) & \(names[2])"
        default:
            let head = names.prefix(2).joined(separator: ", ")
            let rest = names.count - 2
            return "\(head) & \(rest) others"
        }
    }

    private func refreshAutoName() {
        guard !nameWasManuallyEdited else { return }
        customName = autoName(forIds: selectedGuestIds)
    }

    private func toggle(_ g: Guest) {
        if selectedGuestIds.contains(g.id) {
            selectedGuestIds.remove(g.id)
        } else {
            selectedGuestIds.insert(g.id)
        }
        refreshAutoName()
        HapticEngine.selection()
    }

    private func beginCreatingParty() {
        selectedGuestIds = []
        customName = ""
        nameWasManuallyEdited = false
        pickerSearch = ""
        creatingParty = true
        HapticEngine.light()
    }

    private func cancelCreate() {
        creatingParty = false
        selectedGuestIds = []
        customName = ""
        nameWasManuallyEdited = false
    }

    // MARK: - Mutations

    /// Pushes a new party into `rawParties` and writes the canonical
    /// name into each member's `guest.party` denormalised field. Saves
    /// the plan. ID format matches web (9-char base36 random).
    private func commitCreate() {
        guard !selectedGuestIds.isEmpty, var p = plan else { return }
        let trimmed = customName.trimmingCharacters(in: .whitespaces)
        let finalName = trimmed.isEmpty ? autoName(forIds: selectedGuestIds) : trimmed
        guard !finalName.isEmpty else { return }

        let id = randomPartyId()
        let entry: [String: AnyCodable] = [
            "id": AnyCodable(id),
            "name": AnyCodable(finalName),
            "guestIds": AnyCodable(Array(selectedGuestIds)),
        ]
        var raw = p.rawParties ?? []
        raw.append(entry)
        p.rawParties = raw

        for i in p.guests.indices where selectedGuestIds.contains(p.guests[i].id) {
            p.guests[i].party = finalName
        }

        appState.activePlan = p
        cancelCreate()
        HapticEngine.success()
        Task { try? await appState.database.savePlanData(plan: p) }
    }

    private func commitRename(id: String) {
        let trimmed = editPartyName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, var p = plan else {
            editingPartyId = nil
            return
        }
        guard var raw = p.rawParties else { editingPartyId = nil; return }
        var memberIds: [String] = []
        for i in raw.indices where (raw[i]["id"]?.value as? String) == id {
            raw[i]["name"] = AnyCodable(trimmed)
            memberIds = (raw[i]["guestIds"]?.value as? [String]) ?? []
        }
        p.rawParties = raw
        for i in p.guests.indices where memberIds.contains(p.guests[i].id) {
            p.guests[i].party = trimmed
        }
        appState.activePlan = p
        editingPartyId = nil
        HapticEngine.medium()
        Task { try? await appState.database.savePlanData(plan: p) }
    }

    private func commitAddMembers(partyId: String) {
        guard !addToPartySelected.isEmpty, var p = plan else { return }
        guard var raw = p.rawParties else { return }
        var partyName = ""
        for i in raw.indices where (raw[i]["id"]?.value as? String) == partyId {
            var ids = (raw[i]["guestIds"]?.value as? [String]) ?? []
            for newId in addToPartySelected where !ids.contains(newId) {
                ids.append(newId)
            }
            raw[i]["guestIds"] = AnyCodable(ids)
            partyName = (raw[i]["name"]?.value as? String) ?? ""
        }
        p.rawParties = raw
        for i in p.guests.indices where addToPartySelected.contains(p.guests[i].id) {
            p.guests[i].party = partyName
        }
        appState.activePlan = p
        addingToPartyId = nil
        addToPartySelected.removeAll()
        HapticEngine.success()
        Task { try? await appState.database.savePlanData(plan: p) }
    }

    private func removeMember(partyId: String, guestId: String) {
        guard var p = plan else { return }
        guard var raw = p.rawParties else { return }
        for i in raw.indices where (raw[i]["id"]?.value as? String) == partyId {
            var ids = (raw[i]["guestIds"]?.value as? [String]) ?? []
            ids.removeAll { $0 == guestId }
            raw[i]["guestIds"] = AnyCodable(ids)
        }
        p.rawParties = raw
        for i in p.guests.indices where p.guests[i].id == guestId {
            p.guests[i].party = nil
        }
        appState.activePlan = p
        HapticEngine.medium()
        Task { try? await appState.database.savePlanData(plan: p) }
    }

    private func deleteParty(id: String) {
        guard var p = plan else { return }
        guard var raw = p.rawParties else { return }
        var memberIds: [String] = []
        for entry in raw where (entry["id"]?.value as? String) == id {
            memberIds = (entry["guestIds"]?.value as? [String]) ?? []
        }
        raw.removeAll { ($0["id"]?.value as? String) == id }
        p.rawParties = raw
        for i in p.guests.indices where memberIds.contains(p.guests[i].id) {
            p.guests[i].party = nil
        }
        appState.activePlan = p
        HapticEngine.medium()
        Task { try? await appState.database.savePlanData(plan: p) }
    }

    private func randomPartyId() -> String {
        let chars = Array("abcdefghijklmnopqrstuvwxyz0123456789")
        return String((0..<9).compactMap { _ in chars.randomElement() })
    }
}

#Preview {
    PartiesSheet()
        .environment(AppState())
}

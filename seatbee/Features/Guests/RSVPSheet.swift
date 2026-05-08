import SwiftUI

// MARK: - RSVP management sheet
//
// Surface for getting an event's RSVP picture sorted in one place,
// instead of clicking into Edit Guest for every guest individually.
// Mirrors the Meals sheet pattern: counts at top, full guest list,
// per-row quick-set, multi-select for bulk operations.
//
// Adds the "Include {N} unconfirmed in seating" preference (web parity:
// App.jsx:10513) — controls whether guests with rsvp=pending/unknown
// flow into AI seating, exports, and the unassigned counter. Web has
// always honoured this; iOS now persists the same plan-level field.

struct RSVPSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var selectionMode = false
    @State private var selectedGuestIds: Set<String> = []
    @State private var bulkSetterOpen = false
    @State private var bulkSetterStatus: Guest.RSVPStatus = .yes

    private var plan: SeatingPlan? { appState.activePlan }
    private var guests: [Guest] { plan?.guests ?? [] }

    /// Web treats null/maybe rsvp as "unconfirmed". iOS stores .pending
    /// and .unknown for the same idea — group both as "unconfirmed" so
    /// the includeMaybes toggle and counts behave the same as web.
    private static func isUnconfirmed(_ rsvp: Guest.RSVPStatus) -> Bool {
        rsvp == .pending || rsvp == .unknown
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: SBSpacing.sectionGap) {
                    countsSummary
                    includeMaybesToggle
                    selectionToolbar
                    guestList
                    Spacer(minLength: 80)
                }
                .padding(.horizontal, SBSpacing.screenMargin)
                .padding(.top, SBSpacing.screenMargin)
            }
            .background(Color.sbIvory)
            .navigationTitle("RSVP")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Color.sbGoldDk)
                }
                ToolbarItem(placement: .primaryAction) {
                    Button(selectionMode ? "Cancel" : "Select") {
                        withAnimation(.seatbee) {
                            selectionMode.toggle()
                            if !selectionMode { selectedGuestIds.removeAll() }
                        }
                    }
                    .foregroundStyle(Color.sbCharcoal)
                }
            }
            .safeAreaInset(edge: .bottom) {
                if selectionMode && !selectedGuestIds.isEmpty {
                    bulkActionBar
                }
            }
            .confirmationDialog(
                "Set RSVP for \(selectedGuestIds.count) guest\(selectedGuestIds.count == 1 ? "" : "s")",
                isPresented: $bulkSetterOpen,
                titleVisibility: .visible
            ) {
                Button("Yes (Attending)") { applyBulk(.yes) }
                Button("Pending") { applyBulk(.pending) }
                Button("No (Declined)", role: .destructive) { applyBulk(.no) }
                Button("Cancel", role: .cancel) {}
            }
        }
    }

    // MARK: - Counts summary

    private var countsSummary: some View {
        let yes = guests.filter { $0.rsvp == .yes }.count
        let unconfirmed = guests.filter { Self.isUnconfirmed($0.rsvp) }.count
        let no = guests.filter { $0.rsvp == .no }.count
        return HStack(spacing: 0) {
            countCell(value: yes, label: "Yes", color: .sbSage)
            Spacer(); Divider().frame(height: 30)
            Spacer()
            countCell(value: unconfirmed, label: "Pending", color: .sbGoldDk)
            Spacer(); Divider().frame(height: 30)
            Spacer()
            countCell(value: no, label: "No", color: .sbError)
        }
        .padding(14)
        .background(Color.sbIvory2)
        .clipShape(RoundedRectangle(cornerRadius: SBRadius.button))
    }

    private func countCell(value: Int, label: String, color: Color) -> some View {
        VStack(alignment: .center, spacing: 2) {
            Text("\(value)")
                .font(SBFont.displayLarge)
                .foregroundStyle(color)
            Text(label.uppercased())
                .font(SBFont.capsLabel)
                .foregroundStyle(Color.sbWarm)
                .letterSpacing(1.5)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Include unconfirmed toggle

    /// "Include {N} unconfirmed in seating" — drives whether AI seating,
    /// exports, and the unassigned counter pull in pending/unknown
    /// guests. Mirrors the same option from web's seating sidebar.
    @ViewBuilder
    private var includeMaybesToggle: some View {
        let unconfirmedCount = guests.filter { Self.isUnconfirmed($0.rsvp) }.count
        if unconfirmedCount > 0 {
            let included = (plan?.includeMaybes ?? true)
            Button {
                togglIncludeMaybes()
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: included ? "checkmark.square.fill" : "square")
                        .font(.system(size: 20))
                        .foregroundStyle(included ? Color.sbGoldDk : Color.sbWarm2)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Include \(unconfirmedCount) unconfirmed in seating")
                            .font(SBFont.bodySmallBold)
                            .foregroundStyle(Color.sbCharcoal)
                        Text(included
                             ? "AI seating + exports include these guests."
                             : "Excluded from seating. Existing assignments preserved.")
                            .font(SBFont.caption)
                            .foregroundStyle(Color.sbWarm)
                    }
                    Spacer()
                    if !included {
                        Text("EXCLUDED")
                            .font(SBFont.capsLabel)
                            .foregroundStyle(Color.sbError)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.sbError.opacity(0.12))
                            .clipShape(Capsule())
                    }
                }
                .padding(12)
                .background(Color.sbChampagne.opacity(0.5))
                .clipShape(RoundedRectangle(cornerRadius: SBRadius.button))
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Selection toolbar

    @ViewBuilder
    private var selectionToolbar: some View {
        if selectionMode {
            HStack(spacing: 8) {
                Button {
                    if selectedGuestIds.count == guests.count {
                        selectedGuestIds.removeAll()
                    } else {
                        selectedGuestIds = Set(guests.map { $0.id })
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: selectedGuestIds.count == guests.count
                              ? "checkmark.square.fill" : "square")
                            .font(.system(size: 14))
                        Text(selectedGuestIds.count == guests.count ? "Deselect all" : "Select all")
                            .font(SBFont.caption)
                    }
                    .foregroundStyle(Color.sbGoldDk)
                }
                Spacer()
                Text("\(selectedGuestIds.count) selected")
                    .font(SBFont.caption)
                    .foregroundStyle(Color.sbWarm)
            }
            .padding(.horizontal, 4)
        }
    }

    // MARK: - Guest list

    private var guestList: some View {
        VStack(spacing: 6) {
            ForEach(guests) { g in
                guestRow(g)
            }
        }
    }

    private func guestRow(_ g: Guest) -> some View {
        let isSelected = selectedGuestIds.contains(g.id)
        return HStack(spacing: 12) {
            if selectionMode {
                Button {
                    if isSelected { selectedGuestIds.remove(g.id) }
                    else { selectedGuestIds.insert(g.id) }
                    HapticEngine.selection()
                } label: {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(isSelected ? Color.sbGoldDk : Color.sbWarm2)
                        .font(.system(size: 20))
                }
                .buttonStyle(.plain)
            }
            SBAvatar(name: g.displayName, size: 32)
            Text(g.displayName)
                .font(SBFont.bodySmallBold)
                .foregroundStyle(Color.sbCharcoal)
                .lineLimit(1)
            Spacer()
            if !selectionMode {
                rsvpSegmentedToggle(g)
            } else {
                rsvpStatusPill(g.rsvp)
            }
        }
        .padding(10)
        .background(isSelected ? Color.sbChampagne.opacity(0.5) : Color.white)
        .overlay(
            RoundedRectangle(cornerRadius: SBRadius.button)
                .strokeBorder(isSelected ? Color.sbGoldDk : Color.sbLine, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: SBRadius.button))
        .contentShape(Rectangle())
        .onTapGesture {
            if selectionMode {
                if isSelected { selectedGuestIds.remove(g.id) }
                else { selectedGuestIds.insert(g.id) }
                HapticEngine.selection()
            }
        }
    }

    /// Three small pills — Y / P / N — with the active one highlighted.
    /// Tap to set immediately. Faster than opening Edit Guest, and
    /// keyboard-free.
    private func rsvpSegmentedToggle(_ g: Guest) -> some View {
        HStack(spacing: 4) {
            rsvpButton(g: g, status: .yes, label: "Yes", tint: .sbSage)
            rsvpButton(g: g, status: .pending, label: "Pending", tint: .sbGoldDk)
            rsvpButton(g: g, status: .no, label: "No", tint: .sbError)
        }
    }

    private func rsvpButton(g: Guest, status: Guest.RSVPStatus, label: String, tint: Color) -> some View {
        let on = (g.rsvp == status)
                || (status == .pending && Self.isUnconfirmed(g.rsvp))   // .pending button covers pending+unknown
        return Button {
            applyToGuest(g.id, status: status)
        } label: {
            Text(label)
                .font(SBFont.caption)
                .foregroundStyle(on ? Color.white : tint)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(on ? tint : Color.white)
                .overlay(
                    Capsule().strokeBorder(tint.opacity(on ? 1 : 0.4), lineWidth: 1)
                )
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func rsvpStatusPill(_ rsvp: Guest.RSVPStatus) -> some View {
        let (label, color): (String, Color) = {
            switch rsvp {
            case .yes:     return ("Yes", .sbSage)
            case .pending, .unknown: return ("Pending", .sbGoldDk)
            case .no:      return ("No", .sbError)
            }
        }()
        return Text(label)
            .font(SBFont.caption)
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.12))
            .clipShape(Capsule())
    }

    // MARK: - Bulk action bar

    private var bulkActionBar: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 10) {
                SBButton(title: "Set RSVP for \(selectedGuestIds.count)", icon: "envelope.badge",
                         variant: .gold, fullWidth: true) {
                    bulkSetterOpen = true
                }
            }
            .padding(.horizontal, SBSpacing.screenMargin)
            .padding(.vertical, 12)
            .background(Color.sbIvory)
        }
    }

    // MARK: - Mutations

    private func applyToGuest(_ id: String, status: Guest.RSVPStatus) {
        guard var p = plan else { return }
        guard let idx = p.guests.firstIndex(where: { $0.id == id }) else { return }
        p.guests[idx].rsvp = status
        appState.activePlan = p
        let snap = p
        Task { try? await appState.database.savePlanData(plan: snap) }
        HapticEngine.success()
    }

    private func applyBulk(_ status: Guest.RSVPStatus) {
        guard var p = plan else { return }
        for id in selectedGuestIds {
            guard let idx = p.guests.firstIndex(where: { $0.id == id }) else { continue }
            p.guests[idx].rsvp = status
        }
        appState.activePlan = p
        let snap = p
        Task { try? await appState.database.savePlanData(plan: snap) }
        HapticEngine.success()
        withAnimation(.seatbee) {
            selectionMode = false
            selectedGuestIds.removeAll()
        }
    }

    private func togglIncludeMaybes() {
        guard var p = plan else { return }
        let current = p.includeMaybes ?? true
        p.includeMaybes = !current
        appState.activePlan = p
        let snap = p
        Task { try? await appState.database.savePlanData(plan: snap) }
        HapticEngine.selection()
    }
}

#Preview {
    RSVPSheet()
        .environment(AppState())
}

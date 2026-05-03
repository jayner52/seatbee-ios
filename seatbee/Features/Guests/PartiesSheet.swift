import SwiftUI

struct PartiesSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var showAddParty = false
    @State private var newPartyName = ""

    // Derive parties from guest.party field
    private var parties: [String: [Guest]] {
        guard let guests = appState.activePlan?.guests else { return [:] }
        var result: [String: [Guest]] = [:]
        for guest in guests {
            if let party = guest.party, !party.isEmpty {
                result[party, default: []].append(guest)
            }
        }
        return result
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if parties.isEmpty && !showAddParty {
                        VStack(spacing: 16) {
                            Spacer().frame(height: 40)
                            Image(systemName: "person.3")
                                .font(.system(size: 40))
                                .foregroundStyle(Color.sbWarm2)
                            Text("No parties yet")
                                .font(SBFont.displaySmall)
                                .foregroundStyle(Color.sbCharcoal)
                            Text("Group guests into families or parties so they stay together")
                                .font(SBFont.body)
                                .foregroundStyle(Color.sbWarm)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                    }

                    ForEach(Array(parties.keys.sorted()), id: \.self) { partyName in
                        partyCard(name: partyName, members: parties[partyName] ?? [])
                    }

                    // Add party
                    if showAddParty {
                        VStack(spacing: 12) {
                            TextField("Party name (e.g. 'The Chens')", text: $newPartyName)
                                .font(SBFont.body)
                                .padding(14)
                                .background(Color.sbIvory2)
                                .clipShape(RoundedRectangle(cornerRadius: SBRadius.button))

                            HStack {
                                SBButton(title: "Cancel", variant: .ghost, size: .small) {
                                    showAddParty = false
                                    newPartyName = ""
                                }
                                SBButton(title: "Create Party", variant: .gold, size: .small) {
                                    createParty()
                                }
                                .disabled(newPartyName.trimmingCharacters(in: .whitespaces).isEmpty)
                            }
                        }
                    }

                    SBButton(title: "New Party", icon: "plus", variant: .gold, fullWidth: true) {
                        showAddParty = true
                    }

                    Spacer(minLength: 40)
                }
                .padding(.horizontal, SBSpacing.screenMargin)
                .padding(.top, 16)
            }
            .background(Color.sbIvory)
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

    private func partyCard(name: String, members: [Guest]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "person.3.fill")
                    .foregroundStyle(Color.sbGold)
                Text(name)
                    .font(SBFont.bodySemibold)
                    .foregroundStyle(Color.sbCharcoal)
                Spacer()
                Text("\(members.count)")
                    .font(SBFont.capsLabel)
                    .foregroundStyle(Color.sbGoldDk)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.sbChampagne)
                    .clipShape(RoundedRectangle(cornerRadius: 6))

                Button {
                    deleteParty(name)
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.sbWarm2)
                }
                .buttonStyle(.plain)
            }

            ForEach(members) { guest in
                HStack(spacing: 8) {
                    SBAvatar(name: guest.displayName, size: 24)
                    Text(guest.displayName)
                        .font(SBFont.bodySmall)
                        .foregroundStyle(Color.sbCharcoal)
                }
            }
        }
        .padding(14)
        .background(Color.sbIvory2)
        .clipShape(RoundedRectangle(cornerRadius: SBRadius.card))
    }

    private func createParty() {
        let name = newPartyName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        // Party created — users assign guests to it via GuestDetailSheet
        newPartyName = ""
        showAddParty = false
        HapticEngine.success()
    }

    private func deleteParty(_ name: String) {
        guard var plan = appState.activePlan else { return }
        for i in plan.guests.indices {
            if plan.guests[i].party == name {
                plan.guests[i].party = nil
            }
        }
        appState.activePlan = plan
        HapticEngine.medium()
        Task { try? await appState.database.savePlanData(plan: plan) }
    }
}

#Preview {
    PartiesSheet()
        .environment(AppState())
}

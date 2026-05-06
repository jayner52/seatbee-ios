import SwiftUI

struct GuestPickerSheet: View {
    @Environment(AppState.self) private var appState
    let guests: [Guest]
    let tables: [SeatTable]
    let onSelect: (Guest) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""

    private var unseatedGuests: [Guest] {
        let seatedIds = Set(tables.flatMap { $0.assignments.keys })
        let filtered = guests.filter { !seatedIds.contains($0.id) }
        if searchText.isEmpty { return filtered }
        return filtered.filter { $0.displayName.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Search
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 15))
                        .foregroundStyle(Color.sbWarm)
                    TextField("Search guests...", text: $searchText)
                        .font(SBFont.body)
                        .textInputAutocapitalization(.never)
                }
                .padding(12)
                .background(Color.sbIvory2)
                .clipShape(Capsule())
                .padding(.horizontal, SBSpacing.screenMargin)
                .padding(.top, 12)

                if unseatedGuests.isEmpty {
                    Spacer()
                    VStack(spacing: 8) {
                        Image(systemName: "person.slash")
                            .font(.system(size: 32))
                            .foregroundStyle(Color.sbWarm2)
                        Text(searchText.isEmpty ? "All guests are seated!" : "No matching guests")
                            .font(SBFont.body)
                            .foregroundStyle(Color.sbWarm)
                    }
                    Spacer()
                } else {
                    List(unseatedGuests) { guest in
                        Button {
                            onSelect(guest)
                            dismiss()
                        } label: {
                            HStack(spacing: 12) {
                                SBAvatar(name: guest.displayName, size: 32)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(guest.displayName)
                                        .font(SBFont.bodySmallBold)
                                        .foregroundStyle(Color.sbCharcoal)
                                    if let label = appState.activePlan?.displayCategoryLabel(for: guest) {
                                        Text(label)
                                            .font(SBFont.caption)
                                            .foregroundStyle(Color.sbWarm)
                                    }
                                }
                                Spacer()
                                if guest.rsvp == .yes {
                                    Circle()
                                        .fill(Color.sbSage)
                                        .frame(width: 8, height: 8)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                        .listRowBackground(Color.sbIvory)
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
            }
            .background(Color.sbIvory)
            .navigationTitle("Assign Guest")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Color.sbGoldDk)
                }
            }
        }
    }
}

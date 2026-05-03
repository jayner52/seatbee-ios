import SwiftUI
import Auth

struct SettingsSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var showSignOutConfirm = false
    @State private var showDeletePlanConfirm = false

    var body: some View {
        NavigationStack {
            List {
                // Account
                Section {
                    if let user = appState.auth.currentUser {
                        HStack(spacing: 12) {
                            SBAvatar(name: user.email ?? "User", size: 40)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(user.email ?? "Signed in")
                                    .font(SBFont.bodySmallBold)
                                    .foregroundStyle(Color.sbCharcoal)
                                Text("Seatbee Account")
                                    .font(SBFont.caption)
                                    .foregroundStyle(Color.sbWarm)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                } header: {
                    Text("Account")
                }

                // Plan management
                if appState.activePlan != nil {
                    Section {
                        Button {
                            showDeletePlanConfirm = true
                        } label: {
                            HStack {
                                Image(systemName: "trash")
                                    .foregroundStyle(Color.sbError)
                                Text("Delete Active Plan")
                                    .foregroundStyle(Color.sbError)
                            }
                        }
                    } header: {
                        Text("Active Plan")
                    }
                }

                // App info
                Section {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("1.0.0")
                            .foregroundStyle(Color.sbWarm)
                    }
                    HStack {
                        Text("Platform")
                        Spacer()
                        Text("iOS")
                            .foregroundStyle(Color.sbWarm)
                    }

                    Link(destination: URL(string: "https://seatbee.app")!) {
                        HStack {
                            Text("Visit seatbee.app")
                            Spacer()
                            Image(systemName: "arrow.up.right")
                                .font(.system(size: 12))
                                .foregroundStyle(Color.sbWarm)
                        }
                    }

                    Link(destination: URL(string: "mailto:hello@seatbee.app")!) {
                        HStack {
                            Text("Contact Support")
                            Spacer()
                            Image(systemName: "envelope")
                                .font(.system(size: 12))
                                .foregroundStyle(Color.sbWarm)
                        }
                    }
                } header: {
                    Text("About")
                }

                // Sign out
                Section {
                    Button {
                        showSignOutConfirm = true
                    } label: {
                        HStack {
                            Spacer()
                            Text("Sign Out")
                                .font(SBFont.bodySemibold)
                                .foregroundStyle(Color.sbError)
                            Spacer()
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Color.sbIvory)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Color.sbGoldDk)
                }
            }
            .alert("Sign Out?", isPresented: $showSignOutConfirm) {
                Button("Sign Out", role: .destructive) {
                    Task {
                        await appState.auth.signOut()
                        dismiss()
                    }
                }
                Button("Cancel", role: .cancel) {}
            }
            .alert("Delete Plan?", isPresented: $showDeletePlanConfirm) {
                Button("Delete", role: .destructive) {
                    deletePlan()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will permanently delete \"\(appState.activePlan?.name ?? "this plan")\". This cannot be undone.")
            }
        }
    }

    private func deletePlan() {
        guard let plan = appState.activePlan else { return }
        Task {
            try? await appState.database.deletePlan(id: plan.id)
            appState.activePlan = nil
            appState.selectedTab = .plans
            HapticEngine.medium()
        }
        dismiss()
    }
}

#Preview {
    SettingsSheet()
        .environment(AppState())
}

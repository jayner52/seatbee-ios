import SwiftUI
import Auth

struct SettingsSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var showSignOutConfirm = false
    @State private var showDeletePlanConfirm = false
    @State private var showDeleteAccountConfirm = false
    @State private var deletingAccount = false
    @State private var deleteAccountError: String?

    // Profile-backed state — loaded from `profiles` on appear and
    // written live to Supabase on every change. Mirrors web's
    // AccountSettings (App.jsx ~25241–25272).
    @State private var emailMarketingOptIn = false
    @State private var selectedRoles: Set<String> = []
    @State private var profileLoaded = false
    @State private var profileDisplayName: String? = nil

    // Web parity: role IDs must match App.jsx line 22633 exactly.
    private static let roleOptions: [(id: String, label: String, icon: String)] = [
        ("bride_groom",    "Bride or Groom",               "heart.fill"),
        ("event_host",     "Event Host",                   "person.fill"),
        ("wedding_planner","Professional Wedding Planner",  "briefcase.fill"),
        ("wedding_vendor", "Wedding Vendor",               "storefront.fill"),
    ]

    var body: some View {
        NavigationStack {
            List {
                // Account
                Section {
                    if let user = appState.auth.currentUser {
                        let displayName = profileDisplayName ?? appState.auth.displayName
                        HStack(spacing: 12) {
                            SBAvatar(
                                name: displayName ?? user.email ?? "User",
                                size: 40,
                                photoURL: appState.auth.avatarURL
                            )
                            VStack(alignment: .leading, spacing: 2) {
                                if let name = displayName, !name.isEmpty {
                                    Text(name)
                                        .font(SBFont.bodySmallBold)
                                        .foregroundStyle(Color.sbCharcoal)
                                    Text(user.email ?? "Seatbee Account")
                                        .font(SBFont.caption)
                                        .foregroundStyle(Color.sbWarm)
                                } else {
                                    Text(user.email ?? "Signed in")
                                        .font(SBFont.bodySmallBold)
                                        .foregroundStyle(Color.sbCharcoal)
                                    Text("Seatbee Account")
                                        .font(SBFont.caption)
                                        .foregroundStyle(Color.sbWarm)
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                } header: {
                    Text("Account")
                }

                // Event Passes
                if appState.auth.currentUser != nil {
                    Section {
                        NavigationLink {
                            EventPassesView()
                                .environment(appState)
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "ticket")
                                    .foregroundStyle(Color.sbGoldDk)
                                    .frame(width: 24)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Event Passes")
                                        .foregroundStyle(Color.sbCharcoal)
                                    if appState.activePlanTier != .free {
                                        Text("This plan: \(appState.activePlanTier.displayName)")
                                            .font(SBFont.caption)
                                            .foregroundStyle(Color.sbGoldDk)
                                    }
                                }
                                Spacer()
                                if appState.userPasses.summary.available > 0 {
                                    Text("\(appState.userPasses.summary.available) available")
                                        .font(SBFont.caption)
                                        .foregroundStyle(Color.sbGoldDk)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 3)
                                        .background(Color.sbGold.opacity(0.15))
                                        .clipShape(Capsule())
                                }
                            }
                        }
                        // The "Upgrade Plan" tile that used to live here
                        // was removed — it pointed at web's pricing page
                        // and read as a duplicate route next to Event
                        // Passes (applying a pass IS how a plan
                        // upgrades on iOS). The Redeem-a-Gift-Code flow
                        // lives inside Event Passes itself, surfaced at
                        // the top of that view; no need for a separate
                        // top-level tile cluttering Settings.
                    } header: {
                        Text("Passes")
                    }
                }

                // Notifications — marketing email toggle. Web parity
                // (App.jsx AccountSettings ~25241).
                Section {
                    Toggle(isOn: $emailMarketingOptIn) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Marketing emails")
                                .foregroundStyle(Color.sbCharcoal)
                            Text("Venue tips, planning guides, product updates.")
                                .font(SBFont.caption)
                                .foregroundStyle(Color.sbWarm)
                        }
                    }
                    .tint(Color.sbGold)
                    .onChange(of: emailMarketingOptIn) { _, newValue in
                        guard profileLoaded else { return }
                        Task { await appState.auth.updateEmailMarketingOptIn(newValue) }
                    }
                } header: {
                    Text("Notifications")
                }

                // Role multi-select. Web parity (App.jsx ~25261).
                Section {
                    ForEach(Self.roleOptions, id: \.id) { opt in
                        let active = selectedRoles.contains(opt.id)
                        Button {
                            if active { selectedRoles.remove(opt.id) }
                            else      { selectedRoles.insert(opt.id) }
                            HapticEngine.selection()
                            // Persist after every toggle so the switch
                            // reads as immediately-saved (matches web).
                            Task { await appState.auth.updateUserRoles(Array(selectedRoles)) }
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: opt.icon)
                                    .foregroundStyle(active ? Color.sbGoldDk : Color.sbWarm)
                                    .frame(width: 24)
                                Text(opt.label)
                                    .foregroundStyle(Color.sbCharcoal)
                                Spacer()
                                Image(systemName: active ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(active ? Color.sbGold : Color.sbWarm2)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    Text("I am a…")
                } footer: {
                    Text("Pick any that apply. Helps us tailor tips and templates.")
                }

                // Active Event — rich card mirroring web AccountSettings
                // (App.jsx ~25094). Shows tier badge, optional date /
                // venue / table count, seated-guest progress, and
                // feature flags. Tapping the card returns to the editor.
                if let plan = appState.activePlan {
                    Section {
                        activeEventCard(plan)
                        Button {
                            showDeletePlanConfirm = true
                        } label: {
                            HStack(spacing: 8) {
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

                // Legal — Apple App Store 5.1.1 requires Privacy
                // Policy + Terms of Service to be reachable in-app,
                // not just on first signup.
                Section {
                    Link(destination: URL(string: "https://seatbee.app/privacy")!) {
                        HStack {
                            Text("Privacy Policy")
                            Spacer()
                            Image(systemName: "arrow.up.right")
                                .font(.system(size: 12))
                                .foregroundStyle(Color.sbWarm)
                        }
                    }
                    Link(destination: URL(string: "https://seatbee.app/terms")!) {
                        HStack {
                            Text("Terms of Service")
                            Spacer()
                            Image(systemName: "arrow.up.right")
                                .font(.system(size: 12))
                                .foregroundStyle(Color.sbWarm)
                        }
                    }
                } header: {
                    Text("Legal")
                }

                // Sign out + Delete account
                // Apple App Store 5.1.1(v) requires in-app account
                // deletion for any app that creates user accounts.
                // Calls AuthService.deleteAccount → /api/delete-account
                // on web, which runs the same admin-panel delete
                // sequence scoped to the requesting user.
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
                    Button {
                        showDeleteAccountConfirm = true
                    } label: {
                        HStack {
                            Spacer()
                            Text("Delete Account")
                                .font(SBFont.bodySemibold)
                                .foregroundStyle(Color.sbError)
                            Spacer()
                        }
                    }
                    .disabled(deletingAccount)
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
            .task {
                // Load the profile once on first appear. The
                // `profileLoaded` gate prevents the .onChange writers
                // from firing when we hydrate the toggle / role state.
                if let p = await appState.auth.loadProfile() {
                    emailMarketingOptIn = p.email_marketing_opt_in ?? false
                    selectedRoles = Set(p.user_roles ?? [])
                }
                // Fetch name separately so a missing DB column never
                // breaks role/marketing loading above.
                profileDisplayName = await appState.auth.loadFullName()
                profileLoaded = true
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
            .alert("Delete account?", isPresented: $showDeleteAccountConfirm) {
                Button("Delete", role: .destructive) {
                    runDeleteAccount()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This permanently deletes your account, every plan you've created, and any passes you own. This cannot be undone.")
            }
            .alert(
                "Couldn't delete account",
                isPresented: Binding(
                    get: { deleteAccountError != nil },
                    set: { if !$0 { deleteAccountError = nil } }
                ),
                presenting: deleteAccountError
            ) { _ in
                Button("OK") { deleteAccountError = nil }
            } message: { msg in
                Text(msg)
            }
        }
    }

    /// Kicks off the network call. Set `deletingAccount` so the
    /// button disables for the duration; on success the AppRouter
    /// will route back to auth automatically as soon as
    /// AuthService.currentUser flips to nil.
    private func runDeleteAccount() {
        guard !deletingAccount else { return }
        deletingAccount = true
        Task {
            do {
                try await appState.auth.deleteAccount()
                deletingAccount = false
                dismiss()
            } catch {
                deletingAccount = false
                deleteAccountError = error.localizedDescription
            }
        }
    }

    // MARK: - Active event card (web parity, App.jsx ~25094)

    @ViewBuilder
    private func activeEventCard(_ plan: SeatingPlan) -> some View {
        let tier = appState.activePlanTier
        let limits = appState.activePlanLimits
        let isPaid = tier != .free
        let seated = plan.guests.count
        let cap = limits.seatedGuests
        let progress = cap > 0 ? min(1.0, Double(seated) / Double(cap)) : 0
        let overCap = seated >= cap

        Button {
            // Tap returns to the editor for this plan.
            appState.selectedTab = .edit
            dismiss()
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                // Title row: event name + optional tier badge
                HStack(alignment: .top, spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(plan.name)
                            .font(SBFont.bodySemibold)
                            .foregroundStyle(Color.sbCharcoal)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                        if isPaid, let daysLeft = daysRemaining(plan) {
                            Text("\(tier.displayName) · \(daysLeft) days remaining")
                                .font(SBFont.caption)
                                .foregroundStyle(Color.sbGoldDk)
                        } else if isPaid {
                            Text(tier.displayName)
                                .font(SBFont.caption)
                                .foregroundStyle(Color.sbGoldDk)
                        } else {
                            Text("Free Plan")
                                .font(SBFont.caption)
                                .foregroundStyle(Color.sbWarm)
                        }
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.sbGoldDk)
                }

                // Event facts (date / venue / table count)
                if plan.eventDate != nil || (plan.venue?.isEmpty == false) || !plan.tables.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        if let date = plan.eventDate {
                            factRow(icon: "calendar",
                                    text: date.formatted(date: .long, time: .omitted))
                        }
                        if let venue = plan.venue, !venue.isEmpty {
                            factRow(icon: "mappin.and.ellipse", text: venue)
                        }
                        if !plan.tables.isEmpty {
                            factRow(icon: "square.stack.3d.up",
                                    text: "\(plan.tables.count) \(plan.tables.count == 1 ? "table" : "tables")")
                        }
                    }
                }

                // Seated guests progress
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Seated guests")
                            .font(SBFont.caption)
                            .foregroundStyle(Color.sbWarm)
                        Spacer()
                        Text("\(seated) / \(cap)")
                            .font(SBFont.caption)
                            .foregroundStyle(Color.sbCharcoal)
                    }
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Color.sbCharcoal.opacity(0.10))
                            Capsule()
                                .fill(overCap ? Color.sbError.opacity(0.8) : Color.sbGold)
                                .frame(width: geo.size.width * progress)
                        }
                    }
                    .frame(height: 6)
                }

                // Feature flags — mirrors web's tierLimits booleans
                VStack(alignment: .leading, spacing: 3) {
                    featureRow("AI auto-seating",        on: limits.aiGenerate)
                    featureRow("AI floor plan detection",on: limits.aiFloorPlan)
                    featureRow("Watermark-free exports", on: isPaid)
                    featureRow("Invite collaborators",   on: isPaid)
                }
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }

    private func factRow(icon: String, text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundStyle(Color.sbWarm.opacity(0.7))
                .frame(width: 14)
            Text(text)
                .font(SBFont.caption)
                .foregroundStyle(Color.sbCharcoal2)
                .lineLimit(1)
        }
    }

    private func featureRow(_ label: String, on: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: on ? "checkmark.circle.fill" : "xmark.circle")
                .font(.system(size: 11))
                .foregroundStyle(on ? Color.sbSage : Color.sbCharcoal.opacity(0.3))
                .frame(width: 14)
            Text(label)
                .font(SBFont.caption)
                .foregroundStyle(on ? Color.sbCharcoal2 : Color.sbWarm)
        }
    }

    /// Whole days between now and the plan's pass expiry. Nil for plans
    /// with no expiry on file (e.g. free plans).
    private func daysRemaining(_ plan: SeatingPlan) -> Int? {
        guard let exp = plan.eventPassExpiresAt else { return nil }
        let secs = exp.timeIntervalSince(Date())
        guard secs > 0 else { return 0 }
        return Int(secs / 86_400)
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

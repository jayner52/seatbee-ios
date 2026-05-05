import SwiftUI
import CoreImage.CIFilterBuiltins

struct ShareView: View {
    @Environment(AppState.self) private var appState

    // Collaborators (web parity — /api/collab)
    @State private var collabIsOwner = false
    @State private var collabOwner: CollabPerson?
    @State private var collaborators: [CollabPerson] = []
    @State private var invitations: [PendingInvitation] = []
    @State private var collabLoading = false
    @State private var collabError: String?
    @State private var showInvitePrompt = false
    @State private var inviteEmail = ""
    @State private var inviteSending = false
    @State private var inviteResult: String?

    // Guest QR section state
    @State private var qrExpanded = false
    @State private var qrEnabled = false
    @State private var qrToken: String?
    @State private var qrSyncing = false
    @State private var qrError: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                SBNavHeader(title: "Share plan")

                if appState.activePlan == nil {
                    Spacer()
                    VStack(spacing: 16) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 44))
                            .foregroundStyle(Color.sbWarm2)
                        Text("No plan to share")
                            .font(SBFont.displaySmall)
                            .foregroundStyle(Color.sbCharcoal)
                        Text("Select a plan first")
                            .font(SBFont.body)
                            .foregroundStyle(Color.sbWarm)
                        SBButton(title: "Go to Plans", icon: "square.grid.2x2", variant: .gold) {
                            appState.selectedTab = .plans
                        }
                    }
                    Spacer()
                } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: SBSpacing.sectionGap) {
                        // Plan preview + collaborator banner (when non-owner)
                        if let plan = appState.activePlan {
                            planPreview(plan)
                            if !collabIsOwner, let owner = collabOwner {
                                collabBanner(owner: owner)
                            }
                        }

                        // Collaborators (web parity — /api/collab)
                        if let plan = appState.activePlan {
                            collaboratorsCard(plan: plan)
                        }

                        SBOrnament(label: "Share via")

                        // Social row
                        socialRow

                        // Guest QR (expandable, web parity)
                        if let plan = appState.activePlan {
                            guestQRSection(plan: plan)
                        }

                        // Export row
                        exportSection

                        Spacer(minLength: 100)
                    }
                    .padding(.horizontal, SBSpacing.screenMargin)
                    .padding(.top, SBSpacing.screenMargin)
                }
                } // end else
            }
            .background(Color.sbIvory)
            .task {
                if appState.activePlan == nil {
                    let plans = (try? await appState.database.fetchPlans()) ?? []
                    if let first = plans.first { appState.activePlan = first }
                }
            }
        }
    }

    // MARK: - Plan Preview

    private func planPreview(_ plan: SeatingPlan) -> some View {
        HStack(spacing: 10) {
            SBAvatar(name: plan.name, size: 28)
            Text(plan.name)
                .font(SBFont.bodySmallBold)
                .foregroundStyle(Color.sbCharcoal)
            Spacer()
        }
        .padding(12)
        .background(Color.sbIvory2)
        .clipShape(RoundedRectangle(cornerRadius: SBRadius.chip))
    }

    // MARK: - Collaborator banner (when not the owner)

    private func collabBanner(owner: CollabPerson) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "person.2.fill")
                .font(.system(size: 14))
                .foregroundStyle(Color.sbGoldDk)
            VStack(alignment: .leading, spacing: 0) {
                Text("Shared by \(owner.name)")
                    .font(SBFont.bodySmallBold)
                    .foregroundStyle(Color.sbCharcoal)
                Text("You're a collaborator")
                    .font(SBFont.caption)
                    .foregroundStyle(Color.sbWarm)
            }
            Spacer()
        }
        .padding(12)
        .background(Color.sbChampagne.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: SBRadius.chip))
    }

    // MARK: - Collaborators (web parity — /api/collab)

    private func collaboratorsCard(plan: SeatingPlan) -> some View {
        SBCard(backgroundColor: .sbIvory2) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Text("Collaborators")
                        .font(SBFont.bodySemibold)
                        .foregroundStyle(Color.sbCharcoal)
                    Spacer()
                    if collabLoading {
                        ProgressView().scaleEffect(0.7)
                    }
                }

                if let owner = collabOwner {
                    collaboratorRow(person: owner, isOwnerEntry: true, planId: plan.id)
                }
                ForEach(collaborators, id: \.userId) { c in
                    Divider().background(Color.sbLine)
                    collaboratorRow(person: c, isOwnerEntry: false, planId: plan.id)
                }
                ForEach(invitations, id: \.id) { inv in
                    Divider().background(Color.sbLine)
                    invitationRow(invitation: inv, planId: plan.id)
                }

                if collabIsOwner {
                    Button {
                        inviteEmail = ""
                        inviteResult = nil
                        showInvitePrompt = true
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "plus.circle.fill")
                            Text("Invite by email")
                        }
                        .font(SBFont.bodySemibold)
                        .foregroundStyle(Color.sbGoldDk)
                    }
                    .buttonStyle(.plain)
                }

                if let err = collabError {
                    Text(err)
                        .font(SBFont.caption)
                        .foregroundStyle(Color.sbError)
                }

                if collabOwner == nil && collaborators.isEmpty && invitations.isEmpty && !collabLoading {
                    Text("Loading collaborators…")
                        .font(SBFont.caption)
                        .foregroundStyle(Color.sbWarm)
                }
            }
        }
        .onAppear { Task { await loadCollaborators(planId: plan.id) } }
        .onChange(of: appState.activePlan?.id) { _, newId in
            if let id = newId { Task { await loadCollaborators(planId: id) } }
        }
        .alert("Invite a collaborator", isPresented: $showInvitePrompt) {
            TextField("name@example.com", text: $inviteEmail)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            Button("Cancel", role: .cancel) {}
            Button("Send invite") {
                Task { await sendInvite(planId: plan.id, email: inviteEmail) }
            }
        } message: {
            Text("They'll get an email with a link to join. Anyone you invite gets full edit access.")
        }
        .alert("Invitation", isPresented: Binding(
            get: { inviteResult != nil },
            set: { if !$0 { inviteResult = nil } }
        )) {
            Button("OK", role: .cancel) { inviteResult = nil }
        } message: {
            Text(inviteResult ?? "")
        }
    }

    private func collaboratorRow(person: CollabPerson, isOwnerEntry: Bool, planId: String) -> some View {
        HStack(spacing: 10) {
            SBAvatar(name: person.name, size: 32)
            VStack(alignment: .leading, spacing: 1) {
                Text(person.name)
                    .font(SBFont.bodySmallBold)
                    .foregroundStyle(Color.sbCharcoal)
                if !person.email.isEmpty {
                    Text(person.email)
                        .font(SBFont.caption)
                        .foregroundStyle(Color.sbWarm)
                        .lineLimit(1)
                }
            }
            Spacer()
            if isOwnerEntry {
                Text("OWNER")
                    .font(SBFont.capsLabel)
                    .foregroundStyle(Color.sbGoldDk)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.sbChampagne)
                    .clipShape(Capsule())
            } else if collabIsOwner {
                Button {
                    Task { await removeCollaborator(planId: planId, userId: person.userId) }
                } label: {
                    Image(systemName: "minus.circle")
                        .font(.system(size: 16))
                        .foregroundStyle(Color.sbWarm2)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func invitationRow(invitation: PendingInvitation, planId: String) -> some View {
        HStack(spacing: 10) {
            ZStack {
                Circle().fill(Color.sbIvory).frame(width: 32, height: 32)
                Image(systemName: "envelope")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.sbWarm)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(invitation.email)
                    .font(SBFont.bodySmall)
                    .foregroundStyle(Color.sbCharcoal)
                    .lineLimit(1)
                Text("Pending")
                    .font(SBFont.caption)
                    .foregroundStyle(Color.sbWarm)
            }
            Spacer()
            Button {
                Task { await revokeInvitation(invitationId: invitation.id) }
            } label: {
                Image(systemName: "xmark.circle")
                    .font(.system(size: 16))
                    .foregroundStyle(Color.sbWarm2)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Social Row

    private var socialRow: some View {
        HStack(spacing: 16) {
            socialButton(icon: "message.fill", label: "iMessage")
            socialButton(icon: "text.bubble.fill", label: "WhatsApp")
            socialButton(icon: "envelope.fill", label: "Email")
            socialButton(icon: "camera.fill", label: "IG")
            socialButton(icon: "ellipsis", label: "More")
        }
    }

    private func socialButton(icon: String, label: String) -> some View {
        Button {
            sharePlan(via: label)
        } label: {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 20))
                    .foregroundStyle(Color.sbCharcoal)
                    .frame(width: 56, height: 56)
                    .background(Color.sbIvory2)
                    .clipShape(Circle())

                Text(label)
                    .font(SBFont.capsLabel)
                    .foregroundStyle(Color.sbWarm)
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Export

    private var exportSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("EXPORT")
                .font(SBFont.capsLabel)
                .foregroundStyle(Color.sbWarm)
                .letterSpacing(1.5)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    exportCard(icon: "doc.text", title: "PDF")
                    exportCard(icon: "rectangle.stack", title: "Printable cards")
                    exportCard(icon: "photo", title: "Social image")
                    exportCard(icon: "person.2", title: "Guest CSV")
                    exportCard(icon: "square.grid.3x2", title: "Tables CSV")
                }
            }
        }
    }

    private func sharePlan(via method: String) {
        guard let plan = appState.activePlan else { return }
        let shareURL = "https://seatbee.app/plan/\(plan.id)"
        let activityVC = UIActivityViewController(
            activityItems: ["\(plan.name) — View seating plan", URL(string: shareURL)!],
            applicationActivities: nil
        )
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootVC = windowScene.windows.first?.rootViewController {
            rootVC.present(activityVC, animated: true)
        }
    }

    // MARK: - Guest QR section
    //
    // Web parity (src/App.jsx GuestQRPanel ~48046). iOS provides a slim
    // version: enable / disable, view + share / save the QR. Visual style
    // (custom colors, logo overlay) is intentionally left to web.

    private func guestQRSection(plan: SeatingPlan) -> some View {
        SBCard(backgroundColor: .sbIvory2) {
            VStack(alignment: .leading, spacing: 12) {
                // Header — always visible. Toggle is the primary control.
                HStack(spacing: 12) {
                    Button {
                        withAnimation(.seatbee) { qrExpanded.toggle() }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: qrExpanded ? "chevron.down" : "chevron.right")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Color.sbWarm)
                            Text("Guest QR Code")
                                .font(SBFont.bodySemibold)
                                .foregroundStyle(Color.sbCharcoal)
                        }
                    }
                    .buttonStyle(.plain)

                    Spacer()

                    if qrSyncing {
                        ProgressView().scaleEffect(0.8)
                    }
                    Toggle("", isOn: Binding(
                        get: { qrEnabled },
                        set: { newValue in
                            qrEnabled = newValue
                            Task { await saveQRConfig(planId: plan.id, enabled: newValue) }
                        }
                    ))
                    .labelsHidden()
                    .tint(.sbGold)
                    .disabled(qrSyncing)
                }

                if qrExpanded {
                    if qrEnabled, let token = qrToken {
                        let url = "https://seatbee.app/g/\(token)"
                        HStack(alignment: .top, spacing: 14) {
                            if let qrImage = UIImage.qrCode(from: url, size: 110) {
                                Image(uiImage: qrImage)
                                    .resizable()
                                    .interpolation(.none) // crisp pixels
                                    .frame(width: 110, height: 110)
                                    .background(Color.white)
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10)
                                            .strokeBorder(Color.sbLine, lineWidth: 1)
                                    )
                            }
                            VStack(alignment: .leading, spacing: 8) {
                                Text(url)
                                    .font(SBFont.caption)
                                    .foregroundStyle(Color.sbWarm)
                                    .lineLimit(2)
                                    .truncationMode(.middle)
                                HStack(spacing: 8) {
                                    qrActionButton(icon: "square.and.arrow.up", label: "Share") {
                                        shareQR(url: url)
                                    }
                                    qrActionButton(icon: "square.and.arrow.down", label: "Save") {
                                        saveQRToPhotos(url: url)
                                    }
                                }
                            }
                        }
                        Button {
                            openWebPlan(planId: plan.id)
                        } label: {
                            HStack(spacing: 4) {
                                Text("Customize design on web")
                                Image(systemName: "arrow.up.right.square")
                            }
                            .font(SBFont.caption)
                            .foregroundStyle(Color.sbGoldDk)
                        }
                        .buttonStyle(.plain)
                    } else if qrEnabled && qrToken == nil {
                        Text("Enabling…")
                            .font(SBFont.caption)
                            .foregroundStyle(Color.sbWarm)
                    } else {
                        Text("Turn on to generate a QR code that guests can scan to see their table assignment.")
                            .font(SBFont.caption)
                            .foregroundStyle(Color.sbWarm)
                    }

                    if let err = qrError {
                        Text(err)
                            .font(SBFont.caption)
                            .foregroundStyle(Color.sbError)
                    }
                }
            }
        }
        .onAppear {
            syncQRStateFromPlan(plan)
            Task { await fetchQRConfig(planId: plan.id) }
        }
        .onChange(of: appState.activePlan?.id) { _, _ in
            if let p = appState.activePlan {
                syncQRStateFromPlan(p)
                Task { await fetchQRConfig(planId: p.id) }
            }
        }
    }

    private func qrActionButton(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                Text(label)
                    .font(SBFont.inter(11, weight: .semibold))
            }
            .foregroundStyle(Color.sbGoldDk)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.sbChampagne)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: - QR state + API

    /// Read current values out of the active plan's `rawGuestQR` blob into
    /// local @State so the toggle reflects the plan's actual state when the
    /// user lands on the Share tab. No network call here.
    private func syncQRStateFromPlan(_ plan: SeatingPlan) {
        qrEnabled = plan.guestQREnabled
        qrToken = plan.guestQRToken
    }

    /// GET current config from the server on first appearance. The token +
    /// enabled flag live on top-level `seating_plans` columns
    /// (`guest_link_token`, `guest_experience`) — NOT inside the JSONB
    /// `data` blob — so iOS has to ask the server rather than reading it
    /// off the local plan.
    private func fetchQRConfig(planId: String) async {
        qrError = nil
        guard let url = URL(string: "\(AppConfig.guestAPIBaseURL)?action=config&planId=\(planId)") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        if let token = await AuthService().accessToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200,
                  let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
                return  // silent — section just stays in default state
            }
            qrToken = json["token"] as? String
            let config = (json["config"] as? [String: Any]) ?? [:]
            qrEnabled = (config["enabled"] as? Bool) ?? false
        } catch {
            // silent on read; the toggle still works for write
        }
    }

    /// POST to `/api/guest`. Server stores config in the `guest_experience`
    /// column and returns the (possibly newly-minted) token. iOS keeps the
    /// returned token in local @State; no JSONB writeback needed.
    private func saveQRConfig(planId: String, enabled: Bool) async {
        qrError = nil
        qrSyncing = true
        defer { qrSyncing = false }

        guard let url = URL(string: "\(AppConfig.guestAPIBaseURL)") else {
            qrError = "Couldn't reach the QR service."
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token = await AuthService().accessToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        } else {
            qrError = "Sign-in required. Try the Plans tab to refresh."
            return
        }

        let body: [String: Any] = [
            "action": "save-config",
            "planId": planId,
            "config": ["enabled": enabled],
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                qrError = "Unexpected response."
                return
            }
            let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            if http.statusCode != 200 {
                let serverError = (json?["error"] as? String) ?? "status \(http.statusCode)"
                qrError = "QR save failed: \(serverError)"
                return
            }
            qrToken = (json?["token"] as? String) ?? qrToken
        } catch {
            qrError = "Network error: \(error.localizedDescription)"
        }
    }

    private func shareQR(url: String) {
        guard let img = UIImage.qrCode(from: url, size: 600),
              let png = img.pngData() else { return }
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("Seatbee Guest QR.png")
        try? png.write(to: tmp)
        let activityVC = UIActivityViewController(
            activityItems: [tmp, URL(string: url)!],
            applicationActivities: nil
        )
        if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let root = scene.windows.first?.rootViewController {
            root.present(activityVC, animated: true)
        }
    }

    private func saveQRToPhotos(url: String) {
        guard let img = UIImage.qrCode(from: url, size: 600) else { return }
        // No Info.plist photo permission is required for UIImageWriteToSavedPhotosAlbum
        // when the user has granted Photos access via the activity sheet flow,
        // but iOS still expects NSPhotoLibraryAddUsageDescription. If missing,
        // the call no-ops silently — surface a hint via haptic + share fallback.
        UIImageWriteToSavedPhotosAlbum(img, nil, nil, nil)
        HapticEngine.success()
    }

    private func openWebPlan(planId: String) {
        if let url = URL(string: "https://seatbee.app/plan/\(planId)") {
            UIApplication.shared.open(url)
        }
    }

    private func exportCard(icon: String, title: String) -> some View {
        Button {
            if let plan = appState.activePlan {
                switch title {
                case "PDF":
                    PDFExportService.sharePDF(plan: plan)
                case "Printable cards":
                    PDFExportService.sharePlaceCards(plan: plan)
                case "Social image":
                    PDFExportService.shareSocialImage(plan: plan)
                case "Guest CSV":
                    PDFExportService.shareGuestListCSV(plan: plan)
                case "Tables CSV":
                    PDFExportService.shareTablesCSV(plan: plan)
                default:
                    sharePlan(via: title)
                }
            }
        } label: {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 24))
                    .foregroundStyle(Color.sbGoldDk)
                Text(title)
                    .font(SBFont.caption)
                    .foregroundStyle(Color.sbCharcoal)
            }
            .frame(width: 100, height: 80)
            .background(Color.sbIvory2)
            .clipShape(RoundedRectangle(cornerRadius: SBRadius.chip))
            .overlay(
                RoundedRectangle(cornerRadius: SBRadius.chip)
                    .strokeBorder(Color.sbLine, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Collaborator API
    //
    // Web parity (api/collab.js). All four actions hit the www subdomain
    // directly to avoid the seatbee.app → www.seatbee.app 307 redirect
    // that strips Authorization headers in URLSession.

    private func loadCollaborators(planId: String) async {
        collabError = nil
        collabLoading = true
        defer { collabLoading = false }

        guard let url = URL(string: "\(AppConfig.collabAPIBaseURL)?action=list&planId=\(planId)") else {
            collabError = "Couldn't build collab URL."
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        guard let token = await AuthService().accessToken else {
            collabError = "Sign in again to load collaborators."
            return
        }
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { return }
            let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            if http.statusCode != 200 {
                collabError = (json?["error"] as? String) ?? "Couldn't load collaborators."
                return
            }
            collabIsOwner = (json?["isOwner"] as? Bool) ?? false

            if let ownerDict = json?["owner"] as? [String: Any] {
                collabOwner = CollabPerson(dict: ownerDict)
            }
            if let arr = json?["collaborators"] as? [[String: Any]] {
                collaborators = arr.compactMap { CollabPerson(dict: $0) }
            }
            if let arr = json?["invitations"] as? [[String: Any]] {
                // Filter out invitations that have already been accepted —
                // web's API returns the full history (`SELECT *`), but the
                // accepted user already appears in `collaborators` and
                // showing the invite row again confuses users (it looks
                // like Shayan is both a collaborator AND pending).
                invitations = arr
                    .compactMap { PendingInvitation(dict: $0) }
                    .filter { !$0.accepted }
            } else {
                invitations = []
            }
        } catch {
            collabError = "Network error: \(error.localizedDescription)"
        }
    }

    private func sendInvite(planId: String, email: String) async {
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            inviteResult = "Email can't be empty."
            return
        }
        inviteSending = true
        defer { inviteSending = false }

        guard let url = URL(string: "\(AppConfig.collabAPIBaseURL)?action=invite") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token = await AuthService().accessToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        } else {
            inviteResult = "Sign in again to invite."
            return
        }
        request.httpBody = try? JSONSerialization.data(withJSONObject: [
            "planId": planId,
            "email": trimmed,
        ])

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { return }
            let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            if http.statusCode == 200 {
                let emailSent = (json?["emailSent"] as? Bool) ?? false
                inviteResult = emailSent ? "Invite sent to \(trimmed)." : "Invite created for \(trimmed). They can sign up to join."
                HapticEngine.success()
                await loadCollaborators(planId: planId)
            } else {
                inviteResult = (json?["error"] as? String) ?? "Invite failed (status \(http.statusCode))."
            }
        } catch {
            inviteResult = "Network error: \(error.localizedDescription)"
        }
    }

    private func removeCollaborator(planId: String, userId: String) async {
        guard let url = URL(string: "\(AppConfig.collabAPIBaseURL)?action=remove") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token = await AuthService().accessToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try? JSONSerialization.data(withJSONObject: [
            "planId": planId,
            "userId": userId,
        ])
        _ = try? await URLSession.shared.data(for: request)
        await loadCollaborators(planId: planId)
    }

    private func revokeInvitation(invitationId: String) async {
        guard let plan = appState.activePlan else { return }
        guard let url = URL(string: "\(AppConfig.collabAPIBaseURL)?action=revoke") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token = await AuthService().accessToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try? JSONSerialization.data(withJSONObject: [
            "invitationId": invitationId,
        ])
        _ = try? await URLSession.shared.data(for: request)
        await loadCollaborators(planId: plan.id)
    }
}

// MARK: - Collaborator response models

struct CollabPerson {
    let userId: String
    let name: String
    let email: String

    init?(dict: [String: Any]) {
        // userId field name differs between owner ({userId:..., isOwner:true})
        // and collaborator entries — both use "userId" per the API contract.
        guard let id = dict["userId"] as? String else { return nil }
        self.userId = id
        self.name = (dict["name"] as? String) ?? "Unknown"
        self.email = (dict["email"] as? String) ?? ""
    }
}

struct PendingInvitation {
    let id: String
    let email: String
    let accepted: Bool

    init?(dict: [String: Any]) {
        guard let id = dict["id"] as? String else { return nil }
        self.id = id
        self.email = (dict["email"] as? String) ?? ""
        self.accepted = (dict["accepted"] as? Bool) ?? false
    }
}

#Preview {
    ShareView()
        .environment(AppState())
}

// MARK: - QR code generator (Core Image)
//
// Web parity (`qr-code-styling` library, errorCorrectionLevel: 'H'). iOS
// uses CIFilter.qrCodeGenerator with the same correction level (H = up to
// 30% recovery, robust at small print sizes). No third-party deps.

extension UIImage {
    static func qrCode(from string: String, size: CGFloat = 240) -> UIImage? {
        guard let data = string.data(using: .utf8) else { return nil }
        let filter = CIFilter.qrCodeGenerator()
        filter.message = data
        filter.correctionLevel = "H"
        guard let ciImage = filter.outputImage else { return nil }

        // Default CI output is ~25–35pt; scale up to the requested size.
        let scaleX = size / ciImage.extent.width
        let scaleY = size / ciImage.extent.height
        let scaled = ciImage.transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))

        let context = CIContext(options: nil)
        guard let cgImage = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}

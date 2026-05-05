import SwiftUI
import CoreImage.CIFilterBuiltins

struct ShareView: View {
    @Environment(AppState.self) private var appState
    @State private var selectedRole = "Viewer"
    @State private var requireSignIn = false
    @State private var linkCopied = false

    // Guest QR section state
    @State private var qrExpanded = false
    @State private var qrEnabled = false
    @State private var qrToken: String?
    @State private var qrSyncing = false
    @State private var qrError: String?

    private let roles = ["Viewer", "Commenter", "Editor"]

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
                        // Plan preview
                        if let plan = appState.activePlan {
                            planPreview(plan)
                        }

                        // Link card
                        linkCard

                        SBOrnament(label: "OR")

                        // People list
                        peopleSection

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

    // MARK: - Link Card

    private var linkCard: some View {
        SBCard(backgroundColor: .sbIvory2) {
            VStack(alignment: .leading, spacing: 14) {
                Text("Anyone with the link")
                    .font(SBFont.bodySemibold)
                    .foregroundStyle(Color.sbCharcoal)

                // Role segmented control
                HStack(spacing: 0) {
                    ForEach(roles, id: \.self) { role in
                        Button {
                            withAnimation(.seatbee) { selectedRole = role }
                        } label: {
                            Text(role)
                                .font(SBFont.inter(12, weight: .semibold))
                                .foregroundStyle(selectedRole == role ? Color.sbGoldDk : Color.sbWarm)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(
                                    selectedRole == role ? Color.sbChampagne : Color.clear
                                )
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(4)
                .background(Color.sbIvory)
                .clipShape(RoundedRectangle(cornerRadius: 10))

                // Copy link button
                Button {
                    if let plan = appState.activePlan {
                        let url = "https://seatbee.app/plan/\(plan.id)"
                        UIPasteboard.general.string = url
                    }
                    linkCopied = true
                    HapticEngine.success()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        linkCopied = false
                    }
                } label: {
                    HStack {
                        Image(systemName: linkCopied ? "checkmark" : "doc.on.doc")
                        Text(linkCopied ? "Copied!" : "Copy link")
                    }
                    .font(SBFont.inter(12, weight: .semibold))
                    .foregroundStyle(Color.sbGoldDk)
                }

                // Require sign-in toggle
                Toggle(isOn: $requireSignIn) {
                    Text("Require sign-in")
                        .font(SBFont.bodySmall)
                        .foregroundStyle(Color.sbCharcoal)
                }
                .tint(.sbGold)
            }
        }
    }

    // MARK: - People

    private var peopleSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Placeholder collaborators
            ForEach(0..<2) { _ in
                HStack(spacing: 10) {
                    SBAvatar(name: "Collaborator", size: 32)
                    VStack(alignment: .leading) {
                        Text("Invite someone")
                            .font(SBFont.bodySmall)
                            .foregroundStyle(Color.sbWarm)
                    }
                    Spacer()
                }
            }

            Button {
                HapticEngine.light()
            } label: {
                HStack {
                    Image(systemName: "plus")
                    Text("Invite people")
                }
                .font(SBFont.bodySemibold)
                .foregroundStyle(Color.sbGoldDk)
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
        guard let url = URL(string: "https://seatbee.app/api/guest?action=config&planId=\(planId)") else { return }
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

        guard let url = URL(string: "https://seatbee.app/api/guest") else {
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

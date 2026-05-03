import SwiftUI

struct ShareView: View {
    @Environment(AppState.self) private var appState
    @State private var selectedRole = "Viewer"
    @State private var requireSignIn = false
    @State private var linkCopied = false

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

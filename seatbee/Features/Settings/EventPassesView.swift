import SwiftUI

// Event Passes inventory + apply-to-plan UI.
// Phase 1: shows web-purchased passes only. Phase 2 (Shayan) will replace
// the "Coming soon" footer with Apple In-App Purchase buttons.

struct EventPassesView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var alertMessage: AlertMessage?
    /// When set, presents the PlanPickerSheet so the user explicitly
    /// chooses which plan a pass applies to. Replaces the old behaviour
    /// of silently auto-applying to whatever plan happened to be
    /// active in the editor. The sheet itself owns the per-plan
    /// applying spinner — we don't track per-pass loading state up
    /// here anymore.
    @State private var pickingPlanForPass: EventPass?
    /// Redeem-a-gift-code form state. Submission goes to web's
    /// /api/redeem-gift-code; on success the pass lands in the user's
    /// inventory and they pick a plan via the normal Apply flow.
    @State private var giftCodeInput = ""
    @State private var redeemingGiftCode = false

    private struct AlertMessage: Identifiable {
        let id = UUID()
        let title: String
        let body: String
    }

    var body: some View {
        List {
            summarySection
            // Redeem-a-gift-code sits up top so users arriving from
            // the new Settings → "Redeem a Gift Code" entry point can
            // act immediately without scrolling past their inventory.
            // Discoverable for users coming in via Event Passes too.
            redeemGiftCodeSection
            availableSection
            if !redeemedPasses.isEmpty { redeemedSection }
            if !giftedPasses.isEmpty { giftedSection }
            if !expiredPasses.isEmpty { expiredSection }
            buyMoreSection
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color.sbIvory)
        .navigationTitle("Event Passes")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await appState.refreshPasses() }
        .task {
            // Always refresh on first appearance — passes are bought outside the app.
            await appState.refreshPasses()
        }
        .alert(
            alertMessage?.title ?? "",
            isPresented: Binding(get: { alertMessage != nil }, set: { if !$0 { alertMessage = nil } }),
            presenting: alertMessage
        ) { _ in
            Button("OK") { alertMessage = nil }
        } message: { msg in
            Text(msg.body)
        }
        .sheet(item: $pickingPlanForPass) { pass in
            PlanPickerSheet(pass: pass) { result in
                handleApplied(result, pass: pass)
            }
            .environment(appState)
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
    }

    // MARK: - Summary

    private var summarySection: some View {
        // 2×2 grid of tier-themed stat cards. Mirrors web's "Your Passes"
        // layout: Event / Signature / Grand counts of AVAILABLE passes,
        // plus a "Used on events" total of redeemed passes.
        let avail = appState.userPasses.passes.filter { $0.isAvailable }
        let eventCount = avail.filter { $0.tier == .eventPass }.count
        let signatureCount = avail.filter { $0.tier == .signaturePass }.count
        let grandCount = avail.filter { $0.tier == .proPass }.count
        let usedCount = appState.userPasses.summary.redeemed

        return Section {
            VStack(spacing: 10) {
                HStack(spacing: 10) {
                    statCard(count: eventCount, title: "Event Pass", subtitle: "250 guests", tint: Color.sbChampagne, accent: Color.sbGoldDk)
                    statCard(count: signatureCount, title: "Signature Pass", subtitle: "500 guests", tint: Color.sbChampagne2, accent: Color.sbGoldDk)
                }
                HStack(spacing: 10) {
                    statCard(count: grandCount, title: "Grand Pass", subtitle: "1,000 guests", tint: Color.sbCharcoal.opacity(0.10), accent: Color.sbCharcoal)
                    statCard(count: usedCount, title: "Used on Events", subtitle: usedCount == 1 ? "redeemed" : "redeemed", tint: Color.sbSage.opacity(0.20), accent: Color.sbSage)
                }
            }
            .padding(.vertical, 4)

            if let nextExpiry = appState.userPasses.nextExpiry,
               appState.userPasses.summary.available > 0 {
                HStack(spacing: 6) {
                    Image(systemName: "clock")
                        .foregroundStyle(Color.sbGoldDk)
                    Text("Next pass expires \(nextExpiry.formatted(date: .abbreviated, time: .omitted))")
                        .font(SBFont.caption)
                        .foregroundStyle(Color.sbWarm)
                }
            }
        } header: {
            Text("Your Inventory")
        } footer: {
            Text("Passes are valid for 6 months from purchase. Apply one to a plan to unlock its features.")
                .font(SBFont.caption)
        }
    }

    private func statCard(count: Int, title: String, subtitle: String, tint: Color, accent: Color) -> some View {
        VStack(spacing: 4) {
            Text("\(count)")
                .font(SBFont.statNumber)
                .foregroundStyle(accent)
            Text(title)
                .font(SBFont.capsLabel)
                .foregroundStyle(Color.sbCharcoal)
                .textCase(.uppercase)
                .multilineTextAlignment(.center)
            Text(subtitle)
                .font(SBFont.small)
                .foregroundStyle(Color.sbWarm)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(tint)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: - Available passes (one section per tier)

    @ViewBuilder
    private var availableSection: some View {
        let groups = appState.userPasses.availableByTier()
        let allEmpty = groups.allSatisfy { $0.passes.isEmpty }

        if allEmpty {
            Section {
                if appState.loadingPasses {
                    HStack { Spacer(); ProgressView(); Spacer() }
                        .padding(.vertical, 8)
                } else {
                    VStack(spacing: 8) {
                        Image(systemName: "ticket")
                            .font(.system(size: 32))
                            .foregroundStyle(Color.sbWarm2)
                        Text("No passes available")
                            .font(SBFont.bodySmallBold)
                            .foregroundStyle(Color.sbCharcoal)
                        Text("Purchase a pass on seatbee.app to unlock larger events and AI seating.")
                            .font(SBFont.caption)
                            .foregroundStyle(Color.sbWarm)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                }
            } header: {
                Text("Available")
            }
        } else {
            // One section per tier — Event → Signature → Grand. Skips
            // tiers where the user has no available passes.
            ForEach(groups, id: \.tier) { group in
                if !group.passes.isEmpty {
                    Section {
                        ForEach(group.passes) { pass in
                            availablePassRow(pass)
                        }
                    } header: {
                        HStack(spacing: 6) {
                            Text(group.tier.displayName.uppercased())
                            Text("·")
                                .foregroundStyle(Color.sbWarm2)
                            Text("\(group.passes.count) available")
                                .foregroundStyle(Color.sbGoldDk)
                        }
                    }
                }
            }
        }
    }

    private func availablePassRow(_ pass: EventPass) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Image(systemName: "ticket")
                    .foregroundStyle(Color.sbGoldDk)
                    .frame(width: 22)

                VStack(alignment: .leading, spacing: 2) {
                    if let exp = pass.expiresAt {
                        Text("Expires \(exp.formatted(date: .abbreviated, time: .omitted))")
                            .font(SBFont.bodySmallBold)
                            .foregroundStyle(pass.isExpiringSoon ? Color.sbError : Color.sbCharcoal)
                    } else {
                        Text("No expiry")
                            .font(SBFont.bodySmallBold)
                            .foregroundStyle(Color.sbCharcoal)
                    }
                    if let code = pass.giftCode {
                        Text(code)
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundStyle(Color.sbWarm)
                    }
                }

                Spacer()

                applyButton(for: pass)
            }
            // Secondary action — Gift this pass. Web parity (App.jsx
            // ~24700: "Gift This Pass" button reveals a share panel).
            // iOS uses a SwiftUI Menu with two paths so the user can:
            //   - Send link → iOS share sheet (iMessage / WhatsApp /
            //     Email / Copy Link). The recipient taps the link and
            //     lands on web's gift welcome modal.
            //   - Copy code → just the SEAT-XXXX-XXXX onto the
            //     clipboard, ready to paste into a chat. The
            //     recipient pastes it into "Redeem a Gift Code" on
            //     iOS, never following a link to web. Avoids the
            //     iOS-installed-but-link-goes-to-web round-trip.
            if let code = pass.giftCode {
                Menu {
                    Button {
                        shareGiftLink(code: code, packType: pass.packType)
                    } label: {
                        Label("Send link", systemImage: "square.and.arrow.up")
                    }
                    Button {
                        copyGiftCode(code)
                    } label: {
                        Label("Copy code", systemImage: "doc.on.doc")
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "gift")
                            .font(.system(size: 11, weight: .semibold))
                        Text("Gift this pass")
                            .font(SBFont.caption)
                    }
                    .foregroundStyle(Color.sbGoldDk)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func applyButton(for pass: EventPass) -> some View {
        // Apply is ALWAYS available for in-inventory passes — the
        // picker sheet decides per-plan eligibility, not this row.
        // The old "Plan upgraded" gate hid the button whenever the
        // active plan happened to be at >= the pass's tier, which
        // made passes look used when they were still in inventory.
        Button {
            pickingPlanForPass = pass
        } label: {
            Text("Apply")
                .font(SBFont.label)
                .foregroundStyle(Color.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.sbGold)
                .clipShape(Capsule())
        }
        .buttonStyle(.borderless)
    }

    // MARK: - Redeemed / Expired sections

    private var redeemedPasses: [EventPass] {
        appState.userPasses.passes.filter { $0.status == "redeemed" }
    }

    private var expiredPasses: [EventPass] {
        appState.userPasses.passes.filter { $0.status == "expired" }
    }

    private var redeemedSection: some View {
        Section {
            ForEach(redeemedPasses) { pass in
                HStack(spacing: 12) {
                    tierBadge(pass.tier)
                    VStack(alignment: .leading, spacing: 3) {
                        // Lead with the plan name now that the user
                        // explicitly picks per-pass — they're more
                        // likely to be asking "where is this pass?"
                        // than "what tier was it?". Tier shows below.
                        if let planName = pass.seatingPlans?.name {
                            Text(planName)
                                .font(SBFont.bodySmallBold)
                                .foregroundStyle(Color.sbCharcoal)
                                .lineLimit(1)
                        } else if pass.seatingPlans?.deletedAt != nil {
                            Text("Plan deleted")
                                .font(SBFont.bodySmallBold)
                                .foregroundStyle(Color.sbWarm)
                        } else {
                            Text(pass.tier.displayName)
                                .font(SBFont.bodySmallBold)
                                .foregroundStyle(Color.sbCharcoal)
                        }
                        HStack(spacing: 4) {
                            Text(pass.tier.displayName)
                            if let date = pass.redeemedAt {
                                Text("·")
                                    .foregroundStyle(Color.sbWarm2)
                                Text("redeemed \(date.formatted(date: .abbreviated, time: .omitted))")
                            }
                        }
                        .font(SBFont.caption)
                        .foregroundStyle(Color.sbWarm)
                    }
                    Spacer()
                }
                .padding(.vertical, 4)
            }
        } header: {
            Text("Redeemed")
        }
    }

    private var expiredSection: some View {
        Section {
            ForEach(expiredPasses) { pass in
                HStack(spacing: 12) {
                    tierBadge(pass.tier).opacity(0.4)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(pass.tier.displayName)
                            .font(SBFont.bodySmallBold)
                            .foregroundStyle(Color.sbWarm)
                        if let exp = pass.expiresAt {
                            Text("Expired \(exp.formatted(date: .abbreviated, time: .omitted))")
                                .font(SBFont.caption)
                                .foregroundStyle(Color.sbWarm)
                        }
                    }
                    Spacer()
                }
                .padding(.vertical, 4)
            }
        } header: {
            Text("Expired")
        }
    }

    // MARK: - Gifted passes (passes the user has sent out)

    private var giftedPasses: [GiftedPass] {
        appState.userPasses.giftedPasses ?? []
    }

    private var giftedSection: some View {
        Section {
            ForEach(giftedPasses) { gift in
                HStack(spacing: 12) {
                    Image(systemName: gift.isClaimed ? "checkmark.seal.fill" : "paperplane")
                        .foregroundStyle(gift.isClaimed ? Color.sbSage : Color.sbGoldDk)
                        .frame(width: 22)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(gift.tier.displayName)
                            .font(SBFont.bodySmallBold)
                            .foregroundStyle(Color.sbCharcoal)
                        // Status line: claimed (with recipient + date)
                        // OR awaiting-claim (with code so the user can
                        // re-share / re-copy the original link).
                        if gift.isClaimed {
                            VStack(alignment: .leading, spacing: 1) {
                                if let email = gift.profiles?.email {
                                    Text("Claimed by \(email)")
                                        .font(SBFont.caption)
                                        .foregroundStyle(Color.sbWarm)
                                        .lineLimit(1)
                                }
                                if let claimed = gift.giftRedeemedAt {
                                    Text(claimed.formatted(date: .abbreviated, time: .omitted))
                                        .font(SBFont.caption)
                                        .foregroundStyle(Color.sbWarm2)
                                }
                            }
                        } else {
                            HStack(spacing: 4) {
                                Text("Awaiting claim")
                                    .font(SBFont.caption)
                                    .foregroundStyle(Color.sbWarm)
                                if let code = gift.giftCode {
                                    Text("·")
                                        .foregroundStyle(Color.sbWarm2)
                                    Text(code)
                                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                                        .foregroundStyle(Color.sbWarm)
                                }
                            }
                        }
                    }
                    Spacer()
                    if !gift.isClaimed, let code = gift.giftCode {
                        // Re-share affordance for unclaimed gifts in
                        // case the recipient lost the link. Same two
                        // options as the primary Gift menu — Send link
                        // OR Copy code. No revoke (web doesn't support
                        // that either).
                        Menu {
                            Button {
                                shareGiftLink(code: code, packType: gift.packType)
                            } label: {
                                Label("Send link", systemImage: "square.and.arrow.up")
                            }
                            Button {
                                copyGiftCode(code)
                            } label: {
                                Label("Copy code", systemImage: "doc.on.doc")
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                                .font(.system(size: 16))
                                .foregroundStyle(Color.sbGoldDk)
                        }
                    }
                }
                .padding(.vertical, 4)
            }
        } header: {
            Text("Gifted")
        } footer: {
            Text("Once you've gifted a pass, the recipient can claim it with the SEAT code on either iOS or web. Gifts can't be revoked.")
                .font(SBFont.caption)
        }
    }

    // MARK: - Redeem a gift code

    private var redeemGiftCodeSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                Text("Got a SEAT-XXXX-XXXX code from someone? Enter it below to add the pass to your inventory.")
                    .font(SBFont.caption)
                    .foregroundStyle(Color.sbWarm)

                HStack(spacing: 8) {
                    TextField("SEAT-XXXX-XXXX", text: $giftCodeInput)
                        .font(.system(size: 13, weight: .medium, design: .monospaced))
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .padding(.vertical, 8)
                        .padding(.horizontal, 10)
                        .background(Color.sbIvory2)
                        .clipShape(RoundedRectangle(cornerRadius: 8))

                    Button {
                        Task { await submitGiftCode() }
                    } label: {
                        if redeemingGiftCode {
                            ProgressView()
                                .padding(.horizontal, 16)
                                .padding(.vertical, 6)
                        } else {
                            Text("Redeem")
                                .font(SBFont.label)
                                .foregroundStyle(.white)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(canSubmitGiftCode ? Color.sbGoldDk : Color.sbWarm2)
                                .clipShape(Capsule())
                        }
                    }
                    .buttonStyle(.borderless)
                    .disabled(!canSubmitGiftCode)
                }
            }
            .padding(.vertical, 4)
        } header: {
            Text("Redeem a Gift Code")
        }
    }

    /// Loose validation — server is authoritative, this just stops
    /// users from tapping Redeem with an empty / obviously-wrong input.
    private var canSubmitGiftCode: Bool {
        !redeemingGiftCode &&
        giftCodeInput.trimmingCharacters(in: .whitespaces).count >= 4
    }

    private func submitGiftCode() async {
        let code = giftCodeInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !code.isEmpty else { return }
        redeemingGiftCode = true
        defer { redeemingGiftCode = false }
        do {
            let result = try await appState.passes.redeemGiftCode(code)
            HapticEngine.success()
            // Refresh inventory so the new pass shows up under
            // Available immediately.
            await appState.refreshPasses()
            giftCodeInput = ""
            let body: String = {
                if result.alreadyOwned == true {
                    return result.message ?? "You already own this pass."
                }
                let tierName = passTierDisplay(for: result.passType)
                if let gifter = result.gifterName, !gifter.isEmpty {
                    return "\(tierName) added to your inventory — gifted by \(gifter). Tap Apply to use it on an event."
                }
                return result.message ?? "\(tierName) added to your inventory. Tap Apply to use it on an event."
            }()
            alertMessage = AlertMessage(title: "Pass Redeemed", body: body)
        } catch let err as PassesService.PassesError {
            HapticEngine.error()
            alertMessage = AlertMessage(title: "Couldn't redeem code", body: err.localizedDescription)
        } catch {
            HapticEngine.error()
            alertMessage = AlertMessage(title: "Couldn't redeem code", body: error.localizedDescription)
        }
    }

    private func passTierDisplay(for packType: String?) -> String {
        switch packType {
        case "pro_pass_single": return PlanTier.proPass.displayName
        case "signature_pass":  return PlanTier.signaturePass.displayName
        default:                return PlanTier.eventPass.displayName
        }
    }

    // MARK: - Send a gift (system share sheet)

    /// Copies just the SEAT-XXXX-XXXX code onto the system clipboard.
    /// Used when the sender wants to paste only the code into a chat
    /// (not the whole "Claim it at..." link), so the recipient can
    /// type it into "Redeem a Gift Code" inside iOS without ever
    /// following a link to web. Side-steps the iOS-app-installed-
    /// but-link-still-goes-to-web round-trip.
    private func copyGiftCode(_ code: String) {
        UIPasteboard.general.string = code
        HapticEngine.success()
        alertMessage = AlertMessage(
            title: "Code Copied",
            body: "\(code) is on your clipboard. Paste it into a message — the recipient can redeem it inside the iOS app or at seatbee.app."
        )
    }

    /// Open the iOS share sheet pre-filled with the gift link + a
    /// short message. Web parity URL: `https://seatbee.app/?gift=CODE`.
    /// We deliberately use the system share sheet (not an in-app
    /// channel picker) so iMessage / WhatsApp / Mail / Copy Link all
    /// work in one tap, and the user picks whichever they actually use.
    private func shareGiftLink(code: String, packType: String) {
        let tierName = passTierDisplay(for: packType)
        let url = URL(string: "https://seatbee.app/?gift=\(code)")
        let message = "I'm gifting you a \(tierName) on Seatbee 🐝\n\nClaim it at the link below — code: \(code)"

        var items: [Any] = [message]
        if let url { items.append(url) }
        let activityVC = UIActivityViewController(activityItems: items, applicationActivities: nil)
        if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let root = scene.windows.first?.rootViewController {
            (root.presentedViewController ?? root).present(activityVC, animated: true)
        }
    }

    // MARK: - Buy more
    //
    // Routes through appState.showUpgrade — same plumbing the rest of
    // the paywall surfaces use. Today (iapEnabled == false) it opens
    // seatbee.app/pricing in Safari; when in-app purchases ship the
    // same trigger flips to the native UpgradeView (AppRouter.swift).

    private var buyMoreSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Text("Get More Passes")
                    .font(SBFont.bodySmallBold)
                    .foregroundStyle(Color.sbCharcoal)
                Text("Browse Event, Signature, and Grand passes — purchases land here automatically.")
                    .font(SBFont.caption)
                    .foregroundStyle(Color.sbWarm)
                    .fixedSize(horizontal: false, vertical: true)

                Button {
                    appState.showUpgrade = true
                    HapticEngine.selection()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "cart")
                            .font(.system(size: 12, weight: .semibold))
                        Text("Buy more passes")
                            .font(SBFont.bodySmallBold)
                        Spacer()
                        Image(systemName: "arrow.up.forward")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.85))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 11)
                    .background(
                        LinearGradient(colors: [Color.sbGold, Color.sbGoldDk],
                                       startPoint: .top, endPoint: .bottom)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: SBRadius.button))
                }
                .buttonStyle(.plain)
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Helpers

    /// Tier accent — same palette as the onboarding pass tiles
    /// (charcoal / gold / plum) so the two surfaces feel like one
    /// system.
    private func tierAccent(_ tier: PlanTier) -> Color {
        switch tier {
        case .free:           return Color.sbWarm
        case .eventPass:      return Color.sbCharcoal
        case .signaturePass:  return Color.sbGoldDk
        case .proPass:        return Color.sbPlum
        }
    }

    private func tierBadge(_ tier: PlanTier) -> some View {
        // Key icon matches web's pass picker (App.jsx ~20284) — colour
        // does the differentiating, not a letter.
        Image(systemName: "key.fill")
            .font(.system(size: 22, weight: .semibold))
            .foregroundStyle(tierAccent(tier))
            .frame(width: 36, height: 36)
            .rotationEffect(.degrees(-45))
    }

    /// Called by `PlanPickerSheet` after a successful redeem. Mirrors
    /// the side-effects the old auto-apply path used to do: refresh
    /// the pass inventory, update active plan tier in memory if it
    /// matches, surface a confirmation alert.
    private func handleApplied(_ result: RedeemPassResponse, pass: EventPass) {
        // If the user happened to apply to whichever plan is currently
        // open, reflect the new tier in memory so other surfaces
        // (Editor / Share) update without a full refetch. Other plans
        // are stateless on iOS — next time they're opened they'll be
        // re-fetched fresh from Supabase with the new tier.
        if let newTier = result.tier,
           let appliedPlanId = result.planId,
           appState.activePlan?.id == appliedPlanId {
            appState.activePlan?.tier = newTier
        }

        Task {
            await appState.refreshPasses()
            alertMessage = AlertMessage(
                title: "Pass Applied",
                body: result.message ?? "\(pass.tier.displayName) applied."
            )
        }
    }
}

#Preview {
    NavigationStack {
        EventPassesView()
            .environment(AppState())
    }
}

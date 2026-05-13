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

    private struct AlertMessage: Identifiable {
        let id = UUID()
        let title: String
        let body: String
    }

    var body: some View {
        List {
            summarySection
            // Buy-more sits right under the inventory grid — the
            // logical "do I have enough?" moment is right after the
            // user reads their counts. Was at the bottom; users
            // weren't reaching it.
            buyMoreSection
            availableSection
            if !redeemedPasses.isEmpty { redeemedSection }
            if !giftedPasses.isEmpty { giftedSection }
            if !expiredPasses.isEmpty { expiredSection }
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
                        Text("Purchase a pass to unlock larger events and AI seating.")
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
        // Gift-this-pass affordance and the SEAT-XXXX-XXXX display were
        // removed for App Store 3.1.1 compliance — anti-steering means
        // iOS can't surface flows that hand out codes redeemable outside
        // Apple's IAP system. Pass gifting lives on web only.
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
            }

            Spacer()

            applyButton(for: pass)
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
                    // Re-share affordance removed for App Store 3.1.1
                    // compliance. Users who need to re-send a code go
                    // to web. iOS shows this section as read-only history.
                }
                .padding(.vertical, 4)
            }
        } header: {
            Text("Gifted")
        } footer: {
            Text("Gifts you've sent appear here. Once claimed, the pass moves to the recipient's account.")
                .font(SBFont.caption)
        }
    }

    private func passTierDisplay(for packType: String?) -> String {
        switch packType {
        case "pro_pass_single": return PlanTier.proPass.displayName
        case "signature_pass":  return PlanTier.signaturePass.displayName
        default:                return PlanTier.eventPass.displayName
        }
    }

    // MARK: - Buy more
    //
    // Routes through appState.showUpgrade which presents the native
    // UpgradeView (StoreKit paywall) via AppRouter.swift.

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

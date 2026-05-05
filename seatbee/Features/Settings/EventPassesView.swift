import SwiftUI

// Event Passes inventory + apply-to-plan UI.
// Phase 1: shows web-purchased passes only. Phase 2 (Shayan) will replace
// the "Coming soon" footer with Apple In-App Purchase buttons.

struct EventPassesView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var redeemingPassId: String?
    @State private var alertMessage: AlertMessage?

    private struct AlertMessage: Identifiable {
        let id = UUID()
        let title: String
        let body: String
    }

    var body: some View {
        List {
            summarySection
            availableSection
            if !redeemedPasses.isEmpty { redeemedSection }
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
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func applyButton(for pass: EventPass) -> some View {
        let activePlan = appState.activePlan
        let canApply = canApply(pass: pass, to: activePlan)

        if redeemingPassId == pass.id {
            ProgressView()
        } else if canApply {
            Button {
                Task { await redeem(pass) }
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
        } else if let plan = activePlan, plan.tier != nil, plan.tier != "free" {
            Text("Plan upgraded")
                .font(SBFont.caption)
                .foregroundStyle(Color.sbWarm)
        } else if activePlan == nil {
            Text("Open a plan")
                .font(SBFont.caption)
                .foregroundStyle(Color.sbWarm)
        }
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
                    VStack(alignment: .leading, spacing: 2) {
                        Text(pass.tier.displayName)
                            .font(SBFont.bodySmallBold)
                            .foregroundStyle(Color.sbCharcoal)
                        if let planName = pass.seatingPlans?.name {
                            Text("Applied to: \(planName)")
                                .font(SBFont.caption)
                                .foregroundStyle(Color.sbWarm)
                                .lineLimit(1)
                        } else if let date = pass.redeemedAt {
                            Text("Redeemed \(date.formatted(date: .abbreviated, time: .omitted))")
                                .font(SBFont.caption)
                                .foregroundStyle(Color.sbWarm)
                        }
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

    // MARK: - Buy more (Phase 2 placeholder)

    private var buyMoreSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                Text("Get More Passes")
                    .font(SBFont.bodySmallBold)
                    .foregroundStyle(Color.sbCharcoal)
                Text("In-app purchases are coming soon. For now, purchase passes on seatbee.app and they will appear here automatically.")
                    .font(SBFont.caption)
                    .foregroundStyle(Color.sbWarm)
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Helpers

    private func tierBadge(_ tier: PlanTier) -> some View {
        let (color, letter): (Color, String) = {
            switch tier {
            case .free:           return (Color.sbWarm, "F")
            case .eventPass:      return (Color.sbGold, "E")
            case .signaturePass:  return (Color.sbGoldDk, "S")
            case .proPass:        return (Color.sbCharcoal, "G")
            }
        }()
        return ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(color.opacity(0.15))
                .frame(width: 36, height: 36)
            Text(letter)
                .font(SBFont.bodySmallBold)
                .foregroundStyle(color)
        }
    }

    private func canApply(pass: EventPass, to plan: SeatingPlan?) -> Bool {
        guard let plan else { return false }
        let currentTier = PlanTier.from(plan.tier)
        return pass.tier.rank > currentTier.rank
    }

    private func redeem(_ pass: EventPass) async {
        guard let planId = appState.activePlan?.id else { return }
        redeemingPassId = pass.id
        defer { redeemingPassId = nil }
        do {
            let result = try await appState.passes.redeemPass(planId: planId, passId: pass.id)
            HapticEngine.success()
            // Reflect new tier locally without forcing a full plan refetch.
            if let newTier = result.tier {
                appState.activePlan?.tier = newTier
            }
            // Refresh inventory so this pass moves out of "Available".
            await appState.refreshPasses()
            alertMessage = AlertMessage(
                title: "Pass Applied",
                body: result.message ?? "\(pass.tier.displayName) applied to this event."
            )
        } catch let error as PassesService.PassesError {
            HapticEngine.error()
            alertMessage = AlertMessage(title: "Could not apply pass", body: error.localizedDescription)
        } catch {
            HapticEngine.error()
            alertMessage = AlertMessage(title: "Could not apply pass", body: error.localizedDescription)
        }
    }
}

#Preview {
    NavigationStack {
        EventPassesView()
            .environment(AppState())
    }
}

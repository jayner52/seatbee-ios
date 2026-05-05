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
        Section {
            HStack(spacing: 16) {
                summaryStat(label: "Available", value: appState.userPasses.summary.available, color: .sbGold)
                Divider()
                summaryStat(label: "Redeemed", value: appState.userPasses.summary.redeemed, color: .sbCharcoal)
                Divider()
                summaryStat(label: "Expired", value: appState.userPasses.summary.expired, color: .sbWarm)
            }
            .padding(.vertical, 8)

            if let nextExpiry = appState.userPasses.nextExpiry,
               appState.userPasses.summary.available > 0 {
                HStack {
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

    private func summaryStat(label: String, value: Int, color: Color) -> some View {
        VStack(spacing: 4) {
            Text("\(value)")
                .font(SBFont.statNumberSmall)
                .foregroundStyle(color)
            Text(label)
                .font(SBFont.capsLabel)
                .foregroundStyle(Color.sbWarm)
                .textCase(.uppercase)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Available passes (grouped by tier)

    @ViewBuilder
    private var availableSection: some View {
        let groups = appState.userPasses.availableByTier()
        let allEmpty = groups.allSatisfy { $0.passes.isEmpty }

        Section {
            if allEmpty {
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
            } else {
                ForEach(groups, id: \.tier) { group in
                    if !group.passes.isEmpty {
                        ForEach(group.passes) { pass in
                            availablePassRow(pass)
                        }
                    }
                }
            }
        } header: {
            Text("Available")
        }
    }

    private func availablePassRow(_ pass: EventPass) -> some View {
        HStack(spacing: 12) {
            tierBadge(pass.tier)

            VStack(alignment: .leading, spacing: 2) {
                Text(pass.tier.displayName)
                    .font(SBFont.bodySmallBold)
                    .foregroundStyle(Color.sbCharcoal)
                if let exp = pass.expiresAt {
                    Text("Expires \(exp.formatted(date: .abbreviated, time: .omitted))")
                        .font(SBFont.caption)
                        .foregroundStyle(pass.isExpiringSoon ? Color.sbError : Color.sbWarm)
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

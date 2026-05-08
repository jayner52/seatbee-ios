import SwiftUI

// MARK: - Plan picker for applying an Event Pass
//
// Web parity: when a user taps "Apply" on an available pass, web pops
// a list of THEIR plans filtered to ones the pass would meaningfully
// upgrade (lower tier rank than the pass). Same logic here. Replaces
// the old behaviour of silently auto-applying to whatever plan
// happened to be active in the editor — which led to the user not
// knowing which event got the pass.
//
// Filter rules (mirrors web App.jsx ~line 24700):
//   - Exclude plans whose current tier RANK >= pass tier rank.
//     Free plans → eligible for any pass. Event-Pass plans → eligible
//     only for Signature/Grand. Signature plans → eligible only for
//     Grand. Same-tier passes show as "already covered" so the user
//     understands why they can't pick that plan.
//   - Soft-deleted plans are already filtered upstream by
//     DatabaseService.fetchPlans().
//
// Variant exclusion (web's `is_variant`/`_meta.isVariant`) doesn't
// apply on iOS yet — iOS doesn't expose multi-arrangement.

struct PlanPickerSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    let pass: EventPass
    /// Called once the apply succeeds. Parent reflects the new tier on
    /// the active plan if it matches and refreshes pass inventory.
    let onApplied: (RedeemPassResponse) -> Void

    @State private var allPlans: [SeatingPlan] = []
    @State private var loading = true
    @State private var loadError: String?
    @State private var applyingPlanId: String?

    var body: some View {
        NavigationStack {
            Group {
                if loading {
                    HStack { Spacer(); ProgressView(); Spacer() }
                        .padding(.vertical, 40)
                } else if let loadError {
                    errorState(loadError)
                } else if allPlans.isEmpty {
                    noPlansState
                } else {
                    planList
                }
            }
            .background(Color.sbIvory)
            .navigationTitle("Apply pass to…")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Color.sbWarm)
                }
            }
        }
        .task { await loadPlans() }
    }

    // MARK: - Sub-views

    private var planList: some View {
        List {
            Section {
                ForEach(allPlans, id: \.id) { plan in
                    planRow(plan)
                }
            } header: {
                passSummaryHeader
            } footer: {
                Text("A pass can only be applied to one event. Once applied, it can't be transferred.")
                    .font(SBFont.caption)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color.sbIvory)
    }

    /// Header that reminds the user what they're applying so the picker
    /// doesn't feel disconnected from the pass they tapped.
    private var passSummaryHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Applying \(pass.tier.displayName)")
                .font(SBFont.bodySemibold)
                .foregroundStyle(Color.sbCharcoal)
                .textCase(.none)
            HStack(spacing: 4) {
                Text("\(guestLimit(for: pass.tier)) guests")
                if let exp = pass.expiresAt {
                    Text("·")
                        .foregroundStyle(Color.sbWarm2)
                    Text("expires \(exp.formatted(date: .abbreviated, time: .omitted))")
                }
            }
            .font(SBFont.caption)
            .foregroundStyle(Color.sbWarm)
            .textCase(.none)
        }
        .padding(.vertical, 4)
    }

    /// One row per plan. Eligible plans tap-through to apply; ineligible
    /// plans render dimmed with an explanatory caption so the user
    /// understands why they can't select that plan.
    private func planRow(_ plan: SeatingPlan) -> some View {
        let currentTier = resolvedTier(for: plan)
        let eligible = pass.tier.rank > currentTier.rank
        let isApplying = applyingPlanId == plan.id

        return Button {
            guard eligible, !isApplying else { return }
            Task { await apply(to: plan) }
        } label: {
            HStack(spacing: 12) {
                planAvatar(plan)
                VStack(alignment: .leading, spacing: 2) {
                    Text(plan.name)
                        .font(SBFont.bodySmallBold)
                        .foregroundStyle(Color.sbCharcoal)
                        .lineLimit(1)
                    HStack(spacing: 6) {
                        currentTierChip(currentTier)
                        if eligible && currentTier != .free {
                            Text("UPGRADE")
                                .font(SBFont.capsLabel)
                                .foregroundStyle(Color.sbGoldDk)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.sbChampagne)
                                .clipShape(Capsule())
                        }
                        if !eligible {
                            Text("already covered")
                                .font(SBFont.caption)
                                .foregroundStyle(Color.sbWarm)
                        }
                    }
                }
                Spacer()
                if isApplying {
                    ProgressView()
                } else if eligible {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.sbWarm2)
                } else {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.sbSage)
                }
            }
            .padding(.vertical, 4)
            .opacity(eligible ? 1 : 0.55)
        }
        .buttonStyle(.plain)
        .disabled(!eligible || applyingPlanId != nil)
    }

    private func planAvatar(_ plan: SeatingPlan) -> some View {
        // Same SBAvatar used elsewhere on the Plans surface, so the
        // picker visually matches the dashboard.
        SBAvatar(name: plan.name, size: 36)
    }

    private func currentTierChip(_ tier: PlanTier) -> some View {
        Text(tier.displayName)
            .font(SBFont.caption)
            .foregroundStyle(tier == .free ? Color.sbWarm : Color.sbCharcoal)
    }

    // MARK: - States

    private var noPlansState: some View {
        VStack(spacing: 10) {
            Image(systemName: "tray")
                .font(.system(size: 36))
                .foregroundStyle(Color.sbWarm2)
            Text("No plans yet")
                .font(SBFont.bodySemibold)
                .foregroundStyle(Color.sbCharcoal)
            Text("Create a seating plan first, then come back here to apply this pass.")
                .font(SBFont.caption)
                .foregroundStyle(Color.sbWarm)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }

    private func errorState(_ message: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 30))
                .foregroundStyle(Color.sbError)
            Text("Couldn't load your plans")
                .font(SBFont.bodySemibold)
                .foregroundStyle(Color.sbCharcoal)
            Text(message)
                .font(SBFont.caption)
                .foregroundStyle(Color.sbWarm)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            Button("Try again") {
                Task { await loadPlans() }
            }
            .padding(.top, 6)
            .foregroundStyle(Color.sbGoldDk)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 50)
    }

    // MARK: - Data

    private func loadPlans() async {
        loading = true
        loadError = nil
        do {
            let fetched = try await appState.database.fetchPlans()
            // Sort: most-recently-updated first (matches the Plans tab).
            allPlans = fetched
        } catch {
            loadError = error.localizedDescription
        }
        loading = false
    }

    private func apply(to plan: SeatingPlan) async {
        applyingPlanId = plan.id
        defer { applyingPlanId = nil }
        do {
            let result = try await appState.passes.redeemPass(
                planId: plan.id,
                passId: pass.id
            )
            HapticEngine.success()
            onApplied(result)
            dismiss()
        } catch let err as PassesService.PassesError {
            HapticEngine.error()
            // Don't dismiss the sheet on error — let the user try a
            // different plan or fix the issue. Surface as a basic
            // alert via parent's existing alertMessage chain by
            // re-throwing through onApplied... actually simpler:
            // show inline error here.
            loadError = err.localizedDescription
        } catch {
            HapticEngine.error()
            loadError = error.localizedDescription
        }
    }

    private func guestLimit(for tier: PlanTier) -> String {
        switch tier {
        case .free: return "100"
        case .eventPass: return "250"
        case .signaturePass: return "500"
        case .proPass: return "1,000"
        }
    }

    /// Same resolution chain as `AppState.activePlanTier` but for
    /// arbitrary plans (the active-tier helper only covers the
    /// currently-open one). Catches plans whose `tier` column is stale
    /// or nil but whose `event_pass_expires_at` / pass inventory says
    /// they're already on a paid tier — without this the picker would
    /// list them as "Free" and the server would 400 with
    /// ALREADY_HAS_PASS the moment the user picked them.
    private func resolvedTier(for plan: SeatingPlan) -> PlanTier {
        // 1. Direct tier column, respecting expiry.
        let raw = plan.tier ?? "free"
        if raw != "free" {
            if let exp = plan.eventPassExpiresAt, Date() > exp {
                // Paid tier but pass has expired — fall through.
            } else {
                return PlanTier.from(raw)
            }
        }
        // 2. event_pass_expires_at fallback (covers web's older
        //    write path where the tier column wasn't kept in lockstep).
        if let exp = plan.eventPassExpiresAt, Date() < exp {
            return .eventPass
        }
        // 3. Cross-reference the user's redeemed-pass inventory — most
        //    reliable for promo / signature / grand applied via web.
        if let pass = appState.userPasses.passes.first(where: { p in
            p.status == "redeemed"
            && p.redeemedForPlanId == plan.id
            && (p.expiresAt.map { Date() < $0 } ?? true)
        }) {
            return pass.tier
        }
        return .free
    }
}

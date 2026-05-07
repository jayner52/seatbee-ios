import SwiftUI
import StoreKit

struct UpgradeView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var storeKit = StoreKitService()
    @State private var isPurchasing = false
    @State private var purchasingProductId: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Header
                    VStack(spacing: 8) {
                        Image("SeatbeeLogo")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 56, height: 56)

                        Text("Upgrade Your Plan")
                            .font(SBFont.displayLarge)
                            .foregroundStyle(Color.sbCharcoal)

                        Text("Unlock AI seating, more guests, and premium features")
                            .font(SBFont.body)
                            .foregroundStyle(Color.sbWarm)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 8)

                    // Current tier badge
                    currentTierBadge

                    // Pass cards
                    if storeKit.isLoading {
                        ProgressView("Loading prices...")
                            .padding(.top, 20)
                    } else if storeKit.products.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "exclamationmark.triangle")
                                .font(.system(size: 32))
                                .foregroundStyle(Color.sbWarm2)
                            Text("Couldn't load prices")
                                .font(SBFont.body)
                                .foregroundStyle(Color.sbWarm)
                            SBButton(title: "Retry", variant: .ghost) {
                                Task { await storeKit.fetchProducts() }
                            }
                        }
                        .padding(.top, 20)
                    } else {
                        ForEach(SeatbeeProduct.allCases, id: \.rawValue) { seatbeeProduct in
                            if let product = storeKit.product(for: seatbeeProduct) {
                                passCard(product: product, seatbeeProduct: seatbeeProduct)
                            }
                        }
                    }

                    // Restore purchases
                    Button {
                        Task {
                            await storeKit.restorePurchases()
                            await appState.refreshPasses()
                        }
                    } label: {
                        Text("Restore Purchases")
                            .font(SBFont.bodySmall)
                            .foregroundStyle(Color.sbGoldDk)
                            .underline()
                    }
                    .buttonStyle(.plain)

                    // Web alternative
                    VStack(spacing: 4) {
                        Text("Passes also available at seatbee.app")
                            .font(SBFont.caption)
                            .foregroundStyle(Color.sbWarm)
                    }

                    // Error
                    if let error = storeKit.purchaseError {
                        Text(error)
                            .font(SBFont.caption)
                            .foregroundStyle(Color.sbError)
                            .padding(.horizontal)
                    }

                    Spacer(minLength: 40)
                }
                .padding(.horizontal, SBSpacing.screenMargin)
            }
            .background(Color.sbIvory)
            .navigationTitle("Upgrade")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                        .foregroundStyle(Color.sbWarm)
                }
            }
            .onChange(of: storeKit.purchaseSuccess) { _, success in
                if success {
                    Task {
                        await appState.refreshPasses()
                        HapticEngine.success()
                    }
                }
            }
        }
    }

    // MARK: - Current Tier

    private var currentTierBadge: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(appState.activePlanTier == .free ? Color.sbWarm2 : Color.sbGold)
                .frame(width: 8, height: 8)
            Text("Current plan: \(appState.activePlanTier.displayName)")
                .font(SBFont.bodySemibold)
                .foregroundStyle(Color.sbCharcoal)

            if appState.isActivePlanExpired {
                SBChip(text: "Expired", variant: .muted)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .background(Color.sbIvory2)
        .clipShape(RoundedRectangle(cornerRadius: SBRadius.small))
    }

    // MARK: - Pass Card

    private func passCard(product: Product, seatbeeProduct: SeatbeeProduct) -> some View {
        let isCurrentTier = appState.activePlanTier == seatbeeProduct.tier
        let isLowerTier = seatbeeProduct.tier.rank < appState.activePlanTier.rank
        let isPopular = seatbeeProduct == .eventPass

        return VStack(spacing: 16) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(seatbeeProduct.displayName)
                            .font(SBFont.displaySmall)
                            .foregroundStyle(Color.sbCharcoal)

                        if isPopular && !isCurrentTier {
                            Text("POPULAR")
                                .font(SBFont.capsLabel)
                                .foregroundStyle(.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Color.sbGold)
                                .clipShape(Capsule())
                        }

                        if isCurrentTier {
                            Text("CURRENT")
                                .font(SBFont.capsLabel)
                                .foregroundStyle(Color.sbSage)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Color.sbSage.opacity(0.15))
                                .clipShape(Capsule())
                        }
                    }

                    Text("Up to \(seatbeeProduct.guestLimit) guests")
                        .font(SBFont.meta)
                        .foregroundStyle(Color.sbWarm)
                }

                Spacer()

                // Price
                VStack(alignment: .trailing, spacing: 2) {
                    Text(product.displayPrice)
                        .font(SBFont.fraunces(24, weight: .medium))
                        .foregroundStyle(Color.sbGoldDk)
                    Text("one-time")
                        .font(SBFont.capsLabel)
                        .foregroundStyle(Color.sbWarm)
                }
            }

            // Features
            VStack(alignment: .leading, spacing: 6) {
                ForEach(seatbeeProduct.features, id: \.self) { feature in
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(Color.sbSage)
                        Text(feature)
                            .font(SBFont.bodySmall)
                            .foregroundStyle(Color.sbCharcoal)
                    }
                }
            }

            // Buy button
            if isCurrentTier {
                Text("This is your current plan")
                    .font(SBFont.bodySmall)
                    .foregroundStyle(Color.sbWarm)
                    .frame(maxWidth: .infinity)
                    .padding(12)
                    .background(Color.sbIvory2)
                    .clipShape(RoundedRectangle(cornerRadius: SBRadius.button))
            } else if isLowerTier {
                Text("Included in your current plan")
                    .font(SBFont.bodySmall)
                    .foregroundStyle(Color.sbWarm)
                    .frame(maxWidth: .infinity)
                    .padding(12)
                    .background(Color.sbIvory2)
                    .clipShape(RoundedRectangle(cornerRadius: SBRadius.button))
            } else {
                SBButton(
                    title: isPurchasing && purchasingProductId == product.id
                        ? "Processing..."
                        : "Get \(seatbeeProduct.displayName)",
                    icon: "sparkles",
                    variant: isPopular ? .gold : .primary,
                    fullWidth: true
                ) {
                    purchaseProduct(product)
                }
                .disabled(isPurchasing)
            }
        }
        .padding(20)
        .background(Color.sbIvory)
        .clipShape(RoundedRectangle(cornerRadius: SBRadius.card))
        .overlay(
            RoundedRectangle(cornerRadius: SBRadius.card)
                .strokeBorder(
                    isPopular && !isCurrentTier ? Color.sbGold : Color.sbLine,
                    lineWidth: isPopular && !isCurrentTier ? 2 : 1
                )
        )
        .if(isPopular && !isCurrentTier) { view in
            view.sbCardShadow()
        }
    }

    // MARK: - Purchase

    private func purchaseProduct(_ product: Product) {
        isPurchasing = true
        purchasingProductId = product.id

        Task {
            let success = await storeKit.purchase(product)
            if success {
                await appState.refreshPasses()
            }
            isPurchasing = false
            purchasingProductId = nil
        }
    }
}

#Preview {
    UpgradeView()
        .environment(AppState())
}

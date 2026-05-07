import SwiftUI
import StoreKit

struct UpgradeView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var storeKit = StoreKitService()
    @State private var selectedProduct: SeatbeeProduct = .eventPass
    @State private var isPurchasing = false
    @State private var showSuccess = false

    private var daysUntilWedding: Int? {
        guard let date = appState.activePlan?.eventDate else { return nil }
        let days = Calendar.current.dateComponents([.day], from: Date(), to: date).day
        return days.flatMap { $0 > 0 ? $0 : nil }
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    heroSection
                    planSelector.padding(.top, 28)
                    featureComparison.padding(.top, 24)
                    ctaButton.padding(.top, 28)
                    errorBanner.padding(.top, 8)
                    trustSignals.padding(.top, 20)
                    restoreButton.padding(.top, 16)
                    Spacer(minLength: 40)
                }
                .padding(.horizontal, 20)
            }
            .background(Color.sbIvory)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color.sbWarm)
                            .frame(width: 32, height: 32)
                            .background(Color.sbIvory2)
                            .clipShape(Circle())
                    }
                }
            }
            .overlay { if showSuccess { successOverlay } }
            .onChange(of: storeKit.purchaseSuccess) { _, success in
                if success {
                    Task { await appState.refreshPasses() }
                    withAnimation(.seatbeeSpring) { showSuccess = true }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) { dismiss() }
                }
            }
        }
    }

    // MARK: - Hero

    private var heroSection: some View {
        VStack(spacing: 16) {
            Spacer().frame(height: 8)

            Image("SeatbeeLogo")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 52, height: 52)

            VStack(spacing: 6) {
                Text("Let AI handle the\nseating drama")
                    .font(SBFont.fraunces(28, weight: .medium))
                    .foregroundStyle(Color.sbCharcoal)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)

                Text("One purchase. No subscription. No stress.")
                    .font(SBFont.body)
                    .foregroundStyle(Color.sbWarm)
            }

            if let days = daysUntilWedding {
                HStack(spacing: 6) {
                    Image(systemName: "calendar")
                        .font(.system(size: 12))
                    Text("Your wedding is \(days) days away")
                        .font(SBFont.inter(13, weight: .semibold))
                }
                .foregroundStyle(Color.sbGoldDk)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color.sbChampagne)
                .clipShape(Capsule())
            }
        }
    }

    // MARK: - Plan Selector

    private var planSelector: some View {
        VStack(spacing: 10) {
            ForEach(SeatbeeProduct.allCases, id: \.rawValue) { product in
                planCard(product)
            }
        }
    }

    private func planCard(_ seatbeeProduct: SeatbeeProduct) -> some View {
        let isSelected = selectedProduct == seatbeeProduct
        let isPopular = seatbeeProduct == .eventPass
        let storeProduct = storeKit.product(for: seatbeeProduct)

        return Button {
            withAnimation(.seatbee) { selectedProduct = seatbeeProduct }
            HapticEngine.selection()
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .strokeBorder(isSelected ? Color.sbGold : Color.sbWarm2, lineWidth: 2)
                        .frame(width: 22, height: 22)
                    if isSelected {
                        Circle()
                            .fill(Color.sbGold)
                            .frame(width: 12, height: 12)
                    }
                }

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(seatbeeProduct.displayName)
                            .font(SBFont.bodySemibold)
                            .foregroundStyle(Color.sbCharcoal)
                        if isPopular {
                            Text("BEST VALUE")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 2)
                                .background(Color.sbGold)
                                .clipShape(Capsule())
                        }
                    }
                    Text("Up to \(seatbeeProduct.guestLimit) guests · AI seating · 6 months")
                        .font(SBFont.caption)
                        .foregroundStyle(Color.sbWarm)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 1) {
                    Text(storeProduct?.displayPrice ?? fallbackPrice(seatbeeProduct))
                        .font(SBFont.fraunces(20, weight: .medium))
                        .foregroundStyle(isSelected ? Color.sbGoldDk : Color.sbCharcoal)
                    Text("one-time")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.sbWarm)
                }
            }
            .padding(16)
            .background(isSelected ? Color.sbChampagne.opacity(0.4) : Color.sbIvory2)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(isSelected ? Color.sbGold : Color.sbLine, lineWidth: isSelected ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func fallbackPrice(_ p: SeatbeeProduct) -> String {
        switch p {
        case .eventPass: return "$69.99"
        case .signaturePass: return "$119.99"
        case .grandPass: return "$249.99"
        }
    }

    // MARK: - Feature Comparison

    private var featureComparison: some View {
        VStack(spacing: 0) {
            HStack {
                Text("What you get")
                    .font(SBFont.label)
                    .foregroundStyle(Color.sbWarm)
                    .textCase(.uppercase)
                Spacer()
                Text("Free")
                    .font(SBFont.capsLabel)
                    .foregroundStyle(Color.sbWarm)
                    .frame(width: 44)
                Text("Pass")
                    .font(SBFont.capsLabel)
                    .foregroundStyle(Color.sbGoldDk)
                    .frame(width: 44)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)

            featureRow("Seated guests", free: "100", pass: "250–1K")
            featureRow("AI seating", free: false, pass: true)
            featureRow("Floor plan AI", free: true, pass: true)
            featureRow("Arrangements", free: "1", pass: "5–10")
            featureRow("CSV import", free: true, pass: true)
            featureRow("PDF export", free: true, pass: true)
            featureRow("Collaboration", free: true, pass: true)
            featureRow("Day-of mode", free: true, pass: true)
        }
        .padding(.vertical, 16)
        .background(Color.sbIvory2)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func featureRow(_ label: String, free: Any, pass: Any) -> some View {
        HStack {
            Text(label)
                .font(SBFont.bodySmall)
                .foregroundStyle(Color.sbCharcoal)
            Spacer()
            cellView(free, accent: false).frame(width: 44)
            cellView(pass, accent: true).frame(width: 44)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 7)
    }

    @ViewBuilder
    private func cellView(_ value: Any, accent: Bool) -> some View {
        if let b = value as? Bool {
            Image(systemName: b ? "checkmark.circle.fill" : "xmark.circle")
                .font(.system(size: 15))
                .foregroundStyle(b ? (accent ? Color.sbGold : Color.sbSage) : Color.sbWarm2)
        } else if let t = value as? String {
            Text(t)
                .font(SBFont.inter(12, weight: accent ? .semibold : .regular))
                .foregroundStyle(accent ? Color.sbGoldDk : Color.sbWarm)
        }
    }

    // MARK: - CTA

    private var ctaButton: some View {
        Button { purchase() } label: {
            HStack(spacing: 8) {
                if isPurchasing {
                    ProgressView().tint(.white)
                } else {
                    Image(systemName: "sparkles")
                        .font(.system(size: 15, weight: .semibold))
                }
                Text(isPurchasing ? "Processing..." : "Unlock \(selectedProduct.displayName)")
                    .font(SBFont.bodySemibold)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background(
                LinearGradient(colors: [Color.sbGold, Color.sbGoldDk], startPoint: .leading, endPoint: .trailing)
            )
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .shadow(color: Color.sbGold.opacity(0.3), radius: 12, x: 0, y: 6)
        }
        .buttonStyle(.plain)
        .disabled(isPurchasing)
    }

    // MARK: - Trust

    private var trustSignals: some View {
        VStack(spacing: 12) {
            HStack(spacing: 20) {
                trustBadge(icon: "lock.shield", text: "Secure\npayment")
                trustBadge(icon: "arrow.counterclockwise", text: "No auto\nrenewal")
                trustBadge(icon: "gift", text: "Shareable\ngift code")
            }
            Text("One-time purchase · No subscription · Works on web too")
                .font(SBFont.caption)
                .foregroundStyle(Color.sbWarm)
                .multilineTextAlignment(.center)
        }
    }

    private func trustBadge(icon: String, text: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundStyle(Color.sbGoldDk)
            Text(text)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Color.sbWarm)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Restore

    private var restoreButton: some View {
        Button {
            Task {
                await storeKit.restorePurchases()
                await appState.refreshPasses()
            }
        } label: {
            Text("Restore Purchases")
                .font(SBFont.bodySmall)
                .foregroundStyle(Color.sbWarm)
                .underline()
        }
        .buttonStyle(.plain)
    }

    // MARK: - Error

    @ViewBuilder
    var errorBanner: some View {
        if let error = storeKit.purchaseError {
            Text(error)
                .font(SBFont.caption)
                .foregroundStyle(Color.sbError)
                .padding(10)
                .frame(maxWidth: .infinity)
                .background(Color.sbError.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    // MARK: - Success

    private var successOverlay: some View {
        ZStack {
            Color.sbCharcoal.opacity(0.4).ignoresSafeArea()

            VStack(spacing: 16) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(Color.sbGold)
                Text("You're upgraded!")
                    .font(SBFont.displayLarge)
                    .foregroundStyle(Color.sbCharcoal)
                Text("AI seating is now unlocked")
                    .font(SBFont.body)
                    .foregroundStyle(Color.sbWarm)
            }
            .padding(40)
            .background(Color.sbIvory)
            .clipShape(RoundedRectangle(cornerRadius: 24))
            .shadow(color: Color.black.opacity(0.15), radius: 30, x: 0, y: 10)
            .transition(.scale.combined(with: .opacity))
        }
    }

    // MARK: - Purchase

    private func purchase() {
        guard let product = storeKit.product(for: selectedProduct) else {
            if let url = URL(string: "https://seatbee.app/pricing") {
                UIApplication.shared.open(url)
            }
            return
        }
        isPurchasing = true
        Task {
            _ = await storeKit.purchase(product)
            isPurchasing = false
        }
    }
}

#Preview {
    UpgradeView()
        .environment(AppState())
}

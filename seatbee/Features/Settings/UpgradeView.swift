import SwiftUI
import StoreKit

struct UpgradeView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var storeKit = StoreKitService()
    @State private var isPurchasing = false
    @State private var showSuccess = false
    @State private var shimmerOffset: CGFloat = -200
    @State private var appearAnimation = false

    private var product: SeatbeeProduct { .proMonthly }

    private var daysUntilWedding: Int? {
        guard let date = appState.activePlan?.eventDate else { return nil }
        let days = Calendar.current.dateComponents([.day], from: Date(), to: date).day
        return days.flatMap { $0 > 0 ? $0 : nil }
    }

    private var isAlreadyEntitled: Bool {
        if let sub = appState.userSubscription, sub.isProEntitled { return true }
        return storeKit.hasActiveSubscription
    }

    var body: some View {
        ZStack {
            // Background gradient — blush top, sage hint, ivory body
            LinearGradient(
                stops: [
                    .init(color: Color.sbBlush.opacity(0.25), location: 0),
                    .init(color: Color.sbChampagne.opacity(0.4), location: 0.2),
                    .init(color: Color.sbIvory, location: 0.45),
                    .init(color: Color.sbSage.opacity(0.05), location: 0.85),
                    .init(color: Color.sbIvory, location: 1),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    HStack {
                        Spacer()
                        Button { dismiss() } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(Color.sbWarm)
                                .frame(width: 30, height: 30)
                                .background(.ultraThinMaterial)
                                .clipShape(Circle())
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 16)

                    heroSection
                        .opacity(appearAnimation ? 1 : 0)
                        .offset(y: appearAnimation ? 0 : 20)

                    proCard
                        .padding(.top, 32)
                        .padding(.horizontal, 20)
                        .opacity(appearAnimation ? 1 : 0)
                        .offset(y: appearAnimation ? 0 : 30)

                    ctaButton
                        .padding(.top, 24)
                        .padding(.horizontal, 20)

                    errorBanner
                        .padding(.top, 8)
                        .padding(.horizontal, 20)

                    whatsIncluded
                        .padding(.top, 28)
                        .padding(.horizontal, 20)

                    trustSignals
                        .padding(.top, 24)

                    restoreAndLegal
                        .padding(.top, 16)
                        .padding(.bottom, 50)
                }
            }

            if showSuccess { successOverlay }
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.6).delay(0.1)) {
                appearAnimation = true
            }
            startShimmer()
        }
        .onChange(of: storeKit.purchaseSuccess) { _, success in
            if success {
                Task {
                    await appState.refreshSubscription()
                    await appState.refreshActivePlan()
                }
                withAnimation(.seatbeeSpring) { showSuccess = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { dismiss() }
            }
        }
    }

    // MARK: - Hero

    private var heroSection: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .fill(Color.sbGold.opacity(0.15))
                    .frame(width: 100, height: 100)
                    .blur(radius: 20)

                Image("SeatbeeLogo")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 60, height: 60)
            }

            VStack(spacing: 10) {
                Text("Unlock the magic")
                    .font(SBFont.fraunces(32, weight: .medium))
                    .foregroundStyle(Color.sbCharcoal)

                Text("of AI seating")
                    .font(SBFont.fraunces(32, weight: .medium))
                    .foregroundStyle(Color.sbGoldDk)
                    .italic()
            }
            .multilineTextAlignment(.center)

            Text("Cancel anytime · No commitment")
                .font(SBFont.inter(14, weight: .medium))
                .foregroundStyle(Color.sbWarm)

            if let days = daysUntilWedding {
                HStack(spacing: 8) {
                    Image(systemName: "heart.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.sbBlush)
                    Text("\(days) days until your wedding")
                        .font(SBFont.inter(13, weight: .semibold))
                        .foregroundStyle(Color.sbGoldDk)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(
                    Capsule()
                        .fill(Color.sbChampagne)
                        .overlay(
                            Capsule()
                                .strokeBorder(Color.sbGold.opacity(0.3), lineWidth: 1)
                        )
                )
            }
        }
        .padding(.top, 8)
    }

    // MARK: - Pro Card

    private var proCard: some View {
        let storeProduct = storeKit.product(for: product)

        return VStack(spacing: 0) {
            // Gold accent header
            HStack(spacing: 10) {
                Image(systemName: "crown.fill")
                    .font(.system(size: 12, weight: .bold))
                Text("SEATBEE PRO")
                    .font(.system(size: 11, weight: .heavy, design: .rounded))
                    .tracking(1.5)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(
                LinearGradient(colors: [Color.sbGold, Color.sbGoldDk], startPoint: .leading, endPoint: .trailing)
            )

            VStack(spacing: 18) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(storeProduct?.displayPrice ?? "$9.99")
                        .font(SBFont.fraunces(40, weight: .medium))
                        .foregroundStyle(Color.sbCharcoal)

                    Text("/ month")
                        .font(SBFont.inter(15, weight: .medium))
                        .foregroundStyle(Color.sbWarm)
                }
                .padding(.top, 18)

                VStack(spacing: 10) {
                    proFeatureRow(icon: "person.3.fill", text: "Up to 1,000 seated guests")
                    proFeatureRow(icon: "sparkles", text: "AI seating generation")
                    proFeatureRow(icon: "doc.viewfinder", text: "AI floor plan analysis")
                    proFeatureRow(icon: "rectangle.on.rectangle", text: "Unlimited plans")
                    proFeatureRow(icon: "clock.arrow.circlepath", text: "Cancel anytime in Settings")
                }
                .padding(.horizontal, 4)
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 22)
        }
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(Color.sbGold.opacity(0.5), lineWidth: 1.5)
        )
        .shadow(color: Color.sbGold.opacity(0.18), radius: 16, x: 0, y: 8)
    }

    private func proFeatureRow(icon: String, text: String) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.sbGold.opacity(0.12))
                    .frame(width: 28, height: 28)
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.sbGoldDk)
            }
            Text(text)
                .font(SBFont.inter(14, weight: .medium))
                .foregroundStyle(Color.sbCharcoal)
            Spacer()
        }
    }

    // MARK: - CTA

    private var productsAvailable: Bool {
        storeKit.product(for: product) != nil
    }

    private var ctaButton: some View {
        VStack(spacing: 8) {
            if isAlreadyEntitled {
                manageSubscriptionButton
            } else {
                subscribeButton
            }

            if !storeKit.isLoading && !productsAvailable && !isAlreadyEntitled {
                Text("Could not connect to the App Store. Check your connection and try again.")
                    .font(SBFont.caption)
                    .foregroundStyle(Color.sbWarm)
                    .multilineTextAlignment(.center)

                Button {
                    Task { await storeKit.fetchProducts() }
                } label: {
                    Text("Retry")
                        .font(SBFont.inter(13, weight: .semibold))
                        .foregroundStyle(Color.sbGoldDk)
                        .underline()
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var subscribeButton: some View {
        Button { purchase() } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .fill(
                        productsAvailable
                            ? LinearGradient(colors: [Color.sbGold, Color.sbGoldDk], startPoint: .leading, endPoint: .trailing)
                            : LinearGradient(colors: [Color.sbWarm2, Color.sbWarm2], startPoint: .leading, endPoint: .trailing)
                    )
                    .frame(height: 56)
                    .shadow(color: productsAvailable ? Color.sbGold.opacity(0.4) : Color.clear, radius: 16, x: 0, y: 8)

                if productsAvailable {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(
                            LinearGradient(
                                colors: [.clear, .white.opacity(0.25), .clear],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(height: 56)
                        .offset(x: shimmerOffset)
                        .mask(RoundedRectangle(cornerRadius: 16).frame(height: 56))
                }

                HStack(spacing: 10) {
                    if isPurchasing {
                        ProgressView().tint(.white)
                    } else if storeKit.isLoading {
                        ProgressView().tint(.white)
                        Text("Loading…")
                            .font(SBFont.inter(16, weight: .bold))
                    } else if !productsAvailable {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 16, weight: .semibold))
                        Text("Unavailable")
                            .font(SBFont.inter(16, weight: .bold))
                    } else {
                        Image(systemName: "sparkles")
                            .font(.system(size: 16, weight: .semibold))
                        Text("Subscribe — \(storeKit.product(for: product)?.displayPrice ?? "$9.99") / month")
                            .font(SBFont.inter(16, weight: .bold))
                    }
                }
                .foregroundStyle(.white)
            }
        }
        .buttonStyle(.plain)
        .disabled(isPurchasing || !productsAvailable)
    }

    private var manageSubscriptionButton: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.sbSage)
                Text("You're a Pro subscriber")
                    .font(SBFont.inter(15, weight: .semibold))
                    .foregroundStyle(Color.sbCharcoal)
            }

            Button {
                // System-managed subscription page. iOS deep-links to the
                // user's active subscriptions list.
                if let url = URL(string: "itms-apps://apps.apple.com/account/subscriptions") {
                    openURL(url)
                }
            } label: {
                Text("Manage Subscription")
                    .font(SBFont.inter(15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(
                        LinearGradient(colors: [Color.sbGold, Color.sbGoldDk], startPoint: .leading, endPoint: .trailing)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - What's Included

    private var whatsIncluded: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("EVERYTHING YOU GET")
                .font(SBFont.capsLabel)
                .foregroundStyle(Color.sbWarm)
                .letterSpacing(2)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                featureItem(icon: "sparkles", title: "AI Seating", subtitle: "Auto-arrange guests", tint: Color.sbGold)
                featureItem(icon: "person.3.fill", title: "1,000 Guests", subtitle: "Seated capacity", tint: Color.sbSage)
                featureItem(icon: "doc.viewfinder", title: "Floor Plan AI", subtitle: "Scan your venue", tint: Color.sbBlush)
                featureItem(icon: "rectangle.on.rectangle", title: "Arrangements", subtitle: "Multiple layouts", tint: Color(hex: "8B9DC3"))
                featureItem(icon: "doc.text", title: "PDF Export", subtitle: "Print-ready charts", tint: Color(hex: "DDA0DD"))
                featureItem(icon: "person.2", title: "Collaborate", subtitle: "Share with planner", tint: Color(hex: "87CEEB"))
            }
        }
    }

    private func featureItem(icon: String, title: String, subtitle: String, tint: Color = Color.sbGold) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(tint)
                .frame(width: 36, height: 36)
                .background(tint.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(SBFont.inter(13, weight: .semibold))
                    .foregroundStyle(Color.sbCharcoal)
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.sbWarm)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Trust

    private var trustSignals: some View {
        HStack(spacing: 0) {
            trustBadge(icon: "lock.shield.fill", label: "Secure")
            dividerLine
            trustBadge(icon: "clock.arrow.circlepath", label: "Cancel anytime")
            dividerLine
            trustBadge(icon: "creditcard", label: "Apple billed")
            dividerLine
            trustBadge(icon: "globe", label: "Web + iOS")
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 12)
        .background(Color.sbIvory2)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 20)
    }

    private var dividerLine: some View {
        Rectangle()
            .fill(Color.sbLine)
            .frame(width: 1, height: 28)
    }

    private func trustBadge(icon: String, label: String) -> some View {
        VStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundStyle(Color.sbGoldDk)
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Color.sbWarm)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Restore & Legal

    private var restoreAndLegal: some View {
        VStack(spacing: 8) {
            Button {
                Task {
                    await storeKit.restorePurchases()
                    await appState.refreshSubscription()
                }
            } label: {
                Text("Restore Purchases")
                    .font(SBFont.inter(13, weight: .medium))
                    .foregroundStyle(Color.sbWarm)
                    .underline()
            }
            .buttonStyle(.plain)

            // Apple HIG requires legal copy near the auto-renewable
            // subscription CTA. Renewal is automatic at the end of each
            // billing period unless canceled at least 24h before renewal.
            Text("Auto-renews monthly until canceled in Settings. Payment charged to your Apple ID.")
                .font(.system(size: 10))
                .foregroundStyle(Color.sbWarm2)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
    }

    // MARK: - Error

    @ViewBuilder
    var errorBanner: some View {
        if let error = storeKit.purchaseError {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(Color.sbError)
                Text(error)
                    .font(SBFont.caption)
                    .foregroundStyle(Color.sbError)
            }
            .padding(12)
            .frame(maxWidth: .infinity)
            .background(Color.sbError.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }

    // MARK: - Success Overlay

    private var successOverlay: some View {
        ZStack {
            Color.sbCharcoal.opacity(0.5)
                .ignoresSafeArea()

            VStack(spacing: 20) {
                ZStack {
                    Circle()
                        .fill(Color.sbGold.opacity(0.15))
                        .frame(width: 120, height: 120)
                        .blur(radius: 20)

                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 64))
                        .foregroundStyle(Color.sbGold)
                        .symbolEffect(.bounce, value: showSuccess)
                }

                Text("Welcome to\nSeatbee Pro!")
                    .font(SBFont.fraunces(28, weight: .medium))
                    .foregroundStyle(Color.sbCharcoal)
                    .multilineTextAlignment(.center)

                Text("AI seating is now unlocked.\nYour perfect arrangement awaits.")
                    .font(SBFont.body)
                    .foregroundStyle(Color.sbWarm)
                    .multilineTextAlignment(.center)
            }
            .padding(44)
            .background(
                RoundedRectangle(cornerRadius: 28)
                    .fill(Color.sbIvory)
                    .shadow(color: Color.black.opacity(0.2), radius: 40, x: 0, y: 15)
            )
            .padding(.horizontal, 32)
            .transition(.scale(scale: 0.85).combined(with: .opacity))
        }
    }

    // MARK: - Purchase

    private func purchase() {
        guard let storeProduct = storeKit.product(for: product) else {
            storeKit.purchaseError = "Unable to load this product from the App Store. Please check your connection and try again."
            return
        }
        isPurchasing = true
        Task {
            _ = await storeKit.purchase(storeProduct)
            isPurchasing = false
        }
    }

    // MARK: - Shimmer Animation

    private func startShimmer() {
        withAnimation(.linear(duration: 2.5).repeatForever(autoreverses: false)) {
            shimmerOffset = 400
        }
    }
}

#Preview {
    UpgradeView()
        .environment(AppState())
}

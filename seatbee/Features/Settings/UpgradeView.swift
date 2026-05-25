import SwiftUI
import StoreKit

struct UpgradeView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var storeKit = StoreKitService()
    @State private var selectedProduct: SeatbeeProduct = .eventPass
    @State private var isPurchasing = false
    @State private var showSuccess = false
    @State private var shimmerOffset: CGFloat = -200
    @State private var appearAnimation = false

    private var daysUntilWedding: Int? {
        guard let date = appState.activePlan?.eventDate else { return nil }
        let days = Calendar.current.dateComponents([.day], from: Date(), to: date).day
        return days.flatMap { $0 > 0 ? $0 : nil }
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
                    // Close button
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

                    // Hero
                    heroSection
                        .opacity(appearAnimation ? 1 : 0)
                        .offset(y: appearAnimation ? 0 : 20)

                    // Plans
                    planSelector
                        .padding(.top, 32)
                        .opacity(appearAnimation ? 1 : 0)
                        .offset(y: appearAnimation ? 0 : 30)

                    // CTA
                    ctaButton
                        .padding(.top, 24)
                        .padding(.horizontal, 20)

                    // Error
                    errorBanner
                        .padding(.top, 8)
                        .padding(.horizontal, 20)

                    // What's included
                    whatsIncluded
                        .padding(.top, 28)
                        .padding(.horizontal, 20)

                    // Trust
                    trustSignals
                        .padding(.top, 24)

                    // Restore + legal
                    restoreAndLegal
                        .padding(.top, 16)
                        .padding(.bottom, 50)
                }
            }

            // Success overlay
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
                    await appState.refreshActivePlan()
                    await appState.refreshPasses()
                }
                withAnimation(.seatbeeSpring) { showSuccess = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { dismiss() }
            }
        }
    }

    // MARK: - Hero

    private var heroSection: some View {
        VStack(spacing: 20) {
            // Floating logo with glow
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

            Text("One purchase · No subscription · Yours forever")
                .font(SBFont.inter(14, weight: .medium))
                .foregroundStyle(Color.sbWarm)

            // Wedding countdown
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

    // MARK: - Plan Cards

    private var planSelector: some View {
        VStack(spacing: 12) {
            ForEach(SeatbeeProduct.allCases, id: \.rawValue) { product in
                planCard(product)
            }
        }
        .padding(.horizontal, 20)
    }

    private func planCard(_ seatbeeProduct: SeatbeeProduct) -> some View {
        let isSelected = selectedProduct == seatbeeProduct
        let isPopular = seatbeeProduct == .eventPass
        let storeProduct = storeKit.product(for: seatbeeProduct)

        return Button {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                selectedProduct = seatbeeProduct
            }
            HapticEngine.selection()
        } label: {
            VStack(spacing: 0) {
                // "MOST POPULAR" ribbon
                if isPopular {
                    Text("MOST POPULAR")
                        .font(.system(size: 10, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(
                            LinearGradient(colors: [Color.sbSage, Color.sbSage.opacity(0.8)], startPoint: .leading, endPoint: .trailing)
                        )
                }

                HStack(spacing: 16) {
                    // Icon — each tier has its own accent color
                    ZStack {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(
                                isSelected
                                    ? LinearGradient(colors: tierColors(seatbeeProduct), startPoint: .topLeading, endPoint: .bottomTrailing)
                                    : LinearGradient(colors: [tierAccent(seatbeeProduct).opacity(0.1), tierAccent(seatbeeProduct).opacity(0.05)], startPoint: .topLeading, endPoint: .bottomTrailing)
                            )
                            .frame(width: 48, height: 48)

                        Image(systemName: seatbeeProduct == .grandPass ? "crown.fill" : (seatbeeProduct == .signaturePass ? "star.fill" : "sparkles"))
                            .font(.system(size: 20))
                            .foregroundStyle(isSelected ? .white : tierAccent(seatbeeProduct))
                    }

                    // Details
                    VStack(alignment: .leading, spacing: 4) {
                        Text(seatbeeProduct.displayName)
                            .font(SBFont.bodySemibold)
                            .foregroundStyle(Color.sbCharcoal)

                        Text("Up to \(seatbeeProduct.guestLimit) guests")
                            .font(SBFont.caption)
                            .foregroundStyle(Color.sbWarm)
                    }

                    Spacer()

                    // Price
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(storeProduct?.displayPrice ?? fallbackPrice(seatbeeProduct))
                            .font(SBFont.fraunces(22, weight: .medium))
                            .foregroundStyle(isSelected ? Color.sbGoldDk : Color.sbCharcoal)

                        Text("one-time")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(Color.sbWarm)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
            }
            .background(
                RoundedRectangle(cornerRadius: isPopular ? 16 : 14)
                    .fill(isSelected ? Color.sbChampagne.opacity(0.35) : Color.white)
            )
            .clipShape(RoundedRectangle(cornerRadius: isPopular ? 16 : 14))
            .overlay(
                RoundedRectangle(cornerRadius: isPopular ? 16 : 14)
                    .strokeBorder(
                        isSelected ? tierAccent(seatbeeProduct) : Color.sbLine,
                        lineWidth: isSelected ? 2.5 : 1
                    )
            )
            .shadow(
                color: isSelected ? tierAccent(seatbeeProduct).opacity(0.2) : Color.clear,
                radius: isSelected ? 12 : 0,
                x: 0,
                y: isSelected ? 6 : 0
            )
            .scaleEffect(isSelected ? 1.02 : 1.0)
        }
        .buttonStyle(.plain)
    }

    // Per-tier accent colors — breaks the gold monotone
    private func tierAccent(_ p: SeatbeeProduct) -> Color {
        switch p {
        case .eventPass: return Color.sbSage
        case .signaturePass: return Color.sbBlush
        case .grandPass: return Color.sbGold
        }
    }

    private func tierColors(_ p: SeatbeeProduct) -> [Color] {
        switch p {
        case .eventPass: return [Color.sbSage, Color.sbSage.opacity(0.8)]
        case .signaturePass: return [Color.sbBlush, Color.sbBlush.opacity(0.8)]
        case .grandPass: return [Color.sbGold, Color.sbGoldDk]
        }
    }

    private func fallbackPrice(_ p: SeatbeeProduct) -> String {
        // Shown only while StoreKit is loading the live product prices from
        // App Store Connect. These must match whatever IAP tier Shayan
        // configures there — keep in lockstep with the web prices in
        // ~/Desktop/Seated/api/create-checkout.js PACK_PRICES.
        switch p {
        case .eventPass: return "$29"
        case .signaturePass: return "$49"
        case .grandPass: return "$149"
        }
    }

    // MARK: - CTA Button with Shimmer

    private var productsAvailable: Bool {
        storeKit.product(for: selectedProduct) != nil
    }

    private var ctaButton: some View {
        VStack(spacing: 8) {
            Button { purchase() } label: {
                ZStack {
                    // Base gradient — grey when unavailable
                    RoundedRectangle(cornerRadius: 16)
                        .fill(
                            productsAvailable
                                ? LinearGradient(colors: [Color.sbGold, Color.sbGoldDk], startPoint: .leading, endPoint: .trailing)
                                : LinearGradient(colors: [Color.sbWarm2, Color.sbWarm2], startPoint: .leading, endPoint: .trailing)
                        )
                        .frame(height: 56)
                        .shadow(color: productsAvailable ? Color.sbGold.opacity(0.4) : Color.clear, radius: 16, x: 0, y: 8)

                    // Shimmer overlay — only when products loaded
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

                    // Content
                    HStack(spacing: 10) {
                        if isPurchasing {
                            ProgressView().tint(.white)
                        } else if storeKit.isLoading {
                            ProgressView().tint(.white)
                            Text("Loading prices...")
                                .font(SBFont.inter(16, weight: .bold))
                        } else if !productsAvailable {
                            Image(systemName: "exclamationmark.triangle")
                                .font(.system(size: 16, weight: .semibold))
                            Text("Unavailable")
                                .font(SBFont.inter(16, weight: .bold))
                        } else {
                            Image(systemName: "sparkles")
                                .font(.system(size: 16, weight: .semibold))
                            Text("Unlock \(selectedProduct.displayName)")
                                .font(SBFont.inter(16, weight: .bold))
                        }
                    }
                    .foregroundStyle(.white)
                }
            }
            .buttonStyle(.plain)
            .disabled(isPurchasing || !productsAvailable)

            // Hint when products fail to load
            if !storeKit.isLoading && !productsAvailable {
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

    // MARK: - What's Included

    private var whatsIncluded: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("EVERYTHING YOU GET")
                .font(SBFont.capsLabel)
                .foregroundStyle(Color.sbWarm)
                .letterSpacing(2)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                featureItem(icon: "sparkles", title: "AI Seating", subtitle: "Auto-arrange guests", tint: Color.sbGold)
                featureItem(icon: "person.3.fill", title: "\(selectedProduct.guestLimit) Guests", subtitle: "Seated capacity", tint: Color.sbSage)
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
            trustBadge(icon: "clock.arrow.circlepath", label: "No renewal")
            dividerLine
            trustBadge(icon: "gift.fill", label: "Giftable")
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
                    await appState.refreshPasses()
                }
            } label: {
                Text("Restore Purchases")
                    .font(SBFont.inter(13, weight: .medium))
                    .foregroundStyle(Color.sbWarm)
                    .underline()
            }
            .buttonStyle(.plain)

            Text("Manage your subscription in Settings")
                .font(.system(size: 11))
                .foregroundStyle(Color.sbWarm2)
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

                Text("Welcome to\n\(selectedProduct.displayName)!")
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
        guard let product = storeKit.product(for: selectedProduct) else {
            storeKit.purchaseError = "Unable to load this product from the App Store. Please check your connection and try again."
            return
        }
        isPurchasing = true
        Task {
            _ = await storeKit.purchase(product)
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

import Foundation
import StoreKit

// MARK: - Product IDs

enum SeatbeeProduct: String, CaseIterable {
    // NEW (2026-05-28): single subscription replaces all three one-time passes.
    // Configured as an auto-renewable subscription in App Store Connect at $9.99/mo.
    case proMonthly = "com.shayan.seatbee.pro_monthly"

    // LEGACY one-time passes. Kept in the enum so any in-flight transactions
    // from users who purchased pre-migration still finish + verify cleanly.
    // Not shown in UpgradeView anymore — see UpgradeView for the post-migration UI.
    case eventPass = "com.shayan.seatbee.event_pass"
    case signaturePass = "com.shayan.seatbee.signature_pass"
    case grandPass = "com.shayan.seatbee.grand_pass"

    /// True if this product is the live subscription. Used to gate
    /// subscription-specific UI (manage-subscription link, renewal copy)
    /// off legacy one-time pass behaviour.
    var isSubscription: Bool {
        switch self {
        case .proMonthly: return true
        case .eventPass, .signaturePass, .grandPass: return false
        }
    }

    var tier: PlanTier {
        switch self {
        case .proMonthly: return .pro
        case .eventPass: return .eventPass
        case .signaturePass: return .signaturePass
        case .grandPass: return .proPass
        }
    }

    var displayName: String {
        switch self {
        case .proMonthly: return "Seatbee Pro"
        case .eventPass: return "Event Pass"
        case .signaturePass: return "Signature Pass"
        case .grandPass: return "Grand Event Pass"
        }
    }

    var guestLimit: Int {
        switch self {
        case .proMonthly: return 1000
        case .eventPass: return 250
        case .signaturePass: return 500
        case .grandPass: return 1000
        }
    }

    var features: [String] {
        switch self {
        case .proMonthly:
            return [
                "Up to 1,000 seated guests",
                "AI seating generation",
                "AI floor plan analysis",
                "Unlimited plans",
                "Cancel anytime",
            ]
        case .eventPass:
            return ["250 seated guests", "AI seating generation", "AI floor plan analysis", "6-month access"]
        case .signaturePass:
            return ["500 seated guests", "AI seating generation", "AI floor plan analysis", "7 arrangements", "6-month access"]
        case .grandPass:
            return ["1,000 seated guests", "AI seating generation", "AI floor plan analysis", "10 arrangements", "6-month access"]
        }
    }
}

// MARK: - StoreKit Service

@Observable
final class StoreKitService {
    var products: [Product] = []
    var purchasedProductIDs: Set<String> = []
    var isLoading = false
    var purchaseError: String?
    var purchaseSuccess = false

    /// True when the user has an active auto-renewable subscription entitlement
    /// from StoreKit (currentEntitlements). Refreshed by the transaction listener
    /// and by `restorePurchases`. Used as a client-side fallback when the
    /// backend hasn't yet propagated the subscription status — the source of
    /// truth is still `profiles.subscription_status` on Supabase.
    var hasActiveSubscription = false

    private var transactionListener: Task<Void, Never>?

    init() {
        transactionListener = listenForTransactions()
        Task {
            await fetchProducts()
            await refreshSubscriptionEntitlement()
        }
    }

    deinit {
        transactionListener?.cancel()
    }

    // MARK: - Fetch Products

    func fetchProducts() async {
        isLoading = true
        do {
            // Phaseout 2026-06-08: legacy one-time pass products are no
            // longer shown in UI. Only fetch the live subscription so
            // App Store Connect doesn't surface unused IDs in the cache.
            // Legacy IDs stay defined on SeatbeeProduct for verification
            // of any in-flight transactions from pre-migration purchases.
            let productIDs = [SeatbeeProduct.proMonthly.rawValue]
            products = try await Product.products(for: productIDs)
            products.sort { ($0.price as NSDecimalNumber).doubleValue < ($1.price as NSDecimalNumber).doubleValue }
            print("[StoreKit] Fetched \(products.count) products")
        } catch {
            print("[StoreKit] Failed to fetch products: \(error)")
        }
        isLoading = false
    }

    // MARK: - Purchase

    func purchase(_ product: Product) async -> Bool {
        purchaseError = nil
        purchaseSuccess = false

        do {
            let result = try await product.purchase()

            switch result {
            case .success(let verification):
                let transaction = try checkVerified(verification)
                // Verify server-side and create pass/subscription in Supabase
                let verified = await verifyWithServer(transaction: transaction, productID: product.id)
                if verified {
                    await transaction.finish()
                    purchasedProductIDs.insert(product.id)
                    purchaseSuccess = true
                    // Subscription entitlement is now active; refresh our flag.
                    if product.id == SeatbeeProduct.proMonthly.rawValue {
                        hasActiveSubscription = true
                    }
                    print("[StoreKit] Purchase successful: \(product.id)")
                    return true
                } else {
                    // Don't finish the transaction — Apple will re-deliver it
                    // via Transaction.updates so we can retry on next launch.
                    purchaseError = "Purchase recorded but activation failed. Tap Restore Purchases to retry."
                    return false
                }

            case .userCancelled:
                print("[StoreKit] User cancelled")
                return false

            case .pending:
                print("[StoreKit] Purchase pending (ask to buy)")
                purchaseError = "Purchase is pending approval."
                return false

            @unknown default:
                purchaseError = "Unknown purchase result."
                return false
            }
        } catch {
            purchaseError = error.localizedDescription
            print("[StoreKit] Purchase error: \(error)")
            return false
        }
    }

    // MARK: - Restore Purchases

    func restorePurchases() async {
        isLoading = true
        do {
            try await AppStore.sync()
            // Check current entitlements — this covers both legacy one-time
            // passes still in the user's history AND the active subscription.
            await refreshSubscriptionEntitlement()
            for await result in Transaction.currentEntitlements {
                if let transaction = try? checkVerified(result) {
                    purchasedProductIDs.insert(transaction.productID)
                    await verifyWithServer(transaction: transaction, productID: transaction.productID)
                }
            }
            print("[StoreKit] Restore complete. \(purchasedProductIDs.count) products restored.")
        } catch {
            purchaseError = "Restore failed: \(error.localizedDescription)"
            print("[StoreKit] Restore error: \(error)")
        }
        isLoading = false
    }

    /// Walk `Transaction.currentEntitlements` and set `hasActiveSubscription`
    /// based on whether the user holds an unexpired pro_monthly entitlement.
    /// Idempotent — safe to call from launch, after purchase, after restore.
    func refreshSubscriptionEntitlement() async {
        var active = false
        for await result in Transaction.currentEntitlements {
            guard let transaction = try? checkVerified(result) else { continue }
            if transaction.productID == SeatbeeProduct.proMonthly.rawValue {
                // For auto-renewables, currentEntitlements only includes the
                // entitlement while it's active (revocationDate==nil and not
                // past expirationDate). Presence alone is sufficient.
                if transaction.revocationDate == nil {
                    active = true
                }
            }
        }
        await MainActor.run { self.hasActiveSubscription = active }
    }

    // MARK: - Transaction Listener

    private func listenForTransactions() -> Task<Void, Never> {
        Task.detached {
            for await result in Transaction.updates {
                if let transaction = try? self.checkVerified(result) {
                    await self.verifyWithServer(transaction: transaction, productID: transaction.productID)
                    await transaction.finish()
                    await MainActor.run {
                        self.purchasedProductIDs.insert(transaction.productID)
                    }
                    // Renewal / cancellation events for the subscription —
                    // recompute the entitlement flag.
                    if transaction.productID == SeatbeeProduct.proMonthly.rawValue {
                        await self.refreshSubscriptionEntitlement()
                    }
                }
            }
        }
    }

    // MARK: - Verification

    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified(_, let error):
            throw error
        case .verified(let value):
            return value
        }
    }

    // MARK: - Server-Side Verification

    /// Sends the transaction to our Vercel endpoint for server-side verification.
    /// The endpoint verifies with Apple and creates the event_pass (legacy)
    /// OR updates `profiles.subscription_status` (pro_monthly) in Supabase.
    @discardableResult
    private func verifyWithServer(transaction: Transaction, productID: String) async -> Bool {
        guard let url = URL(string: AppConfig.aiAPIBaseURL.replacingOccurrences(of: "/api/ai", with: "/api/apple-iap")) else {
            print("[StoreKit] Invalid server URL")
            return false
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Attach auth token
        if let token = await AuthService().accessToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let body: [String: Any] = [
            "transactionId": Int(transaction.id),
            "originalTransactionId": Int(transaction.originalID),
            "productId": productID,
            "environment": transaction.environment.rawValue,
            "purchaseDate": ISO8601DateFormatter().string(from: transaction.purchaseDate),
        ]

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else { return false }

            if httpResponse.statusCode == 200 {
                print("[StoreKit] Server verification succeeded for \(productID)")
                return true
            } else {
                let responseBody = String(data: data, encoding: .utf8) ?? ""
                print("[StoreKit] Server verification failed (\(httpResponse.statusCode)): \(responseBody)")
                return false
            }
        } catch {
            print("[StoreKit] Server verification error: \(error)")
            return false
        }
    }

    // MARK: - Helpers

    func product(for seatbeeProduct: SeatbeeProduct) -> Product? {
        products.first { $0.id == seatbeeProduct.rawValue }
    }

    func priceString(for product: Product) -> String {
        product.displayPrice
    }
}

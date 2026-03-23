import StoreKit

/// Manages all StoreKit 2 operations: product fetch, purchase, restore, and background transaction updates.
class StoreKitManager {

    static let productIds = ["uk.delayrepay.pro.yearly", "uk.delayrepay.pro.monthly"]

    /// Cached products after first successful fetch
    private var cachedProducts: [Product] = []

    /// Background task listening for transaction updates
    private var transactionListener: Task<Void, Error>?

    init() {
        startTransactionListener()
    }

    deinit {
        transactionListener?.cancel()
    }

    // MARK: - Transaction Updates Listener
    
    /// Listens for transactions that complete outside the normal purchase flow:
    /// - Purchases approved by Ask to Buy
    /// - Subscription renewals
    /// - Purchases started on another device
    /// - Transactions that were interrupted
    private func startTransactionListener() {
        transactionListener = Task.detached(priority: .background) {
            for await result in Transaction.updates {
                switch result {
                case .verified(let transaction):
                    print("[STOREKIT] Transaction update: \(transaction.productID) (id: \(transaction.id))")
                    await transaction.finish()
                    await MainActor.run {
                        NotificationCenter.default.post(
                            name: NSNotification.Name("TransactionUpdated"),
                            object: [
                                "transactionId": String(transaction.id),
                                "productId": transaction.productID
                            ]
                        )
                    }
                case .unverified(let transaction, let error):
                    print("[STOREKIT] Unverified transaction: \(transaction.productID) — \(error.localizedDescription)")
                }
            }
        }
    }

    // MARK: - Get Products

    func getProducts(
        onSuccess: @escaping ([[String: Any]]) -> Void,
        onError: @escaping (String) -> Void
    ) {
        Task {
            do {
                let products: [Product]
                if !cachedProducts.isEmpty {
                    products = cachedProducts
                } else {
                    products = try await Product.products(for: Self.productIds)
                    cachedProducts = products
                }

                if products.isEmpty {
                    await MainActor.run {
                        onError("No products available. Please check your App Store Connect configuration.")
                    }
                    return
                }

                let result = products.map { product -> [String: Any] in
                    var info: [String: Any] = [
                        "id": product.id,
                        "displayName": product.displayName,
                        "displayPrice": product.displayPrice,
                        "description": product.description,
                        "price": NSDecimalNumber(decimal: product.price).doubleValue
                    ]

                    if let subscription = product.subscription {
                        let unit = subscription.subscriptionPeriod.unit
                        let value = subscription.subscriptionPeriod.value
                        var periodLabel = ""
                        switch unit {
                        case .year: periodLabel = value == 1 ? "year" : "\(value) years"
                        case .month: periodLabel = value == 1 ? "month" : "\(value) months"
                        case .week: periodLabel = value == 1 ? "week" : "\(value) weeks"
                        case .day: periodLabel = value == 1 ? "day" : "\(value) days"
                        @unknown default: periodLabel = "period"
                        }
                        info["period"] = periodLabel
                    }

                    return info
                }

                await MainActor.run { onSuccess(result) }
            } catch {
                print("[STOREKIT] getProducts error: \(error)")
                await MainActor.run { onError(error.localizedDescription) }
            }
        }
    }

    // MARK: - Purchase

    func purchase(
        productId: String,
        onSuccess: @escaping (String, String) -> Void,
        onError: @escaping (String) -> Void
    ) {
        Task {
            do {
                var product = cachedProducts.first(where: { $0.id == productId })
                if product == nil {
                    let products = try await Product.products(for: [productId])
                    product = products.first
                }

                guard let product = product else {
                    await MainActor.run { onError("Product not found: \(productId)") }
                    return
                }

                let result = try await product.purchase()

                switch result {
                case .success(let verification):
                    switch verification {
                    case .verified(let transaction):
                        await transaction.finish()
                        let txId = String(transaction.id)
                        await MainActor.run { onSuccess(txId, transaction.productID) }

                    case .unverified(_, let error):
                        await MainActor.run { onError("Transaction could not be verified: \(error.localizedDescription)") }
                    }

                case .userCancelled:
                    await MainActor.run { onError("cancelled") }

                case .pending:
                    await MainActor.run { onError("pending") }

                @unknown default:
                    await MainActor.run { onError("Unknown purchase result") }
                }
            } catch let error as StoreKitError {
                let message: String
                switch error {
                case .networkError:
                    message = "Network error. Please check your connection and try again."
                case .userCancelled:
                    message = "cancelled"
                case .notAvailableInStorefront:
                    message = "This subscription is not available in your region."
                default:
                    message = error.localizedDescription
                }
                await MainActor.run { onError(message) }
            } catch {
                await MainActor.run { onError(error.localizedDescription) }
            }
        }
    }

    // MARK: - Restore

    func restore(
        onSuccess: @escaping (String, String) -> Void,
        onError: @escaping (String) -> Void
    ) {
        Task {
            do {
                try await AppStore.sync()

                var found = false
                for await result in Transaction.currentEntitlements {
                    if case .verified(let transaction) = result,
                       transaction.productType == .autoRenewable {
                        found = true
                        let txId = String(transaction.id)
                        await MainActor.run { onSuccess(txId, transaction.productID) }
                        break
                    }
                }

                if !found {
                    await MainActor.run { onError("No active subscription found") }
                }
            } catch {
                await MainActor.run { onError(error.localizedDescription) }
            }
        }
    }
}

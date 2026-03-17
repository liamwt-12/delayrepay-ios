import StoreKit

class StoreKitManager {

    let productIds = ["uk.delayrepay.pro.yearly", "uk.delayrepay.pro.monthly"]

    func getProducts(onSuccess: @escaping ([[String: Any]]) -> Void, onError: @escaping (String) -> Void) {
        Task {
            do {
                let products = try await Product.products(for: productIds)
                let result = products.map { p -> [String: Any] in
                    ["id": p.id, "displayName": p.displayName, "displayPrice": p.displayPrice, "description": p.description]
                }
                await MainActor.run { onSuccess(result) }
            } catch {
                await MainActor.run { onError(error.localizedDescription) }
            }
        }
    }

    func purchase(productId: String, onSuccess: @escaping (String, String) -> Void, onError: @escaping (String) -> Void) {
        Task {
            do {
                let products = try await Product.products(for: [productId])
                guard let product = products.first else {
                    await MainActor.run { onError("Product not found") }
                    return
                }
                let result = try await product.purchase()
                switch result {
                case .success(let verification):
                    switch verification {
                    case .verified(let transaction):
                        await transaction.finish()
                        await MainActor.run { onSuccess(String(transaction.id), transaction.productID) }
                    case .unverified:
                        await MainActor.run { onError("Transaction unverified") }
                    }
                case .userCancelled:
                    await MainActor.run { onError("User cancelled") }
                case .pending:
                    await MainActor.run { onError("Transaction pending") }
                @unknown default:
                    await MainActor.run { onError("Unknown result") }
                }
            } catch {
                await MainActor.run { onError(error.localizedDescription) }
            }
        }
    }

    func restore(onSuccess: @escaping (String, String) -> Void, onError: @escaping (String) -> Void) {
        Task {
            do {
                try await AppStore.sync()
                var found = false
                for await result in Transaction.currentEntitlements {
                    if case .verified(let transaction) = result, transaction.productType == .autoRenewable {
                        found = true
                        await MainActor.run { onSuccess(String(transaction.id), transaction.productID) }
                        break
                    }
                }
                if !found {
                    await MainActor.run { onError("No active subscription") }
                }
            } catch {
                await MainActor.run { onError(error.localizedDescription) }
            }
        }
    }
}

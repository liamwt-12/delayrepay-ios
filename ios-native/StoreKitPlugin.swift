import StoreKit
import Capacitor

@objc(StoreKitPlugin)
public class StoreKitPlugin: CAPPlugin {

    @objc func getProducts(_ call: CAPPluginCall) {
        Task {
            do {
                let products = try await Product.products(for: ["6759902262", "6759902546"])
                var result: [[String: Any]] = []
                for product in products {
                    result.append([
                        "id": product.id,
                        "displayName": product.displayName,
                        "displayPrice": product.displayPrice,
                        "description": product.description
                    ])
                }
                call.resolve(["products": result])
            } catch {
                call.reject("Failed to load products", nil, error)
            }
        }
    }

    @objc func purchase(_ call: CAPPluginCall) {
        guard let productId = call.getString("productId") else {
            call.reject("Missing productId")
            return
        }

        Task {
            do {
                let products = try await Product.products(for: [productId])
                guard let product = products.first else {
                    call.reject("Product not found")
                    return
                }

                let result = try await product.purchase()
                switch result {
                case .success(let verification):
                    switch verification {
                    case .verified(let transaction):
                        await transaction.finish()
                        call.resolve([
                            "success": true,
                            "transactionId": String(transaction.id),
                            "productId": transaction.productID,
                            "originalId": String(transaction.originalID)
                        ])
                    case .unverified:
                        call.reject("Transaction unverified")
                    }
                case .userCancelled:
                    call.reject("User cancelled")
                case .pending:
                    call.reject("Transaction pending")
                @unknown default:
                    call.reject("Unknown result")
                }
            } catch {
                call.reject("Purchase failed", nil, error)
            }
        }
    }

    @objc func restorePurchases(_ call: CAPPluginCall) {
        Task {
            do {
                try await AppStore.sync()
                var activeSubscription = false
                for await result in Transaction.currentEntitlements {
                    if case .verified(let transaction) = result {
                        if transaction.productType == .autoRenewable {
                            activeSubscription = true
                        }
                    }
                }
                call.resolve(["hasActiveSubscription": activeSubscription])
            } catch {
                call.reject("Restore failed", nil, error)
            }
        }
    }
}

import StoreKit

enum PurchaseResult {
    case success
    case userCancelled
    case pending
}

enum StoreKitManagerError: Error {
    case unverifiedTransaction
}

/// Local entitlement truth via `Transaction.currentEntitlements` — no backend
/// reconciliation yet (nothing is feature-gated server-side in this MVP).
/// Backed in development by `Products.storekit` (Simulator-only, zero App
/// Store Connect setup needed); real products must be created there before
/// TestFlight/submission.
@MainActor
@Observable
final class StoreKitManager {
    private(set) var products: [Product] = []
    private(set) var purchasedProductIDs: Set<String> = []

    // Task.cancel() is thread-safe; deinit runs nonisolated, so this can't be MainActor-isolated.
    // @ObservationIgnored: not UI-facing state, and the Observable macro's tracked-property
    // expansion conflicts with `nonisolated` on a mutable stored property.
    @ObservationIgnored
    private nonisolated(unsafe) var updatesTask: Task<Void, Never>?

    init() {
        updatesTask = Task { @MainActor [weak self] in
            for await update in Transaction.updates {
                self?.handle(update)
            }
        }
    }

    deinit {
        updatesTask?.cancel()
    }

    func loadProducts() async {
        do {
            products = try await Product.products(for: ProductIdentifiers.all)
        } catch {
            products = []
        }
    }

    func product(for id: String) -> Product? {
        products.first { $0.id == id }
    }

    @discardableResult
    func purchase(_ product: Product) async throws -> PurchaseResult {
        let result = try await product.purchase()
        switch result {
        case .success(let verification):
            let transaction = try checkVerified(verification)
            purchasedProductIDs.insert(transaction.productID)
            await transaction.finish()
            return .success
        case .userCancelled:
            return .userCancelled
        case .pending:
            return .pending
        @unknown default:
            return .pending
        }
    }

    func refreshEntitlements() async {
        var purchased: Set<String> = []
        for await entitlement in Transaction.currentEntitlements {
            if let transaction = try? checkVerified(entitlement) {
                purchased.insert(transaction.productID)
            }
        }
        purchasedProductIDs = purchased
    }

    private func handle(_ update: VerificationResult<Transaction>) {
        guard let transaction = try? checkVerified(update) else { return }
        purchasedProductIDs.insert(transaction.productID)
        Task { await transaction.finish() }
    }

    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified:
            throw StoreKitManagerError.unverifiedTransaction
        case .verified(let safe):
            return safe
        }
    }
}

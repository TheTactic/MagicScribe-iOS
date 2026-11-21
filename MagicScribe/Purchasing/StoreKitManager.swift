import StoreKit

enum PurchaseResult {
    case success
    case userCancelled
    case pending
}

enum StoreKitManagerError: Error {
    case unverifiedTransaction
    case serverVerificationFailed(String)
}

/// Local StoreKit state (`purchasedProductIDs`) is a UX hint only — the
/// server's plan, returned by api/apple_iap_verify.php, is the actual gate.
/// Backed in development by `Products.storekit` (Simulator-only, zero App
/// Store Connect setup needed); real products must be created there before
/// TestFlight/submission.
@MainActor
@Observable
final class StoreKitManager {
    private(set) var products: [Product] = []
    private(set) var purchasedProductIDs: Set<String> = []
    /// Set only after api/apple_iap_verify.php confirms the purchase —
    /// never from local StoreKit state alone.
    private(set) var verifiedPlan: String?

    private let client: APIClient

    // Task.cancel() is thread-safe; deinit runs nonisolated, so this can't be MainActor-isolated.
    // @ObservationIgnored: not UI-facing state, and the Observable macro's tracked-property
    // expansion conflicts with `nonisolated` on a mutable stored property.
    @ObservationIgnored
    private nonisolated(unsafe) var updatesTask: Task<Void, Never>?

    init(client: APIClient = APIClient()) {
        self.client = client
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
            // Server verification gates everything past this point — don't
            // finish the transaction or grant local access until it
            // succeeds, so a failure leaves StoreKit free to re-surface the
            // transaction (via Transaction.updates/currentEntitlements) for
            // a retry instead of losing it.
            try await verifyWithServer(transaction)
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

    /// For a reinstall/new-device "I already subscribed" case, and as a
    /// manual self-serve resync if a subscriber's access ever looks stale
    /// (e.g. a renewal that arrived via the background `Transaction.updates`
    /// listener, which — unlike this path — doesn't itself call the server).
    /// `AppStore.sync()` forces StoreKit to re-fetch entitlements from Apple
    /// before `Transaction.currentEntitlements` is read, which is what makes
    /// this different from `refreshEntitlements()` (that one only reads
    /// whatever StoreKit already has cached locally). Returns `false` when
    /// there was genuinely nothing to restore (not an error — a free-tier
    /// user simply has no entitlement to find).
    @discardableResult
    func restorePurchases() async throws -> Bool {
        try await AppStore.sync()
        for await entitlement in Transaction.currentEntitlements {
            guard let transaction = try? checkVerified(entitlement) else { continue }
            try await verifyWithServer(transaction)
            return true
        }
        return false
    }

    /// Shared by `purchase(_:)` and `restorePurchases()` — the server's
    /// plan, not local StoreKit state, is the real gate (see the type's own
    /// doc comment), so both paths must go through this before either one
    /// is allowed to claim success.
    private func verifyWithServer(_ transaction: Transaction) async throws {
        let request = VerifyPurchaseRequest(transactionId: String(transaction.originalID))
        let response: VerifyPurchaseResponse = try await client.post(.verifyPurchase, body: request, authenticated: true)
        guard response.success, let plan = response.plan else {
            throw StoreKitManagerError.serverVerificationFailed(response.error ?? "Couldn't verify your purchase.")
        }
        verifiedPlan = plan
        purchasedProductIDs.insert(transaction.productID)
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

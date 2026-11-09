import Foundation

/// api/apple_iap_verify.php's contract — built against the agreed shape
/// before the endpoint exists server-side. `transactionId` is the StoreKit2
/// transaction's `originalID`, sent as a string.
nonisolated struct VerifyPurchaseRequest: Encodable {
    let transactionId: String

    enum CodingKeys: String, CodingKey {
        case transactionId = "transaction_id"
    }
}

/// Always decodes regardless of success/failure — same "check .success"
/// convention as the other response types in this codebase.
nonisolated struct VerifyPurchaseResponse: Decodable {
    let success: Bool
    let plan: String?
    let error: String?
}

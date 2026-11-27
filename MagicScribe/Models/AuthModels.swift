import Foundation

nonisolated struct UserAccount: Codable, Identifiable {
    let id: Int
    let email: String
    let fullName: String
    let plan: String
    let emailVerified: Bool

    enum CodingKeys: String, CodingKey {
        case id, email, plan
        case fullName = "full_name"
        case emailVerified = "email_verified"
    }
}

nonisolated struct AuthTokenResponse: Decodable {
    let token: String
    let user: UserAccount
    /// Only ever present (and meaningful) on register_token.php's response
    /// — login doesn't send a verification email, so this key is simply
    /// absent there and decodes to nil, which is fine since login never
    /// reads it.
    let emailDeliveryFailed: Bool?

    enum CodingKeys: String, CodingKey {
        case token, user
        case emailDeliveryFailed = "email_delivery_failed"
    }
}

nonisolated struct AuthTokenRequest: Encodable {
    let email: String
    let password: String
    let deviceLabel: String

    enum CodingKeys: String, CodingKey {
        case email, password
        case deviceLabel = "device_label"
    }
}

/// Same request/response contract as `AuthTokenRequest`/`AuthTokenResponse`, plus `full_name`.
/// Mirrors the `POST /api/register_token.php` backend contract.
nonisolated struct RegisterTokenRequest: Encodable {
    let email: String
    let password: String
    let fullName: String
    let deviceLabel: String

    enum CodingKeys: String, CodingKey {
        case email, password
        case fullName = "full_name"
        case deviceLabel = "device_label"
    }
}

nonisolated struct VerifyEmailCodeRequest: Encodable {
    let code: String
}

nonisolated struct DeleteAccountRequest: Encodable {
    let password: String
}

nonisolated struct SimpleSuccessResponse: Decodable {
    let success: Bool
}

/// resend_verification_code.php's specific response shape — kept separate
/// from the generic SimpleSuccessResponse, which unrelated callers
/// (DocsService.delete, FormsService.delete) also decode into.
nonisolated struct ResendVerificationResponse: Decodable {
    let success: Bool
    let emailDeliveryFailed: Bool?

    enum CodingKeys: String, CodingKey {
        case success
        case emailDeliveryFailed = "email_delivery_failed"
    }
}

/// For authenticated POST calls with no meaningful request body (e.g. resend).
nonisolated struct EmptyRequestBody: Encodable {}

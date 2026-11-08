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

nonisolated struct SimpleSuccessResponse: Decodable {
    let success: Bool
}

/// For authenticated POST calls with no meaningful request body (e.g. resend).
nonisolated struct EmptyRequestBody: Encodable {}

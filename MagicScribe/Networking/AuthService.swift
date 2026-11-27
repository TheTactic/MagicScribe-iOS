import Foundation
#if canImport(UIKit)
import UIKit
#endif

final class AuthService {
    private let client: APIClient
    private let tokenStore: KeychainTokenStore

    init(client: APIClient = APIClient(), tokenStore: KeychainTokenStore = KeychainTokenStore()) {
        self.client = client
        self.tokenStore = tokenStore
    }

    private var deviceLabel: String {
        #if canImport(UIKit)
        UIDevice.current.name
        #else
        "iOS Device"
        #endif
    }

    func login(email: String, password: String) async throws -> UserAccount {
        let request = AuthTokenRequest(email: email, password: password, deviceLabel: deviceLabel)
        let response: AuthTokenResponse = try await client.post(.authToken, body: request)
        try tokenStore.save(token: response.token)
        return response.user
    }

    /// Issues a token immediately even though the new account is unverified —
    /// confirmed product decision. See `verifyEmailCode`/`resendVerificationCode`
    /// for the in-app (not a browser link) verification flow.
    ///
    /// `emailDeliveryFailed` reflects a real SendGrid suppression check the
    /// backend runs right after sending — true means the verification
    /// email almost certainly never arrived (not just "might be in spam").
    func register(email: String, password: String, fullName: String) async throws -> (user: UserAccount, emailDeliveryFailed: Bool) {
        let request = RegisterTokenRequest(email: email, password: password, fullName: fullName, deviceLabel: deviceLabel)
        let response: AuthTokenResponse = try await client.post(.registerToken, body: request)
        try tokenStore.save(token: response.token)
        return (response.user, response.emailDeliveryFailed ?? false)
    }

    /// For an unverified account that lost its token (signed out, reinstalled)
    /// and so can't reach `verifyEmailCode`/`resendVerificationCode` (both
    /// require a bearer token). Validates credentials like `login` does, but
    /// issues a token for an unverified account instead of 403ing it, and
    /// sends a fresh code in the same call — closes the dead end where an
    /// unverified, signed-out user had no way back in.
    func recoverVerification(email: String, password: String) async throws -> UserAccount {
        let request = AuthTokenRequest(email: email, password: password, deviceLabel: deviceLabel)
        let response: AuthTokenResponse = try await client.post(.recoverVerification, body: request)
        try tokenStore.save(token: response.token)
        return response.user
    }

    func verifyEmailCode(_ code: String) async throws {
        let _: SimpleSuccessResponse = try await client.post(
            .verifyEmailCode, body: VerifyEmailCodeRequest(code: code), authenticated: true
        )
    }

    /// Returns true if the resend almost certainly failed to actually
    /// deliver (SendGrid suppression check), same signal as `register`.
    @discardableResult
    func resendVerificationCode() async throws -> Bool {
        let response: ResendVerificationResponse = try await client.post(
            .resendVerificationCode, body: EmptyRequestBody(), authenticated: true
        )
        return response.emailDeliveryFailed ?? false
    }

    /// Permanently deletes the account and all its data server-side
    /// (App Store Guideline 5.1.1(v)). Requires the password as a re-check.
    /// Clears the local token only after the server confirms — a failed
    /// call leaves the user signed in with their account intact.
    func deleteAccount(password: String) async throws {
        let _: SimpleSuccessResponse = try await client.post(
            .deleteAccount, body: DeleteAccountRequest(password: password), authenticated: true
        )
        tokenStore.deleteToken()
    }
}

import Foundation
import Security

nonisolated enum KeychainError: Error {
    case unexpectedStatus(OSStatus)
}

/// Stores only the bearer auth token — the one piece of credential-shaped state
/// in the app. Everything else (onboarding/plan flags) lives in `OnboardingState`.
nonisolated struct KeychainTokenStore {
    private let service = "tech.magicscribe.ios.authtoken"
    private let account = "authToken"

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    func save(token: String) throws {
        SecItemDelete(baseQuery as CFDictionary)
        var attributes = baseQuery
        attributes[kSecValueData as String] = Data(token.utf8)
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.unexpectedStatus(status)
        }
    }

    func loadToken() -> String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let data = result as? Data,
              let token = String(data: data, encoding: .utf8) else {
            return nil
        }
        return token
    }

    func deleteToken() {
        SecItemDelete(baseQuery as CFDictionary)
    }
}

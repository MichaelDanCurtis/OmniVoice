import Foundation
import Security

/// The signed-in user's WorkOS session. Only the user's own tokens live here — the
/// WorkOS API secret stays server-side in the Worker.
struct AuthSession: Codable, Equatable {
    var accessToken: String
    var refreshToken: String
    var userId: String
    var email: String
    /// Access-token expiry (epoch seconds), used to decide when to refresh.
    var expiresAt: Date
}

/// Persists the ``AuthSession`` in the macOS Keychain as a JSON blob. Mirrors
/// `HuggingFaceTokenStore`: update-then-add, device-only after first unlock.
struct AuthSessionStore {
    private let service = "com.omnispeak.auth"
    private let account = "session"

    func load() -> AuthSession? {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else {
            return nil
        }
        return try? JSONDecoder().decode(AuthSession.self, from: data)
    }

    func save(_ session: AuthSession) throws {
        let data = try JSONEncoder().encode(session)

        let attributes = [kSecValueData as String: data]
        let status = SecItemUpdate(baseQuery() as CFDictionary, attributes as CFDictionary)
        if status == errSecSuccess {
            return
        }

        if status == errSecItemNotFound {
            var item = baseQuery()
            item[kSecValueData as String] = data
            item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            let addStatus = SecItemAdd(item as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw KeychainError.status(addStatus)
            }
            return
        }

        throw KeychainError.status(status)
    }

    func delete() throws {
        let status = SecItemDelete(baseQuery() as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.status(status)
        }
    }

    private func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}

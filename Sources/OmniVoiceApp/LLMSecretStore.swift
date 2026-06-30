import Foundation
import Security

/// Stores LLM provider secrets (API keys, OAuth access/refresh tokens) in the Keychain —
/// one generic-password item per (provider, field) — so they never sit in the plaintext
/// preferences plist. Mirrors `HuggingFaceTokenStore`.
struct LLMSecretStore {
    enum Field: String {
        case apiKey
        case oauthAccessToken
        case oauthRefreshToken
    }

    private let service = "com.omnivoice.llm-secrets"

    func value(provider: String, field: Field) -> String? {
        load(account: account(provider, field))
    }

    /// Stores the secret, or removes it when `value` is empty. Returns true on success.
    @discardableResult
    func setValue(_ value: String, provider: String, field: Field) -> Bool {
        save(value, account: account(provider, field))
    }

    private func account(_ provider: String, _ field: Field) -> String {
        "\(provider).\(field.rawValue)"
    }

    private func load(account: String) -> String? {
        var query = baseQuery(account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess,
              let data = item as? Data,
              let secret = String(data: data, encoding: .utf8),
              !secret.isEmpty else {
            return nil
        }
        return secret
    }

    @discardableResult
    private func save(_ value: String, account: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8) else {
            return delete(account: account)
        }

        let update = [kSecValueData as String: data]
        let status = SecItemUpdate(baseQuery(account) as CFDictionary, update as CFDictionary)
        if status == errSecSuccess {
            return true
        }
        if status == errSecItemNotFound {
            var item = baseQuery(account)
            item[kSecValueData as String] = data
            item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            return SecItemAdd(item as CFDictionary, nil) == errSecSuccess
        }
        return false
    }

    @discardableResult
    private func delete(account: String) -> Bool {
        let status = SecItemDelete(baseQuery(account) as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    private func baseQuery(_ account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}

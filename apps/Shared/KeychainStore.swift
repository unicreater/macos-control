import Foundation
import Security

/// Thin wrapper over the generic-password Keychain, which is where both the agent's
/// long-term secret and every paired phone's session key live (PRD §5, Persistence).
///
/// Sandboxed apps get their own Keychain access group automatically, so no
/// entitlement beyond App Sandbox is needed for this.
struct KeychainStore {
    /// Namespaces every item this app writes, so it never collides with anything else.
    /// The two apps pass different values — they are separate keychains on separate
    /// devices and share nothing but the shape of this code.
    let service: String

    init(service: String) {
        self.service = service
    }

    func data(forAccount account: String) -> Data? {
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess else { return nil }
        return item as? Data
    }

    /// Writes, replacing any existing value for the account.
    @discardableResult
    func set(_ data: Data, forAccount account: String) -> Bool {
        let query = baseQuery(account: account)

        let update: [String: Any] = [kSecValueData as String: data]
        let updateStatus = SecItemUpdate(query as CFDictionary, update as CFDictionary)
        if updateStatus == errSecSuccess { return true }

        guard updateStatus == errSecItemNotFound else { return false }

        var insert = query
        insert[kSecValueData as String] = data
        // The agent needs its identity the moment it launches at login, which can be
        // before the user has unlocked anything beyond the login keychain.
        insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        return SecItemAdd(insert as CFDictionary, nil) == errSecSuccess
    }

    @discardableResult
    func removeItem(forAccount account: String) -> Bool {
        let status = SecItemDelete(baseQuery(account: account) as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    /// Every account this app has stored, for enumerating paired phones.
    func allAccounts() -> [String] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll,
            kSecUseDataProtectionKeychain as String: true
        ]
        query[kSecReturnData as String] = false

        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let entries = item as? [[String: Any]] else {
            return []
        }
        return entries.compactMap { $0[kSecAttrAccount as String] as? String }.sorted()
    }

    private func baseQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecUseDataProtectionKeychain as String: true
        ]
    }
}

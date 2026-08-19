import DeckKit
import Foundation
import Security

/// Where the deck layout lives: versioned JSON in Application Support (PRD §5).
///
/// Supports per-Mac deck layouts. Each Mac gets its own file keyed by device ID.
/// Uses the **legacy keychain** (no data protection) as fallback so deck layouts
/// survive ad-hoc rebuilds. The data protection keychain is tied to the app's
/// signing identity and gets wiped on rebuild — the legacy keychain persists by
/// service name alone.
struct DeckStore {
    private let directory: URL
    private static let keychainService = "com.noso.nosodeck.deck"

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        self.directory = base.appendingPathComponent("NosoDeck", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    private func fileURL(forMacID macID: String?) -> URL {
        let name = macID.map { "deck-\($0).json" } ?? "deck.json"
        return directory.appendingPathComponent(name)
    }

    private func keychainAccount(forMacID macID: String?) -> String {
        macID.map { "deck-\($0)" } ?? "deck"
    }

    // MARK: - Legacy keychain (survives rebuilds)

    private func keychainQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.keychainService,
            kSecAttrAccount as String: account
            // No kSecUseDataProtectionKeychain — uses legacy keychain
        ]
    }

    private func keychainLoad(account: String) -> Data? {
        var query = keychainQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess else { return nil }
        return item as? Data
    }

    private func keychainSave(account: String, data: Data) {
        let query = keychainQuery(account: account)
        let update: [String: Any] = [kSecValueData as String: data]
        let status = SecItemUpdate(query as CFDictionary, update as CFDictionary)
        if status == errSecItemNotFound {
            var insert = query
            insert[kSecValueData as String] = data
            insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            SecItemAdd(insert as CFDictionary, nil)
        }
    }

    // MARK: - Public API

    func load(macID: String? = nil) -> Deck? {
        // Try filesystem first (fastest, works within same install)
        let url = fileURL(forMacID: macID)
        let fallbackURL = directory.appendingPathComponent("deck.json")
        let targetURL = FileManager.default.fileExists(atPath: url.path) ? url : fallbackURL

        if let data = try? Data(contentsOf: targetURL),
           let document = try? JSONDecoder().decode(DeckDocument.self, from: data),
           !document.isFromFutureSchema {
            return document.deck
        }

        // Fall back to legacy keychain (survives rebuilds)
        let account = keychainAccount(forMacID: macID)
        if let data = keychainLoad(account: account),
           let document = try? JSONDecoder().decode(DeckDocument.self, from: data),
           !document.isFromFutureSchema {
            return document.deck
        }

        // Try the generic key if per-Mac wasn't found
        if macID != nil, let data = keychainLoad(account: "deck"),
           let document = try? JSONDecoder().decode(DeckDocument.self, from: data),
           !document.isFromFutureSchema {
            return document.deck
        }

        return nil
    }

    func save(_ deck: Deck, macID: String? = nil) {
        guard let data = try? JSONEncoder().encode(DeckDocument(deck: deck)) else { return }
        try? data.write(to: fileURL(forMacID: macID), options: .atomic)
        keychainSave(account: keychainAccount(forMacID: macID), data: data)
    }

    /// List all Mac IDs that have saved deck layouts.
    func savedMacIDs() -> [String] {
        guard let files = try? FileManager.default.contentsOfDirectory(atPath: directory.path) else { return [] }
        return files.compactMap { file in
            guard file.hasPrefix("deck-"), file.hasSuffix(".json") else { return nil }
            return String(file.dropFirst(5).dropLast(5))
        }
    }
}

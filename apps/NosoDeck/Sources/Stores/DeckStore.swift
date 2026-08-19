import DeckKit
import Foundation

/// Where the deck layout lives: versioned JSON in Application Support (PRD §5).
///
/// Supports per-Mac deck layouts. Each Mac gets its own file keyed by device ID.
/// Uses Keychain as fallback so deck layouts survive ad-hoc rebuilds — filesystem
/// and UserDefaults both get wiped when the app container changes, but Keychain
/// persists (same reason PhoneIdentityStore uses Keychain).
struct DeckStore {
    private let directory: URL
    private let keychain: KeychainStore

    private func keychainAccount(forMacID macID: String?) -> String {
        macID.map { "deck.\($0)" } ?? "deck"
    }

    init(keychain: KeychainStore = KeychainStore(service: "com.noso.nosodeck.ios")) {
        self.keychain = keychain
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        self.directory = base.appendingPathComponent("NosoDeck", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    private func fileURL(forMacID macID: String?) -> URL {
        let name = macID.map { "deck-\($0).json" } ?? "deck.json"
        return directory.appendingPathComponent(name)
    }

    func load(macID: String? = nil) -> Deck? {
        // Try filesystem first (fastest)
        let url = fileURL(forMacID: macID)
        let fallbackURL = directory.appendingPathComponent("deck.json")
        let targetURL = FileManager.default.fileExists(atPath: url.path) ? url : fallbackURL

        if let data = try? Data(contentsOf: targetURL),
           let document = try? JSONDecoder().decode(DeckDocument.self, from: data),
           !document.isFromFutureSchema {
            return document.deck
        }

        // Fall back to Keychain (survives rebuilds)
        let account = keychainAccount(forMacID: macID)
        if let data = keychain.data(forAccount: account),
           let document = try? JSONDecoder().decode(DeckDocument.self, from: data),
           !document.isFromFutureSchema {
            return document.deck
        }

        // Try the generic key if per-Mac wasn't found
        if macID != nil, let data = keychain.data(forAccount: "deck"),
           let document = try? JSONDecoder().decode(DeckDocument.self, from: data),
           !document.isFromFutureSchema {
            return document.deck
        }

        return nil
    }

    func save(_ deck: Deck, macID: String? = nil) {
        guard let data = try? JSONEncoder().encode(DeckDocument(deck: deck)) else { return }
        // Write to both filesystem and Keychain
        try? data.write(to: fileURL(forMacID: macID), options: .atomic)
        keychain.set(data, forAccount: keychainAccount(forMacID: macID))
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

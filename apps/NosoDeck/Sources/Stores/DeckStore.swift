import DeckKit
import Foundation

/// Where the deck layout lives: versioned JSON in Application Support (PRD §5).
///
/// Supports per-Mac deck layouts. Each Mac gets its own file keyed by device ID.
struct DeckStore {
    private let directory: URL

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

    func load(macID: String? = nil) -> Deck? {
        let url = fileURL(forMacID: macID)
        // Fall back to the shared deck.json if per-Mac file doesn't exist
        let fallbackURL = directory.appendingPathComponent("deck.json")
        let targetURL = FileManager.default.fileExists(atPath: url.path) ? url : fallbackURL

        guard let data = try? Data(contentsOf: targetURL),
              let document = try? JSONDecoder().decode(DeckDocument.self, from: data) else {
            return nil
        }
        guard !document.isFromFutureSchema else { return nil }
        return document.deck
    }

    func save(_ deck: Deck, macID: String? = nil) {
        guard let data = try? JSONEncoder().encode(DeckDocument(deck: deck)) else { return }
        try? data.write(to: fileURL(forMacID: macID), options: .atomic)
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

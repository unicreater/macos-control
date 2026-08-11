import DeckKit
import Foundation

/// Where the deck layout lives: versioned JSON in Application Support (PRD §5).
///
/// Saving is best-effort and never throws into the UI. A layout that fails to write is
/// worth a log line, not an alert in the middle of dragging a tile — the next edit will
/// try again.
struct DeckStore {
    private let fileURL: URL

    init(fileName: String = "deck.json") {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let directory = base.appendingPathComponent("NosoDeck", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        self.fileURL = directory.appendingPathComponent(fileName)
    }

    /// Returns nil when nothing has been saved yet, which is what tells the app to build
    /// a starter deck from the Mac's suggestions (FR-12).
    func load() -> Deck? {
        guard let data = try? Data(contentsOf: fileURL),
              let document = try? JSONDecoder().decode(DeckDocument.self, from: data) else {
            return nil
        }
        // A file from a newer build is left alone rather than downgraded — better to
        // show a starter deck than to quietly discard a layout this version can't read.
        guard !document.isFromFutureSchema else { return nil }
        return document.deck
    }

    func save(_ deck: Deck) {
        guard let data = try? JSONEncoder().encode(DeckDocument(deck: deck)) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}

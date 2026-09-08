import DeckKit
import Foundation

/// A single clipboard entry received from the Mac.
struct ClipboardItem: Codable, Identifiable, Hashable {
    let id: UUID
    let text: String
    let sourceApp: String?
    let timestamp: Date

    init(from update: ClipboardUpdate) {
        self.id = UUID()
        self.text = update.text
        self.sourceApp = update.sourceApp
        self.timestamp = update.timestamp
    }
}

/// Persists clipboard history to UserDefaults (last 30 items).
enum ClipboardStore {
    private static let key = "com.noso.nosodeck.clipboardHistory"
    private static let maxItems = 30

    static func load() -> [ClipboardItem] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let items = try? JSONDecoder().decode([ClipboardItem].self, from: data) else {
            return []
        }
        return items
    }

    static func save(_ items: [ClipboardItem]) {
        let clamped = Array(items.prefix(maxItems))
        guard let data = try? JSONEncoder().encode(clamped) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}

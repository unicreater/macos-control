import Foundation

/// A slot address on the deck — which page, which position within it.
public struct DeckSlot: Hashable, Sendable {
    public var pageIndex: Int
    public var slotIndex: Int

    public init(pageIndex: Int, slotIndex: Int) {
        self.pageIndex = pageIndex
        self.slotIndex = slotIndex
    }

    /// One-based, for the "Page 1 · slot 8 of 8" line in the add-tile flow (design S6).
    public var humanReadable: String {
        "Page \(pageIndex + 1) · slot \(slotIndex + 1) of \(Page.maxTiles)"
    }
}

/// The user's whole deck: an ordered list of pages.
///
/// `currentPage` and `editing` from the design's state model are deliberately *not*
/// here — they are view state owned by each app, not something worth persisting or
/// sending over the wire. What is persisted is the layout itself.
public struct Deck: Codable, Hashable, Sendable {
    /// The premium ceiling, and therefore the highest a deck can ever legitimately go.
    /// Per-tier limits live on `Entitlement`.
    public static let maxPages = 8

    public private(set) var pages: [Page]

    /// A deck always has at least one page and never more than `maxPages`; both ends
    /// are clamped here so decoding can't produce an unrenderable deck.
    public init(pages: [Page] = [Page()]) {
        let clamped = Array(pages.prefix(Deck.maxPages))
        self.pages = clamped.isEmpty ? [Page()] : clamped
    }

    public var pageCount: Int { pages.count }
    public var tileCount: Int { pages.reduce(0) { $0 + $1.tiles.count } }
    public var isEmpty: Bool { tileCount == 0 }

    // MARK: - Pages

    /// Free decks stop at two pages, premium at eight (D16, FR-17).
    public func canAddPage(for entitlement: Entitlement) -> Bool {
        pages.count < min(entitlement.maxPages, Deck.maxPages)
    }

    /// Adds an empty page, returning false when the tier's limit is reached — that
    /// false is what opens the paywall rather than a dead tap.
    @discardableResult
    public mutating func addPage(for entitlement: Entitlement) -> Bool {
        guard canAddPage(for: entitlement) else { return false }
        pages.append(Page())
        return true
    }

    /// Removes a page. The last remaining page is never removed — a deck with no pages
    /// has nothing to render. Deleting is a destructive confirm in the UI (design S5).
    @discardableResult
    public mutating func removePage(at index: Int) -> Bool {
        guard pages.count > 1, pages.indices.contains(index) else { return false }
        pages.remove(at: index)
        return true
    }

    /// Pages a lapsed premium user can still see but no longer add to. Existing pages
    /// are never taken away — nothing already free is ever locked (FR-17).
    public func lockedPageIndices(for entitlement: Entitlement) -> Range<Int> {
        let allowed = min(entitlement.maxPages, pages.count)
        return allowed..<pages.count
    }

    // MARK: - Tiles

    /// The slot a newly added tile would land in, scanning pages in order.
    public var nextFreeSlot: DeckSlot? {
        for (pageIndex, page) in pages.enumerated() {
            if let slot = page.nextFreeSlot {
                return DeckSlot(pageIndex: pageIndex, slotIndex: slot)
            }
        }
        return nil
    }

    @discardableResult
    public mutating func add(_ tile: Tile, toPageAt index: Int) -> Bool {
        guard pages.indices.contains(index) else { return false }
        return pages[index].append(tile)
    }

    /// Adds to the first page with room. Returns the slot used, or nil when the whole
    /// deck is full.
    @discardableResult
    public mutating func add(_ tile: Tile) -> DeckSlot? {
        guard let slot = nextFreeSlot else { return nil }
        pages[slot.pageIndex].append(tile)
        return slot
    }

    @discardableResult
    public mutating func removeTile(id: UUID) -> Tile? {
        for index in pages.indices {
            if let removed = pages[index].remove(tileID: id) { return removed }
        }
        return nil
    }

    public func slot(ofTileID id: UUID) -> DeckSlot? {
        for (pageIndex, page) in pages.enumerated() {
            if let slotIndex = page.tiles.firstIndex(where: { $0.id == id }) {
                return DeckSlot(pageIndex: pageIndex, slotIndex: slotIndex)
            }
        }
        return nil
    }

    /// Drag-reorder, within a page or across pages (FR-6). Fails without mutating when
    /// the tile is unknown or the destination page is full.
    @discardableResult
    public mutating func moveTile(id: UUID, to destination: DeckSlot) -> Bool {
        guard let origin = slot(ofTileID: id) else { return false }
        guard pages.indices.contains(destination.pageIndex) else { return false }

        if origin.pageIndex == destination.pageIndex {
            pages[origin.pageIndex].move(from: origin.slotIndex, to: destination.slotIndex)
            return true
        }

        guard !pages[destination.pageIndex].isFull else { return false }
        guard let tile = pages[origin.pageIndex].remove(tileID: id) else { return false }
        pages[destination.pageIndex].insert(tile, at: destination.slotIndex)
        return true
    }

    public func tile(withID id: UUID) -> Tile? {
        for page in pages {
            if let tile = page.tiles.first(where: { $0.id == id }) { return tile }
        }
        return nil
    }

    /// Bundle IDs of every app tile on the deck — what the phone subscribes to state
    /// updates for.
    public var appBundleIDs: Set<String> {
        var result: Set<String> = []
        for page in pages {
            for tile in page.tiles {
                if case .app(let bundleID) = tile.target { result.insert(bundleID) }
            }
        }
        return result
    }
}

extension Deck {
    private enum CodingKeys: String, CodingKey {
        case pages
    }

    /// Hand-written so decoding routes through `init(pages:)` and inherits its clamping.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(pages: try container.decode([Page].self, forKey: .pages))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(pages, forKey: .pages)
    }
}

/// The persisted form of a deck: versioned so a later schema change can migrate rather
/// than discard someone's layout (PRD §5, Persistence).
public struct DeckDocument: Codable, Hashable, Sendable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var deck: Deck

    public init(deck: Deck, schemaVersion: Int = DeckDocument.currentSchemaVersion) {
        self.schemaVersion = schemaVersion
        self.deck = deck
    }

    /// True when the file was written by a newer build than this one. The app should
    /// refuse to overwrite it rather than silently downgrade the user's layout.
    public var isFromFutureSchema: Bool { schemaVersion > DeckDocument.currentSchemaVersion }
}

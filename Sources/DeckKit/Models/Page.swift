import Foundation

/// One page of the deck: at most eight tiles, always.
///
/// The 4×2 grid is a hard product constraint (D15, FR-6) — larger devices get larger
/// tiles, never more of them. That cap is enforced here rather than in the UI so no
/// call site, and no decoded file from a future or corrupted build, can exceed it.
public struct Page: Identifiable, Codable, Hashable, Sendable {
    /// 4 columns × 2 rows. Not a default, a maximum.
    public static let maxTiles = 8

    public var id: UUID
    /// Ordered left-to-right, top-to-bottom. Never longer than `maxTiles`.
    public private(set) var tiles: [Tile]

    /// Tiles beyond `maxTiles` are dropped rather than rejected: decoding routes
    /// through here too, and a deck file that somehow carries nine tiles should still
    /// open with eight instead of failing to load.
    public init(id: UUID = UUID(), tiles: [Tile] = []) {
        self.id = id
        self.tiles = Array(tiles.prefix(Page.maxTiles))
    }

    public var isFull: Bool { tiles.count >= Page.maxTiles }
    public var isEmpty: Bool { tiles.isEmpty }
    /// Index of the first free slot, or nil when the page is full. Drives the add-tile
    /// flow's "Page 1 · slot 8 of 8" line (design S6).
    public var nextFreeSlot: Int? { isFull ? nil : tiles.count }

    /// Appends a tile, returning false when the page is already full.
    @discardableResult
    public mutating func append(_ tile: Tile) -> Bool {
        guard !isFull else { return false }
        tiles.append(tile)
        return true
    }

    /// Inserts at a slot, clamping into range. Returns false when the page is full.
    @discardableResult
    public mutating func insert(_ tile: Tile, at slot: Int) -> Bool {
        guard !isFull else { return false }
        tiles.insert(tile, at: min(max(slot, 0), tiles.count))
        return true
    }

    /// Updates a tile's label and emoji in place.
    public mutating func updateTile(id: UUID, label: String, emoji: String?) {
        guard let index = tiles.firstIndex(where: { $0.id == id }) else { return }
        tiles[index].label = label
        tiles[index].emoji = emoji
    }

    @discardableResult
    public mutating func remove(tileID: UUID) -> Tile? {
        guard let index = tiles.firstIndex(where: { $0.id == tileID }) else { return nil }
        return tiles.remove(at: index)
    }

    /// Drag-reorder within the page. Out-of-range indices are ignored.
    public mutating func move(from source: Int, to destination: Int) {
        guard tiles.indices.contains(source) else { return }
        let clamped = min(max(destination, 0), tiles.count - 1)
        guard clamped != source else { return }
        let tile = tiles.remove(at: source)
        tiles.insert(tile, at: clamped)
    }

    public func contains(tileID: UUID) -> Bool {
        tiles.contains { $0.id == tileID }
    }
}

extension Page {
    private enum CodingKeys: String, CodingKey {
        case id
        case tiles
    }

    /// Written by hand so decoding goes through `init(id:tiles:)`. The synthesized
    /// version would assign `tiles` directly and let an over-long page slip past the
    /// eight-tile cap.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decode(UUID.self, forKey: .id),
            tiles: try container.decode([Tile].self, forKey: .tiles)
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(tiles, forKey: .tiles)
    }
}

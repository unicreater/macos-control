import Foundation

/// One keycap on the deck.
///
/// The visual states a tile can take (idle / running / frontmost / pressed /
/// disconnected / edit / dragging) are *derived* from `MacState` and the connection —
/// they are never stored here, so a tile means the same thing on both platforms.
public struct Tile: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var target: TileTarget
    /// Rendered in the keycap legend: mono 12/+1, uppercased, one line, truncating.
    public var label: String
    /// The user's chosen emoji, replacing the icon on shortcut and website tiles.
    /// App tiles leave this nil and render the real icon served by the Mac (FR-7).
    public var emoji: String?

    public init(id: UUID = UUID(), target: TileTarget, label: String, emoji: String? = nil) {
        self.id = id
        self.target = target
        self.label = label
        self.emoji = emoji
    }

    public var kind: TileKind { target.kind }

    /// Convenience for the common case of an app tile built from a catalog entry.
    public static func app(_ entry: AppCatalogEntry, id: UUID = UUID()) -> Tile {
        Tile(id: id, target: .app(bundleID: entry.bundleID), label: entry.name)
    }
}

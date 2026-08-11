import Foundation

/// What the Mac is doing right now, pushed by the agent on every change and on
/// subscribe (PRD §5, `stateEvent`). This is what makes the deck live rather than a
/// launcher: it drives each keycap's mint LED and the frontmost ring (FR-10).
public struct MacState: Codable, Hashable, Sendable {
    /// FR-16: the recents column shows four cells.
    public static let maxVisibleRecents = 4

    /// Bundle IDs of every running app.
    public var running: Set<String>
    /// Bundle ID of the frontmost app, if any.
    public var frontmost: String?
    /// Recently activated apps, most recent first, already deduplicated and with the
    /// agent itself excluded (FR-16).
    public var recents: [String]

    public init(running: Set<String> = [], frontmost: String? = nil, recents: [String] = []) {
        self.running = running
        self.frontmost = frontmost
        self.recents = recents
    }

    /// The state to show before the first `stateEvent` arrives, and after a disconnect.
    public static let unknown = MacState()

    public func isRunning(_ bundleID: String) -> Bool { running.contains(bundleID) }
    public func isFrontmost(_ bundleID: String) -> Bool { frontmost == bundleID }

    /// The recents actually rendered in the 92pt column (design S9).
    public var visibleRecents: [String] { Array(recents.prefix(MacState.maxVisibleRecents)) }

    /// The keycap state for a tile, given this Mac state. Frontmost wins over running,
    /// per the keycap state table.
    public func tileState(for target: TileTarget) -> TileActivityState {
        guard case .app(let bundleID) = target else { return .idle }
        if isFrontmost(bundleID) { return .frontmost }
        if isRunning(bundleID) { return .running }
        return .idle
    }

    /// Folds a newly activated app into the recents list: most recent first,
    /// deduplicated, capped at a sensible history depth.
    public mutating func recordActivation(of bundleID: String, historyDepth: Int = 8) {
        recents.removeAll { $0 == bundleID }
        recents.insert(bundleID, at: 0)
        if recents.count > historyDepth {
            recents.removeLast(recents.count - historyDepth)
        }
    }
}

/// The activity portion of the keycap state table. The remaining states (pressed,
/// disconnected, edit, dragging, empty) come from interaction and connection, not from
/// the Mac, so they are the UI's business rather than this model's.
public enum TileActivityState: String, Hashable, Sendable, CaseIterable {
    case idle
    case running
    case frontmost
}

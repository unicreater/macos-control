import Foundation

/// The `connection` slice of the state model. Drives the top bar, the deck's opacity,
/// and whether tiles accept taps at all (design S4).
public enum ConnectionState: Hashable, Sendable {
    /// No link, and none being attempted. The red banner state — "Disconnected — tiles
    /// are inactive until your Mac is back."
    case disconnected
    /// First connection to this Mac in this session. Visually the same treatment as
    /// `reconnecting`; separate because "Reconnecting…" is the wrong words for a link
    /// that has never been up.
    case connecting
    /// Live. `latencyMs` is what the top bar's "· 12MS" shows.
    case connected(latencyMs: Int)
    /// The link dropped and is being retried. The deck stays on screen and desaturates
    /// behind an amber banner — it is never blanked (design S4).
    case reconnecting

    /// True only when actions will actually reach the Mac.
    public var isLive: Bool {
        if case .connected = self { return true }
        return false
    }

    /// True while the deck should render but refuse taps.
    public var isInert: Bool { !isLive }

    /// True while a connection attempt is in flight — what a spinner would wait on,
    /// after the 300ms delay the motion spec requires.
    public var isEstablishing: Bool {
        switch self {
        case .connecting, .reconnecting: return true
        case .connected, .disconnected: return false
        }
    }

    public var latencyMs: Int? {
        if case .connected(let latencyMs) = self { return latencyMs }
        return nil
    }
}

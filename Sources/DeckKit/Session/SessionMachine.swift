import Foundation

public enum SessionEvent: Hashable, Sendable {
    /// A connection attempt has been started.
    case connectAttemptStarted
    /// `hello`/`helloAck` completed — the link is usable.
    case handshakeCompleted
    /// A keepalive ping went out on the wire.
    case pingSent
    /// A pong came back, with the round trip it measured.
    case pongReceived(latencyMs: Int)
    /// The socket failed or the peer went away, while the network itself is still up.
    case transportFailed
    /// The device lost the network entirely — Wi-Fi off, out of range.
    case reachabilityLost
    /// The network came back. Retrying is now worth doing.
    case reachabilityRestored
    /// The user unpaired, backgrounded the app, or otherwise asked to stop.
    case disconnectRequested
}

/// Owns the `connection` state and the keepalive bookkeeping behind it (FR-4).
///
/// Like `PairingMachine`, this is a reducer with no clock and no I/O: the caller runs
/// the 10-second timer and the socket, and reports what happened. That is what lets the
/// "two missed pongs means reconnect" rule be tested in microseconds instead of
/// half a minute.
public struct SessionMachine: Hashable, Sendable {
    /// PRD §5: a keepalive every ten seconds.
    public static let keepaliveInterval: TimeInterval = 10
    /// PRD §5: two misses and the link is presumed dead.
    public static let missedPongLimit = 2

    public private(set) var state: ConnectionState
    /// Pings written since the last pong. Reaching `missedPongLimit` trips reconnect.
    public private(set) var pingsOutstanding: Int
    /// Consecutive failed attempts, for `ReconnectPolicy.delay(forAttempt:)`.
    public private(set) var reconnectAttempt: Int
    /// Whether this session has ever been live, which is the difference between
    /// "connecting" and "reconnecting".
    public private(set) var hasConnected: Bool

    public init(state: ConnectionState = .disconnected) {
        self.state = state
        self.pingsOutstanding = 0
        self.reconnectAttempt = 0
        self.hasConnected = state.isLive
    }

    public mutating func handle(_ event: SessionEvent) {
        switch event {
        case .connectAttemptStarted:
            pingsOutstanding = 0
            let next: ConnectionState = hasConnected ? .reconnecting : .connecting
            if state != next { state = next }

        case .handshakeCompleted:
            hasConnected = true
            pingsOutstanding = 0
            reconnectAttempt = 0
            // Only mark connected once a pong proves the link is stable. During
            // reconnect the banner stays on "Reconnecting" until then, avoiding the
            // blink between connected/reconnecting on flaky links.
            if !state.isLive {
                state = .connected(latencyMs: 0)
            }

        case .pingSent:
            guard state.isLive else { break }
            pingsOutstanding += 1
            if pingsOutstanding >= SessionMachine.missedPongLimit {
                reconnectAttempt = 0
                state = .reconnecting
            }

        case .pongReceived(let latencyMs):
            pingsOutstanding = 0
            hasConnected = true
            reconnectAttempt = 0
            state = .connected(latencyMs: max(latencyMs, 0))

        case .transportFailed:
            pingsOutstanding = 0
            if hasConnected {
                reconnectAttempt += 1
                if state != .reconnecting { state = .reconnecting }
            } else {
                reconnectAttempt += 1
                state = .disconnected
            }

        case .reachabilityLost:
            // No network at all: retrying is pointless, and the design calls for the
            // red banner rather than the amber one.
            pingsOutstanding = 0
            state = .disconnected

        case .reachabilityRestored:
            guard !state.isLive else { break }
            reconnectAttempt = 0
            state = hasConnected ? .reconnecting : .connecting

        case .disconnectRequested:
            pingsOutstanding = 0
            reconnectAttempt = 0
            state = .disconnected
        }
    }

    /// Delay before the next attempt, given a policy.
    public func nextRetryDelay(
        policy: ReconnectPolicy = .default,
        randomUnit: Double = Double.random(in: 0...1)
    ) -> TimeInterval {
        policy.delay(forAttempt: reconnectAttempt, randomUnit: randomUnit)
    }

    /// Whether a tile tap should be sent. Mirrors the deck's interactivity exactly, so
    /// the UI and the transport can never disagree about whether the deck is live.
    public var acceptsActions: Bool { state.isLive }
}

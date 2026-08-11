import Foundation

/// The `pairing` slice of the state model, verbatim from the design handoff.
public enum PairingState: Hashable, Sendable {
    case unpaired
    case discovering
    /// The PIN screen. Carries the device so the screen can name it.
    case awaitingPIN(DeviceIdentity)
    /// Wrong PIN. Carries the device too, because the flow never resets — the user
    /// stays on the PIN screen with a textual counter (design S3).
    case pairingError(DeviceIdentity, attemptsLeft: Int)
    /// Known device ID presenting an unfamiliar key. Requires a deliberate re-pair.
    case identityChanged(DeviceIdentity)
    case paired(DeviceIdentity)
}

public enum PairingEvent: Hashable, Sendable {
    /// Opened the device list and started browsing for `_nosodeck._tcp`.
    case beginDiscovery
    /// The user tapped a Mac in the list.
    case deviceSelected(DeviceIdentity)
    /// The agent accepted the PIN and returned its identity.
    case pairAccepted(DeviceIdentity)
    /// The agent rejected the PIN.
    case pairRejected
    /// The user confirmed the destructive re-pair after an identity change.
    case rePairConfirmed
    /// Backed out of the PIN screen or the identity-changed card.
    case cancelled
    /// The user unpaired from Settings, or the Mac unpaired from its menu (FR-5).
    case unpaired(deviceID: String)
}

/// Drives pairing from `unpaired` to `paired` and owns the trust store while doing it.
///
/// Written as a reducer — one `handle(_:)` entry point, no I/O, no clock — so the whole
/// of FR-2 and FR-3 can be tested as a table of transitions rather than by pairing two
/// physical devices over and over.
public struct PairingMachine: Hashable, Sendable {
    /// Three tries, which is what makes the design's "Wrong PIN — 2 tries left" the
    /// message after the first failure.
    public static let maxAttempts = 3

    public private(set) var state: PairingState
    public private(set) var trust: TrustStore

    public init(trust: TrustStore = TrustStore(), state: PairingState = .unpaired) {
        self.trust = trust
        self.state = state
    }

    public mutating func handle(_ event: PairingEvent) {
        switch event {
        case .beginDiscovery:
            state = .discovering

        case .deviceSelected(let identity):
            switch trust.evaluate(identity) {
            case .trusted:
                // Already paired: straight to the deck, no PIN prompt, even across a
                // force-quit of both apps (FR-2).
                state = .paired(identity)
            case .unknown:
                state = .awaitingPIN(identity)
            case .identityChanged:
                state = .identityChanged(identity)
            }

        case .pairAccepted(let identity):
            // Trust is stored only here — never on the rejection path.
            trust.pin(identity)
            state = .paired(identity)

        case .pairRejected:
            switch state {
            case .awaitingPIN(let identity):
                state = .pairingError(identity, attemptsLeft: PairingMachine.maxAttempts - 1)
            case .pairingError(let identity, let attemptsLeft):
                let remaining = attemptsLeft - 1
                // Out of tries: back to the device list rather than a dead end. The
                // Mac rotates its PIN, and the user picks the Mac again to retry.
                state = remaining > 0 ? .pairingError(identity, attemptsLeft: remaining) : .discovering
            default:
                break
            }

        case .rePairConfirmed:
            guard case .identityChanged(let identity) = state else { break }
            trust.forget(deviceID: identity.deviceID)
            state = .awaitingPIN(identity)

        case .cancelled:
            switch state {
            case .awaitingPIN, .pairingError, .identityChanged:
                state = .discovering
            default:
                break
            }

        case .unpaired(let deviceID):
            trust.forget(deviceID: deviceID)
            if case .paired(let identity) = state, identity.deviceID == deviceID {
                state = .unpaired
            }
        }
    }

    // MARK: - Derived, for the UI

    /// The device currently in play, whatever stage the flow is at.
    public var device: DeviceIdentity? {
        switch state {
        case .unpaired, .discovering:
            return nil
        case .awaitingPIN(let identity),
             .pairingError(let identity, _),
             .identityChanged(let identity),
             .paired(let identity):
            return identity
        }
    }

    /// True while the six PIN cells should accept input.
    public var isAcceptingPIN: Bool {
        switch state {
        case .awaitingPIN, .pairingError: return true
        default: return false
        }
    }

    /// Tries left, for the textual counter under the PIN cells. Nil when not in an
    /// error state — the screen shows no counter until something has gone wrong.
    public var attemptsLeft: Int? {
        guard case .pairingError(_, let attemptsLeft) = state else { return nil }
        return attemptsLeft
    }

    public var isPaired: Bool {
        if case .paired = state { return true }
        return false
    }
}

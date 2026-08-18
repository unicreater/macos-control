import DeckKit
import Foundation
import Network

/// The phone's side of a session: one connection, the handshake, and the keepalive.
///
/// It reports events rather than deciding anything — `SessionMachine` and
/// `PairingMachine` in DeckKit own the state, and they were tested off-device precisely
/// so this layer could stay thin.
@MainActor
final class DeckClient {
    /// Which key opens the connection.
    enum Credential {
        /// First contact: a key derived from the PIN the user just typed.
        case pairing(PairingPIN)
        /// A Mac we already trust, using the secret it minted at pairing.
        case trusted(Data)
    }

    private let identityStore: PhoneIdentityStore
    private var connection: PeerConnection?
    private var keepaliveTask: Task<Void, Never>?
    private var pingSentAt: Date?
    private var pendingPairRequestID: UUID?
    private var hasReachedReady = false
    private var connectedSince: Date?

    /// The Mac this client is currently talking to, if any.
    private(set) var mac: DiscoveredMac?

    var onSessionEvent: ((SessionEvent) -> Void)?
    var onHelloAck: ((HelloAck) -> Void)?
    var onPairResult: ((PairResult) -> Void)?
    var onStateEvent: ((MacState) -> Void)?
    var onActionResult: ((ActionResult) -> Void)?
    var onCatalog: ((Catalog) -> Void)?
    var onIcon: ((IconResponse) -> Void)?
    var onShortcuts: (([String], [ShortcutInfo]) -> Void)?
    var onBrowserTabs: (([BrowserTab]) -> Void)?

    init(identityStore: PhoneIdentityStore) {
        self.identityStore = identityStore
    }

    var isConnected: Bool { connection != nil }

    // MARK: - Lifecycle

    func connect(to mac: DiscoveredMac, credential: Credential) {
        disconnect()
        self.mac = mac

        let key: PresharedKey
        switch credential {
        case .pairing:
            // Connect with the open pairing key — no PIN needed for TLS.
            // The PIN is verified at the application layer (pairRequest).
            key = PresharedKey(
                identity: DeckService.pairingKeyIdentity,
                key: DeckTransport.openPairingKey(deviceID: mac.deviceID)
            )
        case .trusted(let secret):
            // The identity is this phone's ID, which is how the agent picks the right
            // key out of the set it registered.
            key = PresharedKey(identity: identityStore.deviceID, key: secret)
        }

        let connection = PeerConnection(
            endpoint: mac.endpoint,
            parameters: DeckTransport.parameters(key: key)
        )
        connection.onStateChange = { [weak self] state in
            self?.handle(state)
        }
        connection.onEnvelope = { [weak self] envelope in
            self?.handle(envelope)
        }
        // Errors that matter also change the connection's state; anything else is a
        // single bad frame, which is not worth tearing a session down for.
        self.connection = connection
        onSessionEvent?(.connectAttemptStarted)
        connection.start()
    }

    func disconnect() {
        keepaliveTask?.cancel()
        keepaliveTask = nil
        pingSentAt = nil
        pendingPairRequestID = nil
        hasReachedReady = false
        connectedSince = nil
        connection?.cancel()
        connection = nil
        mac = nil
    }

    /// Sends the PIN over the already-authenticated pairing channel.
    ///
    /// Redundant on the face of it — a wrong PIN could not have opened this connection —
    /// but it is what carries the agent's identity and session secret back, and it keeps
    /// the app-level check in place if the transport is ever loosened.
    func sendPairRequest(pin: PairingPIN) {
        let envelope = Envelope(message: .pairRequest(PairRequest(pin: pin)))
        pendingPairRequestID = envelope.id
        connection?.send(envelope)
    }

    @discardableResult
    func send(_ message: Message) -> UUID? {
        guard let connection else {
            return nil
        }
        let envelope = Envelope(message: message)
        connection.send(envelope)
        return envelope.id
    }

    // MARK: - Events

    private func handle(_ state: NWConnection.State) {
        switch state {
        case .ready:
            hasReachedReady = true
            connectedSince = Date()
            connection?.send(Envelope(message: .hello(identityStore.hello())))

        case .waiting:
            if hasReachedReady {
                // Connection was working — let Network.framework recover the path
                // rather than tearing down and cycling.
                break
            }
            teardownAndReportFailure()

        case .failed, .cancelled:
            teardownAndReportFailure()

        default:
            break
        }
    }

    /// A deliberate `disconnect()` never lands here: `PeerConnection.cancel()` clears
    /// its state handler first, so only failures we did not ask for are reported.
    private func teardownAndReportFailure() {
        stopKeepalive()
        connection?.cancel()
        connection = nil
        onSessionEvent?(.transportFailed)
    }

    private func handle(_ envelope: Envelope) {
        switch envelope.message {
        case .helloAck(let ack):
            onSessionEvent?(.handshakeCompleted)
            startKeepalive()
            onHelloAck?(ack)

        case .pairResult(let result):
            onPairResult?(result)

        case .pong:
            let latency = pingSentAt.map { Int(Date().timeIntervalSince($0) * 1000) } ?? 0
            pingSentAt = nil
            onSessionEvent?(.pongReceived(latencyMs: latency))

        case .ping:
            connection?.send(envelope.reply(.pong))

        case .stateEvent(let macState):
            onStateEvent?(macState)

        case .actionResult(let result):
            onActionResult?(result)

        case .catalog(let catalog):
            onCatalog?(catalog)

        case .icon(let icon):
            onIcon?(icon)

        case .shortcuts(let list):
            onShortcuts?(list.names, list.shortcuts)

        case .browserTabs(let list):
            onBrowserTabs?(list.tabs)

        default:
            break
        }
    }

    // MARK: - Keepalive

    private func startKeepalive() {
        stopKeepalive()
        keepaliveTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(SessionMachine.keepaliveInterval))
                guard !Task.isCancelled, let self, self.connection != nil else { return }
                self.pingSentAt = Date()
                self.connection?.send(Envelope(message: .ping))
                // Reported whether or not a pong ever comes back; two unanswered pings
                // are what trip the reconnect (PRD §5).
                self.onSessionEvent?(.pingSent)
            }
        }
    }

    private func stopKeepalive() {
        keepaliveTask?.cancel()
        keepaliveTask = nil
    }
}

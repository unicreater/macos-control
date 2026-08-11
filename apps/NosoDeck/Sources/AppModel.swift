import DeckKit
import Foundation
import Observation
import SwiftUI

/// The coordinator: routing, discovery, pairing, and the session.
///
/// The decisions all live in DeckKit's two state machines. This owns the I/O around
/// them and the small amount of view state the screens need — which is why it reads as
/// wiring rather than logic.
@MainActor
@Observable
final class AppModel {
    enum Route: Hashable {
        case onboarding
        case discovery
        case pin
        case deck
    }

    // MARK: - Published state

    private(set) var route: Route
    private(set) var pairing: PairingMachine
    private(set) var session = SessionMachine()
    private(set) var discovered: [DiscoveredMac] = []
    private(set) var macState = MacState.unknown
    private(set) var permissions = PermissionState()
    private(set) var isScanning = false

    /// Digits typed into the six PIN cells so far.
    private(set) var pinEntry = ""
    /// Bumped to fire the shake on a wrong PIN. The view animates off the change rather
    /// than being told to animate, so a repeat failure shakes again.
    private(set) var shakeToken = 0

    // MARK: - Collaborators

    private let identityStore: PhoneIdentityStore
    private let browser = DeckBrowser()
    private let client: DeckClient
    private var reconnectTask: Task<Void, Never>?
    private var pendingPIN: PairingPIN?
    private var targetMacID: String?

    init(identityStore: PhoneIdentityStore = PhoneIdentityStore()) {
        self.identityStore = identityStore
        self.client = DeckClient(identityStore: identityStore)

        let trust = identityStore.loadTrust()
        self.pairing = PairingMachine(trust: trust)
        // FR-22: onboarding is shown only when no Mac has ever been paired.
        self.route = trust.hasNeverPaired ? .onboarding : .discovery

        wireClient()
        wireBrowser()
    }

    var connectedMacName: String? { pairing.device?.name }

    /// The Mac being talked to, refreshed from the live browse results so a reconnect
    /// uses the current endpoint rather than a stale one.
    private var targetMac: DiscoveredMac? {
        guard let targetMacID else { return nil }
        return discovered.first { $0.deviceID == targetMacID }
    }

    // MARK: - Discovery (FR-1)

    /// Called once the local-network pre-prompt has been accepted — starting the
    /// browser is what raises the system dialog, so it must not run before then (FR-24).
    ///
    /// Browsing continues while the deck is open, which is what lets a Mac that comes
    /// back reconnect immediately; so this leaves the route alone unless it is moving
    /// the user off onboarding.
    func beginDiscovery() {
        if route == .onboarding {
            route = .discovery
            pairing.handle(.beginDiscovery)
        }
        browser.start()
    }

    func stopDiscovery() {
        browser.stop()
        isScanning = false
    }

    // MARK: - Pairing (FR-2, FR-3)

    func select(_ mac: DiscoveredMac) {
        targetMacID = mac.deviceID
        pairing.handle(.deviceSelected(mac.identity))

        switch pairing.state {
        case .paired:
            connectTrusted(to: mac)
        case .awaitingPIN:
            pinEntry = ""
            route = .pin
        case .identityChanged:
            // The identity-changed card sits on the PIN screen (design S3).
            route = .pin
        default:
            break
        }
    }

    /// Takes whatever the field now holds, keeps the digits, and submits on the sixth.
    /// Filtering here rather than in the view means paste and autofill go through the
    /// same path as typing.
    func updatePINEntry(_ raw: String) {
        guard pairing.isAcceptingPIN else { return }
        pinEntry = String(raw.filter(\.isNumber).prefix(PairingPIN.length))
        if pinEntry.count == PairingPIN.length {
            submitPIN()
        }
    }

    private func submitPIN() {
        guard let mac = targetMac, let pin = PairingPIN(pinEntry) else {
            failPIN()
            return
        }
        pendingPIN = pin
        client.connect(to: mac, credential: .pairing(pin))
    }

    /// The user confirmed the destructive re-pair after an identity change.
    func confirmRePair() {
        pairing.handle(.rePairConfirmed)
        if let macID = targetMacID {
            identityStore.forget(macID: macID)
        }
        identityStore.save(pairing.trust)
        pinEntry = ""
    }

    func cancelPairing() {
        pendingPIN = nil
        client.disconnect()
        pairing.handle(.cancelled)
        pinEntry = ""
        route = .discovery
    }

    /// FR-5: drop this Mac entirely; it needs the PIN again.
    func unpairCurrentMac() {
        guard let macID = pairing.device?.deviceID else { return }
        client.disconnect()
        identityStore.forget(macID: macID)
        pairing.handle(.unpaired(deviceID: macID))
        identityStore.save(pairing.trust)
        route = .discovery
    }

    // MARK: - Session (FR-4)

    /// Journey 2: unlock the phone and the deck is already coming back. A Mac the phone
    /// has paired with needs no tap — only an unknown one does.
    private func autoConnectIfPossible() {
        guard route == .discovery, !client.isConnected else { return }
        guard case .discovering = pairing.state else { return }

        let candidate = discovered.first {
            $0.speaksOurProtocol
                && pairing.trust.isTrusted($0.identity)
                && identityStore.sessionSecret(forMacID: $0.deviceID) != nil
        }
        guard let candidate else { return }
        select(candidate)
    }

    private func connectTrusted(to mac: DiscoveredMac) {
        guard let secret = identityStore.sessionSecret(forMacID: mac.deviceID) else {
            // Pinned but with no key to show for it — the two are written together, so
            // this only happens if the Keychain was partially cleared. Re-pair.
            pairing.handle(.deviceSelected(DeviceIdentity(
                deviceID: mac.deviceID,
                name: mac.name,
                publicKeyHash: ""
            )))
            route = .pin
            return
        }
        route = .deck
        client.connect(to: mac, credential: .trusted(secret))
    }

    private func wireClient() {
        client.onSessionEvent = { [weak self] event in
            guard let self else { return }
            self.session.handle(event)
            if case .reconnecting = self.session.state {
                self.scheduleReconnect()
            }
        }

        client.onHelloAck = { [weak self] ack in
            guard let self else { return }

            // The fingerprint in the TXT record is what trust was evaluated against;
            // if the agent now presents a different one, stop rather than carry on.
            if let expected = self.targetMac?.fingerprint,
               !expected.isEmpty,
               expected != ack.identity.publicKeyHash {
                self.client.disconnect()
                self.pairing.handle(.deviceSelected(ack.identity))
                self.route = .pin
                return
            }

            if let pin = self.pendingPIN {
                self.client.sendPairRequest(pin: pin)
            }
        }

        client.onPairResult = { [weak self] result in
            self?.handle(pairResult: result)
        }

        client.onStateEvent = { [weak self] macState in
            self?.macState = macState
        }
    }

    private func handle(pairResult result: PairResult) {
        pendingPIN = nil

        guard result.accepted, let identity = result.identity, let secret = result.sessionSecret else {
            failPIN()
            return
        }

        identityStore.setSessionSecret(secret, forMacID: identity.deviceID)
        pairing.handle(.pairAccepted(identity))
        identityStore.save(pairing.trust)
        pinEntry = ""
        route = .deck
    }

    /// Wrong PIN: shake, clear the digits in place, decrement the counter. The flow
    /// never resets (design S3).
    private func failPIN() {
        pendingPIN = nil
        client.disconnect()
        pairing.handle(.pairRejected)
        pinEntry = ""
        shakeToken += 1

        if case .discovering = pairing.state {
            // Out of tries; back to the device list.
            route = .discovery
        }
    }

    private func scheduleReconnect() {
        guard reconnectTask == nil else { return }
        let delay = session.nextRetryDelay()

        reconnectTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled, let self else { return }
            self.reconnectTask = nil

            guard let mac = self.targetMac,
                  let secret = self.identityStore.sessionSecret(forMacID: mac.deviceID) else {
                return
            }
            self.client.connect(to: mac, credential: .trusted(secret))
        }
    }

    private func wireBrowser() {
        browser.onResults = { [weak self] macs in
            guard let self else { return }
            self.discovered = macs
            self.isScanning = true
            if !macs.isEmpty {
                // Results arriving is the only positive signal iOS gives that local
                // network access was actually granted.
                self.permissions[.localNetwork] = .granted
            }

            // A Mac reappearing while we are trying to reach it is the fastest possible
            // reconnect trigger — faster than waiting out the backoff (FR-4).
            if case .reconnecting = self.session.state,
               let mac = self.targetMac,
               let secret = self.identityStore.sessionSecret(forMacID: mac.deviceID) {
                self.reconnectTask?.cancel()
                self.reconnectTask = nil
                self.client.connect(to: mac, credential: .trusted(secret))
                return
            }

            self.autoConnectIfPossible()
        }

        browser.onStateChange = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                self.isScanning = true
            case .failed:
                self.isScanning = false
                self.permissions[.localNetwork] = .denied
            case .cancelled:
                self.isScanning = false
            default:
                break
            }
        }
    }
}

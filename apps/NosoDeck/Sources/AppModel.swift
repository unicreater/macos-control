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

    /// The user's layout, and where they are in it.
    private(set) var deck: Deck
    private(set) var currentPage = 0
    private(set) var isEditing = false
    /// Every app installed on the paired Mac, for the add-tile search (FR-8).
    private(set) var catalog: [AppCatalogEntry] = []
    /// The most recent action failure, for the tile that reported it.
    private(set) var lastActionError: String?
    let icons = IconCache()

    /// Digits typed into the six PIN cells so far.
    private(set) var pinEntry = ""
    /// Bumped to fire the shake on a wrong PIN. The view animates off the change rather
    /// than being told to animate, so a repeat failure shakes again.
    private(set) var shakeToken = 0

    // MARK: - Collaborators

    private let identityStore: PhoneIdentityStore
    private let browser = DeckBrowser()
    private let client: DeckClient
    private let deckStore: DeckStore
    private var reconnectTask: Task<Void, Never>?
    private var pendingPIN: PairingPIN?
    private var targetMacID: String?
    /// True when the layout came from disk, so the Mac's suggestions are only used on a
    /// genuinely first run (FR-12).
    private var hasSavedDeck: Bool

    init(identityStore: PhoneIdentityStore = PhoneIdentityStore()) {
        // Read through a local: `self` is not usable until every stored property is set.
        let deckStore = DeckStore()
        let saved = deckStore.load()

        self.identityStore = identityStore
        self.client = DeckClient(identityStore: identityStore)
        self.deckStore = deckStore
        self.hasSavedDeck = saved != nil
        self.deck = saved ?? Deck()

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

    // MARK: - The deck (FR-6, FR-9, FR-12)

    var pageCount: Int { deck.pageCount }

    var visiblePage: Page {
        deck.pages[min(currentPage, deck.pageCount - 1)]
    }

    /// The keycap state for a tile, from the Mac's live state (FR-10 lights these up;
    /// M4 only needs the derivation).
    func activity(for tile: Tile) -> TileActivityState {
        macState.tileState(for: tile.target)
    }

    func icon(for tile: Tile) -> Image? {
        guard case .app(let bundleID) = tile.target else { return nil }
        return icons.image(forHash: catalog.first { $0.bundleID == bundleID }?.iconHash)
    }

    /// A tap: launch if closed, front if running (FR-9). Refused while the link is
    /// down, which is the same condition the deck's opacity is showing.
    func activate(_ tile: Tile) {
        guard session.acceptsActions else { return }
        lastActionError = nil
        client.send(.action(ActionRequest(activating: tile.target)))
    }

    func setPage(_ index: Int) {
        currentPage = min(max(index, 0), deck.pageCount - 1)
    }

    func toggleEditing() {
        isEditing.toggle()
    }

    func add(_ entry: AppCatalogEntry) {
        add(Tile.app(entry))
    }

    func add(_ tile: Tile) {
        if deck.add(tile, toPageAt: currentPage) == false {
            // The current page is full; fall through to the first slot anywhere, which
            // is the slot the add-tile flow told the user about.
            guard deck.add(tile) != nil else { return }
        }
        persistDeck()
        requestMissingIcons()
    }

    func removeTile(id: UUID) {
        deck.removeTile(id: id)
        persistDeck()
    }

    func moveTile(id: UUID, to slot: DeckSlot) {
        guard deck.moveTile(id: id, to: slot) else { return }
        persistDeck()
    }

    /// Where a newly added tile would land — "Page 1 · slot 8 of 8" (design S6).
    var nextSlot: DeckSlot? {
        deck.pages[min(currentPage, deck.pageCount - 1)].nextFreeSlot
            .map { DeckSlot(pageIndex: currentPage, slotIndex: $0) }
            ?? deck.nextFreeSlot
    }

    private func persistDeck() {
        hasSavedDeck = true
        deckStore.save(deck)
    }

    // MARK: - Catalog and icons (FR-7, FR-8)

    func requestCatalog(query: String? = nil) {
        guard session.acceptsActions else { return }
        client.send(.catalogRequest(CatalogRequest(query: query)))
    }

    func searchResults(for query: String) -> [AppCatalogEntry] {
        catalog.searching(query)
    }

    private func apply(_ catalog: Catalog) {
        // A filtered response would otherwise shrink the local catalog to the query.
        if catalog.apps.count >= self.catalog.count {
            self.catalog = catalog.apps
        }

        // FR-12: a fresh pair lands on a filled page rather than eight dashed outlines.
        if !hasSavedDeck && deck.isEmpty {
            let starters = catalog.starterTiles()
            if !starters.isEmpty {
                deck = Deck(pages: [Page(tiles: starters)])
                persistDeck()
            }
        }

        requestMissingIcons()
    }

    /// One request per unseen hash, for the tiles actually on the deck. The catalog is
    /// hundreds of apps; the deck is at most sixty-four tiles.
    private func requestMissingIcons() {
        let onDeck = deck.appBundleIDs
        for entry in catalog where onDeck.contains(entry.bundleID) {
            guard icons.shouldRequest(hash: entry.iconHash), let hash = entry.iconHash else { continue }
            client.send(.iconRequest(IconRequest(hash: hash)))
        }
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
            } else if ack.isPaired {
                // A trusted reconnect: ask for the catalog straight away so icons and
                // the app list are ready before the user opens anything.
                self.requestCatalog()
            }
        }

        client.onCatalog = { [weak self] catalog in
            self?.apply(catalog)
        }

        client.onIcon = { [weak self] icon in
            self?.icons.store(hash: icon.hash, png: icon.png)
        }

        client.onActionResult = { [weak self] result in
            guard let self, !result.ok else { return }
            self.lastActionError = result.error
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
        // First thing after pairing: the catalog, which also carries the starter deck.
        requestCatalog()
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

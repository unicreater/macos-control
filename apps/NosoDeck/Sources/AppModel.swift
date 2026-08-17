import DeckKit
import Foundation
import Observation
import SwiftUI
import UIKit

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
        case settings
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
    /// The Mac's Apple Shortcuts, once consent has been given (FR-13).
    private(set) var shortcuts: [String] = []
    private(set) var browserTabs: [BrowserTab] = []
    private var hasRequestedShortcuts = false
    private var shortcutsAnswered = false
    /// The most recent action failure, for the tile that reported it.
    private(set) var lastActionError: String?
    private(set) var isShowingPaywall = false
    private(set) var paywallReason: String?
    let icons = IconCache()
    let entitlements = EntitlementStore()

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

        let defaults = UserDefaults.standard
        self.keepsScreenAwake = (defaults.object(forKey: Self.keepAwakeKey) as? Bool) ?? true
        self.isEmojiStripEnabled = (defaults.object(forKey: Self.emojiStripKey) as? Bool) ?? true
        self.bulletStyle = (defaults.string(forKey: Self.bulletStyleKey)) ?? "bullet"
        self.isLandscapeLayout = (defaults.object(forKey: Self.layoutKey) as? Bool) ?? true

        let trust = identityStore.loadTrust()
        self.pairing = PairingMachine(trust: trust)

        if trust.hasNeverPaired {
            self.route = .onboarding
        } else {
            // Returning user: go straight to the deck and auto-connect in the
            // background. The last paired Mac will be picked up by autoConnectIfPossible
            // as soon as Bonjour finds it — no manual selection needed.
            self.route = .deck
            self.targetMacID = trust.pairedDeviceIDs.first
        }

        wireClient()
        wireBrowser()

        // If we have a paired Mac, start browsing immediately so the auto-connect
        // fires as soon as the Mac is found on the network.
        if !trust.hasNeverPaired {
            pairing.handle(.beginDiscovery)
            browser.start()
        }
    }

    #if DEBUG
    /// Minimal init for SwiftUI previews — no networking, no Bonjour.
    static func preview(tiles: [Tile] = [], macState: MacState = .unknown) -> AppModel {
        let m = AppModel()
        m.deck = Deck(pages: [Page(tiles: tiles)])
        m.macState = macState
        m.route = .deck
        return m
    }
    #endif

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

    func startPairing() {
        route = .discovery
        pairing.handle(.beginDiscovery)
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
            // Connect immediately with the open pairing key — the Mac will show
            // the PIN popup when it receives our hello. The user reads the PIN
            // from the Mac and enters it here.
            client.connect(to: mac, credential: .pairing(PairingPIN.random()))
        case .identityChanged:
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
        guard pendingPIN == nil else { return }
        guard let pin = PairingPIN(pinEntry) else {
            failPIN()
            return
        }
        pendingPIN = pin
        client.sendPairRequest(pin: pin)
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
        print("[NosoDeck] activate: state=\(session.state) accepts=\(session.acceptsActions) target=\(tile.target)")
        guard session.acceptsActions else {
            print("[NosoDeck] BLOCKED — not live")
            return
        }
        print("[NosoDeck] SENDING action for \(tile.label)")
        Haptics.tileTap()
        lastActionError = nil
        client.send(.action(ActionRequest(activating: tile.target)))
    }

    /// Swipe down on a running tile: a graceful quit, never a force kill (FR-11).
    func quit(_ tile: Tile) {
        guard session.acceptsActions, case .app(let bundleID) = tile.target else { return }
        guard macState.isRunning(bundleID) else { return }
        lastActionError = nil
        client.send(.action(ActionRequest(kind: .quitApp, target: bundleID)))
    }

    func setPage(_ index: Int) {
        // Allow pageCount as the AI Sessions page tag.
        currentPage = min(max(index, 0), deck.pageCount)
    }

    // MARK: - Pages and premium (FR-17)

    var entitlement: Entitlement { entitlements.entitlement }
    var canAddPage: Bool { deck.canAddPage(for: entitlement) }

    /// Hitting the tier's page limit opens the paywall. It is never a dead tap, and
    /// nothing that was already free becomes locked.
    func addPage() {
        guard deck.addPage(for: entitlement) else {
            presentPaywall(reason: "Free decks hold \(Entitlement.free.maxPages) pages. Premium takes you to \(Entitlement.premium.maxPages).")
            return
        }
        persistDeck()
        setPage(deck.pageCount - 1)
    }

    func removePage(at index: Int) {
        guard deck.removePage(at: index) else { return }
        persistDeck()
        setPage(min(currentPage, deck.pageCount - 1))
    }

    /// Pages beyond the current tier's limit — visible, but not added to. A lapsed
    /// subscriber keeps everything they built.
    func isPageLocked(_ index: Int) -> Bool {
        deck.lockedPageIndices(for: entitlement).contains(index)
    }

    // MARK: - Settings and polish (FR-21)

    func openSettings() { route = .settings }
    func closeSettings() { route = .deck }

    /// FR-21: the idle timer is disabled *only* while the deck is foregrounded and
    /// connected. A deck that can't reach the Mac has no claim on the user's battery.
    private(set) var keepsScreenAwake = true
    private(set) var isEmojiStripEnabled = true
    private(set) var isLandscapeLayout = true

    func setKeepsScreenAwake(_ enabled: Bool) {
        keepsScreenAwake = enabled
        UserDefaults.standard.set(enabled, forKey: Self.keepAwakeKey)
        applyIdleTimer()
    }

    func setEmojiStripEnabled(_ enabled: Bool) {
        isEmojiStripEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: Self.emojiStripKey)
    }

    func setLandscapeLayout(_ enabled: Bool) {
        isLandscapeLayout = enabled
        UserDefaults.standard.set(enabled, forKey: Self.layoutKey)
    }

    func applyIdleTimer() {
        UIApplication.shared.isIdleTimerDisabled =
            keepsScreenAwake && route == .deck && session.state.isLive
    }

    fileprivate static let keepAwakeKey = "com.noso.nosodeck.keepAwake"
    fileprivate static let emojiStripKey = "com.noso.nosodeck.emojiStrip"
    fileprivate static let bulletStyleKey = "com.noso.nosodeck.bulletStyle"
    fileprivate static let layoutKey = "com.noso.nosodeck.landscapeLayout"

    /// "bullet" for • or "number" for 1. 2. 3.
    private(set) var bulletStyle: String = "bullet"

    func setBulletStyle(_ style: String) {
        bulletStyle = style
        UserDefaults.standard.set(style, forKey: Self.bulletStyleKey)
    }

    func presentPaywall(reason: String? = nil) {
        paywallReason = reason
        isShowingPaywall = true
    }

    func dismissPaywall() {
        isShowingPaywall = false
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

    // MARK: - Recents and emoji (FR-15, FR-16)

    /// The four cells of the recents column, most recent first (FR-16).
    var visibleRecents: [String] { macState.visibleRecents }

    func name(forBundleID bundleID: String) -> String {
        catalog.first { $0.bundleID == bundleID }?.name ?? bundleID
    }

    func icon(forBundleID bundleID: String) -> Image? {
        icons.image(forHash: catalog.first { $0.bundleID == bundleID }?.iconHash)
    }

    func activateRecent(_ bundleID: String) {
        guard session.acceptsActions else { return }
        lastActionError = nil
        client.send(.action(ActionRequest(kind: .activateApp, target: bundleID)))
    }

    func requestBrowserTabs() {
        guard session.acceptsActions else { return }
        client.send(.browserTabsRequest)
    }

    func sendVoiceText(_ text: String) {
        guard session.acceptsActions, !text.isEmpty else { return }
        client.send(.action(ActionRequest(kind: .insertText, target: text)))
    }

    func sendGesture(_ kind: ActionKind) {
        guard session.acceptsActions else { return }
        client.send(.action(ActionRequest(kind: kind, target: "")))
    }

    func activateSession(bundleID: String, windowID: Int?) {
        guard session.acceptsActions else { return }
        lastActionError = nil
        if let windowID {
            // Send windowID in the target so the Mac can raise that specific window
            client.send(.action(ActionRequest(kind: .activateApp, target: "\(bundleID):\(windowID)")))
        } else {
            client.send(.action(ActionRequest(kind: .activateApp, target: bundleID)))
        }
    }

    func activateByBundleID(_ bundleID: String) {
        guard session.acceptsActions else { return }
        lastActionError = nil
        client.send(.action(ActionRequest(kind: .activateApp, target: bundleID)))
    }

    /// Sends an emoji for the Mac to type — or, without Accessibility, to put on the
    /// clipboard and announce. Both are success; the phone doesn't need to know which.
    func send(emoji: String) {
        guard session.acceptsActions else { return }
        lastActionError = nil
        client.send(.action(ActionRequest(kind: .insertText, target: emoji)))
    }

    // MARK: - Catalog and icons (FR-7, FR-8)

    func requestCatalog(query: String? = nil) {
        guard session.acceptsActions else { return }
        client.send(.catalogRequest(CatalogRequest(query: query)))
    }

    func searchResults(for query: String) -> [AppCatalogEntry] {
        catalog.searching(query)
    }

    // MARK: - Shortcuts (FR-13)

    /// Asking for the list is what raises the Automation dialog on the Mac, so this is
    /// called only after the pre-prompt card has been accepted (FR-24).
    func requestShortcuts() {
        guard session.acceptsActions else { return }
        hasRequestedShortcuts = true
        client.send(.shortcutsRequest)
    }

    /// Consent was refused if the Mac answered with nothing. The Shortcuts tab then
    /// shows its degraded path — app and website tiles keep working — rather than an
    /// empty list with no explanation.
    var automationWasRefused: Bool {
        hasRequestedShortcuts && shortcutsAnswered && shortcuts.isEmpty
    }

    private func apply(_ catalog: Catalog) {
        // A filtered response would otherwise shrink the local catalog to the query.
        if catalog.apps.count >= self.catalog.count {
            self.catalog = catalog.apps
        }

        // FR-12: a fresh pair lands on a filled page rather than eight dashed outlines.
        if !hasSavedDeck && deck.isEmpty {
            var starters = catalog.starterTiles()
            // Fallback: use recent apps if no suggestions
            if starters.isEmpty {
                let recentIDs = macState.recents.prefix(Page.maxTiles)
                let byID = Dictionary(catalog.apps.map { ($0.bundleID, $0) }, uniquingKeysWith: { first, _ in first })
                starters = recentIDs.compactMap { bundleID in
                    byID[bundleID].map { Tile.app($0) }
                }
            }
            if !starters.isEmpty {
                deck = Deck(pages: [Page(tiles: starters)])
                persistDeck()
            }
        }

        requestMissingIcons()

        // Retry icon requests after a delay — the Mac may still be rendering them.
        Task {
            try? await Task.sleep(for: .seconds(3))
            self.requestMissingIcons()
        }
    }

    /// Request icons for every app in the catalog (used by AddTileView).
    func requestAllIcons() {
        for entry in catalog {
            guard icons.shouldRequest(hash: entry.iconHash), let hash = entry.iconHash else { continue }
            client.send(.iconRequest(IconRequest(hash: hash)))
        }
    }

    /// Request icons for tiles on the deck, session apps, AND recent apps.
    private func requestMissingIcons() {
        var needed = deck.appBundleIDs
        for info in macState.sessions {
            needed.insert(info.bundleID)
        }
        // Also request icons for recent apps (App Time Travel)
        for bundleID in macState.recents {
            needed.insert(bundleID)
        }
        for entry in catalog where needed.contains(entry.bundleID) {
            guard icons.shouldRequest(hash: entry.iconHash), let hash = entry.iconHash else { continue }
            client.send(.iconRequest(IconRequest(hash: hash)))
        }
    }

    // MARK: - Session (FR-4)

    /// Journey 2: unlock the phone and the deck is already coming back. A Mac the phone
    /// has paired with needs no tap — only an unknown one does.
    private func autoConnectIfPossible() {
        guard !client.isConnected else { return }
        guard route == .discovery || route == .deck else { return }

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
            self.applyIdleTimer()
            if case .reconnecting = self.session.state {
                self.scheduleReconnect()
            }
        }

        client.onHelloAck = { [weak self] ack in
            guard let self else { return }

            if let pin = self.pendingPIN {
                self.client.sendPairRequest(pin: pin)
            } else if ack.isPaired {
                self.requestCatalog()
            }
        }

        client.onCatalog = { [weak self] catalog in
            self?.apply(catalog)
        }

        client.onIcon = { [weak self] icon in
            self?.icons.store(hash: icon.hash, png: icon.png)
        }

        client.onShortcuts = { [weak self] names in
            guard let self else { return }
            self.shortcuts = names
            self.shortcutsAnswered = true
            self.permissions[.automation] = names.isEmpty ? .denied : .granted
        }

        client.onBrowserTabs = { [weak self] tabs in
            self?.browserTabs = tabs
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
            if !macState.sessions.isEmpty {
                print("[NosoDeck] Sessions received: \(macState.sessions.map { "\($0.bundleID): \($0.sessions.count) sessions" })")
                for info in macState.sessions {
                    for s in info.sessions {
                        print("[NosoDeck]   \(s.label) — \(s.status) \(s.detail ?? "") cpu:\(s.cpuPercent ?? 0)")
                    }
                }
            }
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
        Haptics.pairingSucceeded()
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
        Haptics.pairingFailed()

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

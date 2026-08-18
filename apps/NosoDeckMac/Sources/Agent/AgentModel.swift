import DeckKit
import Foundation
import Network
import Observation

/// A phone this Mac trusts.
struct PairedPhone: Identifiable, Hashable, Sendable {
    var deviceID: String
    var name: String
    var id: String { deviceID }
}

/// What the menu bar reports about the listener (FR-19).
enum AgentStatus: Equatable, Sendable {
    case starting
    case advertising
    case connected(phoneName: String)
    case failed(String)

    var menuDescription: String {
        switch self {
        case .starting: return "Starting…"
        case .advertising: return "Waiting for your iPhone"
        case .connected(let phoneName): return "Connected — \(phoneName)"
        case .failed(let reason): return "Not running — \(reason)"
        }
    }
}

/// The agent itself: identity, PIN, listener, and the connected sessions.
///
/// Everything is main-actor isolated. The Network.framework callbacks are all delivered
/// on the main queue, so there is no cross-thread state here to protect.
@MainActor
@Observable
final class AgentModel {
    private(set) var status: AgentStatus = .starting
    /// The six digits shown in the menu while no phone is paired (FR-19).
    private(set) var pin: PairingPIN
    private(set) var pairedPhones: [PairedPhone] = []

    private let identityStore: AgentIdentityStore
    private let listener = DeckListener()
    private let catalogProvider = AppCatalogProvider()
    private let executor = ActionExecutor()
    private let stateObserver = MacStateObserver()
    private let sessionTracker = SessionTracker()
    private let shortcuts = ShortcutsBridge()
    private let textInserter = TextInserter()
    private let loginItem = LoginItem()
    private let browserTabReader = BrowserTabReader()
    private let emojiRain = EmojiRainWindow()
    private let dragDetector = DragDetector()
    private let pinWindow = PINWindow()
    private var sessions: [AgentSession] = []
    /// Failed PIN attempts since the last rotation.
    private var failedAttempts = 0

    /// Built once and reused. Enumerating every app and rendering its icon takes long
    /// enough to be felt, so it happens at launch rather than while a phone waits.
    private var cachedCatalog: Catalog?
    private var bundleIDsByIconHash: [String: String] = [:]

    private static let phoneNamesDefaultsKey = "com.noso.nosodeck.pairedPhoneNames"

    init(identityStore: AgentIdentityStore = AgentIdentityStore()) {
        self.identityStore = identityStore
        self.pin = PairingPIN.random()
        self.pairedPhones = Self.loadPairedPhones(identityStore: identityStore)
    }

    /// This Mac's name, as it appears in the phone's device list.
    var serviceName: String {
        Host.current().localizedName ?? ProcessInfo.processInfo.hostName
    }

    var isPaired: Bool { !pairedPhones.isEmpty }

    func showPIN() {
        pinWindow.show(pin: pin, macName: serviceName, paired: isPaired) { [weak self] in
            guard let self else { return }
            for phone in self.pairedPhones {
                self.unpair(phoneID: phone.deviceID)
            }
            self.showPIN()
        }
    }

    var isConnected: Bool {
        if case .connected = status { return true }
        return false
    }

    /// FR-15 is opt-in: Accessibility is never requested at launch, only when the user
    /// turns emoji typing on from the menu.
    var isEmojiInsertionTrusted: Bool { textInserter.isTrusted }

    func requestEmojiInsertionTrust() {
        textInserter.requestTrust()
    }

    // MARK: - Open at login (FR-20)

    /// Read live rather than remembered: the user can also turn this off in System
    /// Settings, and a toggle that disagrees with the system is worse than none.
    var opensAtLogin: Bool { loginItem.isEnabled }
    var loginItemNeedsApproval: Bool { loginItem.needsApproval }
    private(set) var loginItemError: String?

    func setOpensAtLogin(_ enabled: Bool) {
        loginItemError = loginItem.setEnabled(enabled)
    }

    // MARK: - Lifecycle

    func start() {
        listener.onStateChange = { [weak self] state in
            self?.handleListenerState(state)
        }
        listener.onConnection = { [weak self] connection in
            self?.adopt(connection: connection)
        }
        stateObserver.onChange = { [weak self] macState in
            self?.broadcastState()
        }
        sessionTracker.onChange = { [weak self] _ in
            self?.broadcastState()
        }
        dragDetector.onChange = { [weak self] _ in
            self?.broadcastState()
        }
        stateObserver.start()
        sessionTracker.start()
        dragDetector.start()

        restartListener()
        // Warm the catalog in the background so it doesn't block the main thread
        // and freeze the PIN window.
        Task.detached { [weak self] in
            let catalog = AppCatalogProvider().catalog()
            await MainActor.run {
                self?.cachedCatalog = catalog
                self?.bundleIDsByIconHash = Dictionary(
                    catalog.apps.compactMap { entry in entry.iconHash.map { ($0, entry.bundleID) } },
                    uniquingKeysWith: { first, _ in first }
                )
            }
        }

    }

    /// Merges app state + session tracking + drag state and pushes to every paired phone.
    private func broadcastState() {
        var state = stateObserver.current
        state.sessions = sessionTracker.current
        state.isDragging = dragDetector.isDragging
        for session in sessions where session.isPaired {
            session.connection.send(Envelope(message: .stateEvent(state)))
        }
    }

    @discardableResult
    private func warmCatalog() -> Catalog {
        if let cachedCatalog { return cachedCatalog }
        let catalog = catalogProvider.catalog()
        cachedCatalog = catalog
        bundleIDsByIconHash = Dictionary(
            catalog.apps.compactMap { entry in entry.iconHash.map { ($0, entry.bundleID) } },
            uniquingKeysWith: { first, _ in first }
        )
        return catalog
    }

    func stop() {
        stateObserver.stop()
        sessionTracker.stop()
        dragDetector.stop()
        for session in sessions {
            session.connection.cancel()
        }
        sessions.removeAll()
        listener.stop()
    }

    /// Rebuilds the listener around the current key set.
    ///
    /// The acceptable keys are fixed when the listener starts, so pairing, unpairing,
    /// and rotating the PIN all have to come through here. Live sessions survive it —
    /// only the advertised socket is replaced.
    private func restartListener() {
        // The open pairing key lets any phone connect for the pairing flow.
        // Authentication happens at the application layer (PIN in pairRequest).
        var keys = [PresharedKey(
            identity: DeckService.pairingKeyIdentity,
            key: DeckTransport.openPairingKey(deviceID: identityStore.deviceID)
        )]
        for (phoneID, secret) in identityStore.pairedPhones() {
            keys.append(PresharedKey(identity: phoneID, key: secret))
        }

        do {
            try listener.restart(
                serviceName: serviceName,
                deviceID: identityStore.deviceID,
                fingerprint: identityStore.fingerprint,
                keys: keys
            )
        } catch {
            status = .failed(error.localizedDescription)
        }
    }

    private func handleListenerState(_ state: NWListener.State) {
        switch state {
        case .ready:
            if !sessions.contains(where: { $0.isPaired }) {
                status = .advertising
            }
        case .failed(let error):
            status = .failed(error.localizedDescription)
        case .cancelled:
            break
        default:
            break
        }
    }

    // MARK: - Sessions

    private func adopt(connection: PeerConnection) {
        // Any incoming connection while unpaired — show the PIN immediately
        // so the user can see it before they need to type it on the phone.
        if !isPaired {
            showPIN()
        }

        let session = AgentSession(connection: connection)
        sessions.append(session)

        connection.onEnvelope = { [weak self, weak session] envelope in
            guard let self, let session else { return }
            self.handle(envelope, from: session)
        }
        connection.onStateChange = { [weak self, weak session] state in
            guard let self, let session else { return }
            switch state {
            case .failed, .cancelled:
                self.discard(session)
            default:
                break
            }
        }
        connection.onError = { [weak self, weak session] _ in
            // A link that failed before saying hello is not worth diagnosing in the
            // menu bar. One that already introduced itself is left alone to retry —
            // FR-4 covers what the user sees while it does.
            guard let self, let session, session.hello == nil else { return }
            self.discard(session)
        }
        connection.start()
    }

    private func discard(_ session: AgentSession) {
        session.connection.cancel()
        sessions.removeAll { $0 === session }
        refreshStatus()
    }

    private func refreshStatus() {
        if let name = sessions.compactMap({ $0.isPaired ? $0.phoneName : nil }).first {
            status = .connected(phoneName: name)
        } else if listener.isRunning {
            status = .advertising
        }
    }

    // MARK: - Protocol

    private func handle(_ envelope: Envelope, from session: AgentSession) {
        switch envelope.message {
        case .hello(let hello):
            let paired = identityStore.isPaired(phoneID: hello.deviceID)
            session.adopt(hello: hello, isPaired: paired)
            session.connection.send(envelope.reply(.helloAck(HelloAck(
                identity: identityStore.identity(name: serviceName),
                isPaired: paired
            ))))

            if hello.protocolVersion != DeckKitVersion.wireProtocol {
                // The ack above tells the phone which version this agent speaks, which
                // is the only useful thing left to say before hanging up.
                discard(session)
                return
            }
            if paired {
                rememberName(hello.deviceName, forPhoneID: hello.deviceID)
                pinWindow.close()
                refreshStatus()
                // The current state, immediately — a phone that just connected should
                // not have to wait for the Mac to change before its tiles light up.
                session.connection.send(Envelope(message: .stateEvent({
                    var s = stateObserver.current; s.sessions = sessionTracker.current; s.isDragging = dragDetector.isDragging; return s
                }())))
            } else {
                // An unpaired phone just connected — show the PIN so the user can see it.
                pinWindow.show(pin: pin, macName: serviceName)
            }

        case .pairRequest(let request):
            handlePairRequest(request, envelope: envelope, session: session)

        case .ping:
            session.connection.send(envelope.reply(.pong))

        case .catalogRequest(let request):
            // Everything below this line is for trusted phones only. An unpaired one
            // has satisfied the pairing PSK and nothing more, so it gets no inventory
            // of this Mac and no ability to act on it.
            guard session.isPaired else { break }
            let catalog = warmCatalog()
            let apps = request.query.map { catalog.apps.searching($0) } ?? catalog.apps
            session.connection.send(envelope.reply(.catalog(
                Catalog(apps: apps, suggested: catalog.suggested)
            )))

        case .iconRequest(let request):
            guard session.isPaired else { break }
            guard let bundleID = bundleIDsByIconHash[request.hash],
                  let png = catalogProvider.iconPNG(forBundleID: bundleID) else { break }
            session.connection.send(envelope.reply(.icon(
                IconResponse(hash: request.hash, png: png)
            )))

        case .shortcutsRequest:
            guard session.isPaired else { break }
            // Asking for the list is what triggers the Automation consent dialog, and
            // the phone only asks after showing its pre-prompt card (FR-24). An empty
            // list means consent was refused; the phone hides the tab and says why.
            _ = shortcuts.permissionStatus(promptIfNeeded: true)
            let infos = shortcuts.shortcutInfos()
            session.connection.send(envelope.reply(.shortcuts(
                ShortcutList(names: infos.map(\.name), shortcuts: infos)
            )))

        case .action(let request):
            guard session.isPaired else { break }
            perform(request, for: envelope, on: session)

        case .browserTabsRequest:
            guard session.isPaired else { break }
            let tabs = browserTabReader.tabs()
            session.connection.send(envelope.reply(.browserTabs(BrowserTabList(tabs: tabs))))

        default:
            // State events are pushed, not requested; nothing else is expected inbound.
            break
        }
    }

    private func perform(_ request: ActionRequest, for envelope: Envelope, on session: AgentSession) {
        Task { [weak self, weak session] in
            let result = await self?.executor.perform(request)
            guard let session else { return }
            switch result {
            case .success:
                session.connection.send(envelope.reply(.actionResult(.success(requestID: envelope.id))))
            case .failure(let failure):
                session.connection.send(envelope.reply(.actionResult(
                    .failure(requestID: envelope.id, error: failure.message)
                )))
            case nil:
                break
            }
        }
    }

    private func handlePairRequest(_ request: PairRequest, envelope: Envelope, session: AgentSession) {
        guard let hello = session.hello else {
            // A pair request before hello: nothing to pair with.
            discard(session)
            return
        }

        guard request.pin == pin.digits else {
            failedAttempts += 1
            let remaining = max(PairingMachine.maxAttempts - failedAttempts, 0)
            session.connection.send(envelope.reply(.pairResult(.rejected(attemptsRemaining: remaining))))
            if remaining == 0 {
                // Out of tries: a fresh PIN, so a guesser has to start over and the
                // menu shows the user something new to type.
                rotatePIN()
            }
            return
        }

        let secret = identityStore.pair(phoneID: hello.deviceID)
        rememberName(hello.deviceName, forPhoneID: hello.deviceID)
        session.markPaired()

        session.connection.send(envelope.reply(.pairResult(.accepted(
            identity: identityStore.identity(name: serviceName),
            sessionSecret: secret
        ))))
        session.connection.send(Envelope(message: .stateEvent({
                    var s = stateObserver.current; s.sessions = sessionTracker.current; s.isDragging = dragDetector.isDragging; return s
                }())))

        // Pairing succeeded — close the PIN window.
        pinWindow.close()

        // A used PIN is spent. Rotating also rebuilds the listener, which is what
        // registers this phone's new key for its next connection.
        rotatePIN()
        refreshStatus()
    }

    // MARK: - Pairing administration

    /// Mints a new PIN and rebuilds the listener around it.
    func rotatePIN() {
        failedAttempts = 0
        pin = PairingPIN.random()
        pairedPhones = Self.loadPairedPhones(identityStore: identityStore)
        restartListener()
        if pinWindow.isVisible {
            pinWindow.show(pin: pin, macName: serviceName)
        }
    }

    /// Drops a phone's key. It needs the PIN again to come back (FR-5, Mac side).
    func unpair(phoneID: String) {
        identityStore.unpair(phoneID: phoneID)
        var names = Self.storedNames()
        names.removeValue(forKey: phoneID)
        UserDefaults.standard.set(names, forKey: Self.phoneNamesDefaultsKey)

        for session in sessions where session.phoneID == phoneID {
            discard(session)
        }
        rotatePIN()
    }

    // MARK: - Names
    //
    // Phone display names are convenience, not security, so they live in UserDefaults
    // while the keys that matter stay in the Keychain.

    private func rememberName(_ name: String, forPhoneID phoneID: String) {
        var names = Self.storedNames()
        guard names[phoneID] != name else { return }
        names[phoneID] = name
        UserDefaults.standard.set(names, forKey: Self.phoneNamesDefaultsKey)
        pairedPhones = Self.loadPairedPhones(identityStore: identityStore)
    }

    private static func storedNames() -> [String: String] {
        (UserDefaults.standard.dictionary(forKey: phoneNamesDefaultsKey) as? [String: String]) ?? [:]
    }

    private static func loadPairedPhones(identityStore: AgentIdentityStore) -> [PairedPhone] {
        let names = storedNames()
        return identityStore.pairedPhones().keys
            .map { PairedPhone(deviceID: $0, name: names[$0] ?? "iPhone") }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}

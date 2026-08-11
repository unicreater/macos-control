import Foundation

// The payload types for each message in PRD §5. Each is a plain Codable struct; the
// `v` and `id` fields every message carries live on `Envelope`, not here.

/// Opening message from the phone.
public struct Hello: Codable, Hashable, Sendable {
    public var protocolVersion: Int
    public var deviceName: String
    public var deviceID: String
    /// Optional feature flags, so a newer phone can ask for things an older agent will
    /// simply not list back.
    public var capabilities: [String]

    public init(
        protocolVersion: Int = DeckKitVersion.wireProtocol,
        deviceName: String,
        deviceID: String,
        capabilities: [String] = []
    ) {
        self.protocolVersion = protocolVersion
        self.deviceName = deviceName
        self.deviceID = deviceID
        self.capabilities = capabilities
    }
}

/// The agent's answer, carrying the identity the phone will pin.
public struct HelloAck: Codable, Hashable, Sendable {
    public var protocolVersion: Int
    public var identity: DeviceIdentity
    /// Whether the agent already trusts this phone. False means the phone should expect
    /// to send a `pairRequest`.
    public var isPaired: Bool
    public var capabilities: [String]

    public init(
        protocolVersion: Int = DeckKitVersion.wireProtocol,
        identity: DeviceIdentity,
        isPaired: Bool,
        capabilities: [String] = []
    ) {
        self.protocolVersion = protocolVersion
        self.identity = identity
        self.isPaired = isPaired
        self.capabilities = capabilities
    }
}

public struct PairRequest: Codable, Hashable, Sendable {
    public var pin: String

    public init(pin: PairingPIN) {
        self.pin = pin.digits
    }

    /// The PIN as a validated value, or nil if the peer sent something malformed.
    public var pairingPIN: PairingPIN? { PairingPIN(pin) }
}

public struct PairResult: Codable, Hashable, Sendable {
    public var accepted: Bool
    /// Present only on success — a rejected attempt reveals nothing and stores nothing.
    public var identity: DeviceIdentity?
    /// The long-term key this phone uses for every later connection. Handed over once,
    /// on the PIN-authenticated channel, and never sent again. Success only.
    public var sessionSecret: Data?
    /// Tries the agent will still accept, so the phone's counter matches the Mac's.
    public var attemptsRemaining: Int?

    public init(
        accepted: Bool,
        identity: DeviceIdentity? = nil,
        sessionSecret: Data? = nil,
        attemptsRemaining: Int? = nil
    ) {
        self.accepted = accepted
        self.identity = identity
        self.sessionSecret = sessionSecret
        self.attemptsRemaining = attemptsRemaining
    }

    public static func rejected(attemptsRemaining: Int) -> PairResult {
        PairResult(accepted: false, attemptsRemaining: attemptsRemaining)
    }

    public static func accepted(identity: DeviceIdentity, sessionSecret: Data) -> PairResult {
        PairResult(accepted: true, identity: identity, sessionSecret: sessionSecret)
    }
}

public struct CatalogRequest: Codable, Hashable, Sendable {
    /// Nil asks for the whole catalog; the phone filters locally after that.
    public var query: String?

    public init(query: String? = nil) {
        self.query = query
    }
}

public struct Catalog: Codable, Hashable, Sendable {
    public var apps: [AppCatalogEntry]

    public init(apps: [AppCatalogEntry]) {
        self.apps = apps
    }
}

public struct IconRequest: Codable, Hashable, Sendable {
    public var hash: String

    public init(hash: String) {
        self.hash = hash
    }
}

/// PNG bytes for one icon. Addressed by hash so the phone caches once and never asks
/// again, which is what keeps the catalog cheap to refresh.
public struct IconResponse: Codable, Hashable, Sendable {
    public var hash: String
    /// Base64 in JSON, courtesy of `Data`'s Codable conformance.
    public var png: Data

    public init(hash: String, png: Data) {
        self.hash = hash
        self.png = png
    }
}

public struct ShortcutList: Codable, Hashable, Sendable {
    public var names: [String]

    public init(names: [String]) {
        self.names = names
    }
}

/// What the Mac should do (PRD §5, `action`).
public enum ActionKind: String, Codable, Sendable, CaseIterable {
    /// Launch if closed, bring to front if running (FR-9).
    case activateApp
    /// Graceful terminate — never a force kill (FR-11).
    case quitApp
    case runShortcut
    case openURL
    case insertText
}

public struct ActionRequest: Codable, Hashable, Sendable {
    public var kind: ActionKind
    /// Bundle ID, Shortcut name, URL, or the text to insert, depending on `kind`.
    public var target: String

    public init(kind: ActionKind, target: String) {
        self.kind = kind
        self.target = target
    }

    /// The action a tile tap produces.
    public init(activating target: TileTarget) {
        switch target {
        case .app(let bundleID):
            self.init(kind: .activateApp, target: bundleID)
        case .shortcut(let name):
            self.init(kind: .runShortcut, target: name)
        case .website(let url):
            self.init(kind: .openURL, target: url)
        }
    }
}

public struct ActionResult: Codable, Hashable, Sendable {
    /// The `id` of the `action` envelope this answers.
    public var requestID: UUID
    public var ok: Bool
    public var error: String?

    public init(requestID: UUID, ok: Bool, error: String? = nil) {
        self.requestID = requestID
        self.ok = ok
        self.error = error
    }

    public static func success(requestID: UUID) -> ActionResult {
        ActionResult(requestID: requestID, ok: true)
    }

    public static func failure(requestID: UUID, error: String) -> ActionResult {
        ActionResult(requestID: requestID, ok: false, error: error)
    }
}

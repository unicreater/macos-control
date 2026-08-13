import Foundation
@testable import DeckKit

/// One sample of every message type, so coding tests can assert exhaustively rather
/// than on whichever cases someone remembered.
enum SampleMessages {
    static let identity = DeviceIdentity(
        deviceID: "F1E2D3C4",
        name: "Nora's MacBook Pro",
        publicKeyHash: "sha256:9f86d081884c7d659a2feaa0c55ad015"
    )

    static func message(for type: MessageType) -> Message {
        switch type {
        case .hello:
            return .hello(Hello(deviceName: "Nora's iPhone", deviceID: "A1B2C3", capabilities: ["icons"]))
        case .helloAck:
            return .helloAck(HelloAck(identity: identity, isPaired: false, capabilities: ["icons"]))
        case .pairRequest:
            return .pairRequest(PairRequest(pin: PairingPIN("482913")!))
        case .pairResult:
            return .pairResult(.accepted(
                identity: identity,
                sessionSecret: Data(repeating: 0xA7, count: DeckService.sessionSecretByteCount)
            ))
        case .catalogRequest:
            return .catalogRequest(CatalogRequest(query: "saf"))
        case .catalog:
            return .catalog(Catalog(apps: [
                AppCatalogEntry(bundleID: "com.apple.Safari", name: "Safari", iconHash: "abc123"),
                AppCatalogEntry(bundleID: "com.apple.dt.Xcode", name: "Xcode")
            ]))
        case .iconRequest:
            return .iconRequest(IconRequest(hash: "abc123"))
        case .icon:
            return .icon(IconResponse(hash: "abc123", png: Data([0x89, 0x50, 0x4E, 0x47, 0x00, 0xFF])))
        case .shortcutsRequest:
            return .shortcutsRequest
        case .shortcuts:
            return .shortcuts(ShortcutList(names: ["Start Focus", "Ship It"]))
        case .action:
            return .action(ActionRequest(kind: .activateApp, target: "com.apple.Safari"))
        case .actionResult:
            return .actionResult(.failure(requestID: UUID(), error: "not installed"))
        case .stateEvent:
            return .stateEvent(MacState(
                running: ["com.apple.Safari", "com.apple.dt.Xcode"],
                frontmost: "com.apple.Safari",
                recents: ["com.apple.Safari", "com.apple.dt.Xcode"]
            ))
        case .ping:
            return .ping
        case .pong:
            return .pong
        case .browserTabsRequest:
            return .browserTabsRequest
        case .browserTabs:
            return .browserTabs(BrowserTabList(tabs: [
                BrowserTab(title: "GitHub", url: "https://github.com"),
                BrowserTab(title: "Apple", url: "https://apple.com")
            ]))
        }
    }

    static var allEnvelopes: [Envelope] {
        MessageType.allCases.map { Envelope(message: message(for: $0)) }
    }
}

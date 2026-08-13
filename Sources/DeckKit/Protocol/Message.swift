import Foundation

/// The discriminator written into every frame's `type` field.
public enum MessageType: String, Codable, Sendable, CaseIterable {
    case hello
    case helloAck
    case pairRequest
    case pairResult
    case catalogRequest
    case catalog
    case iconRequest
    case icon
    case shortcutsRequest
    case shortcuts
    case action
    case actionResult
    case stateEvent
    case ping
    case pong
    case browserTabsRequest
    case browserTabs
}

/// One protocol message, payload included.
///
/// The full message set from PRD §5. Three of them — `shortcutsRequest`, `ping`, `pong`
/// — carry no payload, and their frames omit the `payload` key entirely.
public enum Message: Hashable, Sendable {
    case hello(Hello)
    case helloAck(HelloAck)
    case pairRequest(PairRequest)
    case pairResult(PairResult)
    case catalogRequest(CatalogRequest)
    case catalog(Catalog)
    case iconRequest(IconRequest)
    case icon(IconResponse)
    case shortcutsRequest
    case shortcuts(ShortcutList)
    case action(ActionRequest)
    case actionResult(ActionResult)
    case stateEvent(MacState)
    case ping
    case pong
    case browserTabsRequest
    case browserTabs(BrowserTabList)

    public var type: MessageType {
        switch self {
        case .hello: return .hello
        case .helloAck: return .helloAck
        case .pairRequest: return .pairRequest
        case .pairResult: return .pairResult
        case .catalogRequest: return .catalogRequest
        case .catalog: return .catalog
        case .iconRequest: return .iconRequest
        case .icon: return .icon
        case .shortcutsRequest: return .shortcutsRequest
        case .shortcuts: return .shortcuts
        case .action: return .action
        case .actionResult: return .actionResult
        case .stateEvent: return .stateEvent
        case .ping: return .ping
        case .pong: return .pong
        case .browserTabsRequest: return .browserTabsRequest
        case .browserTabs: return .browserTabs
        }
    }

    /// Messages that mean nothing beyond their type.
    public var hasPayload: Bool {
        switch self {
        case .shortcutsRequest, .ping, .pong, .browserTabsRequest: return false
        default: return true
        }
    }
}

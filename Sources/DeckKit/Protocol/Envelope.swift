import Foundation

/// A message plus the two fields every message carries: the protocol version `v` and a
/// correlation `id` (PRD §5).
///
/// The wire form is a flat JSON object:
/// ```json
/// {"v":1,"id":"…","type":"pairRequest","payload":{"pin":"123456"}}
/// ```
/// Coding is written by hand rather than synthesized because the payload's type depends
/// on the value of `type` — the one thing synthesis can't express.
public struct Envelope: Hashable, Sendable {
    public var version: Int
    /// Correlates a response with its request; also unique per pushed event.
    public var id: UUID
    public var message: Message

    public init(id: UUID = UUID(), message: Message, version: Int = DeckKitVersion.wireProtocol) {
        self.version = version
        self.id = id
        self.message = message
    }

    /// A reply reusing the request's id, which is how `actionResult` finds its `action`.
    public func reply(_ message: Message) -> Envelope {
        Envelope(id: id, message: message, version: version)
    }

    public var type: MessageType { message.type }
}

extension Envelope: Codable {
    private enum CodingKeys: String, CodingKey {
        case version = "v"
        case id
        case type
        case payload
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let version = try container.decode(Int.self, forKey: .version)
        let id = try container.decode(UUID.self, forKey: .id)

        // Decoded as a String first so an unknown type from a newer peer surfaces as a
        // recoverable ProtocolError instead of an opaque DecodingError.
        let rawType = try container.decode(String.self, forKey: .type)
        guard let type = MessageType(rawValue: rawType) else {
            throw ProtocolError.unsupportedMessageType(rawType)
        }

        func payload<T: Decodable>(_ kind: T.Type) throws -> T {
            guard container.contains(.payload) else { throw ProtocolError.missingPayload(type) }
            return try container.decode(kind, forKey: .payload)
        }

        let message: Message
        switch type {
        case .hello: message = .hello(try payload(Hello.self))
        case .helloAck: message = .helloAck(try payload(HelloAck.self))
        case .pairRequest: message = .pairRequest(try payload(PairRequest.self))
        case .pairResult: message = .pairResult(try payload(PairResult.self))
        case .catalogRequest: message = .catalogRequest(try payload(CatalogRequest.self))
        case .catalog: message = .catalog(try payload(Catalog.self))
        case .iconRequest: message = .iconRequest(try payload(IconRequest.self))
        case .icon: message = .icon(try payload(IconResponse.self))
        case .shortcutsRequest: message = .shortcutsRequest
        case .shortcuts: message = .shortcuts(try payload(ShortcutList.self))
        case .action: message = .action(try payload(ActionRequest.self))
        case .actionResult: message = .actionResult(try payload(ActionResult.self))
        case .stateEvent: message = .stateEvent(try payload(MacState.self))
        case .ping: message = .ping
        case .pong: message = .pong
        }

        self.init(id: id, message: message, version: version)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(version, forKey: .version)
        try container.encode(id, forKey: .id)
        try container.encode(message.type, forKey: .type)

        switch message {
        case .hello(let payload): try container.encode(payload, forKey: .payload)
        case .helloAck(let payload): try container.encode(payload, forKey: .payload)
        case .pairRequest(let payload): try container.encode(payload, forKey: .payload)
        case .pairResult(let payload): try container.encode(payload, forKey: .payload)
        case .catalogRequest(let payload): try container.encode(payload, forKey: .payload)
        case .catalog(let payload): try container.encode(payload, forKey: .payload)
        case .iconRequest(let payload): try container.encode(payload, forKey: .payload)
        case .icon(let payload): try container.encode(payload, forKey: .payload)
        case .shortcuts(let payload): try container.encode(payload, forKey: .payload)
        case .action(let payload): try container.encode(payload, forKey: .payload)
        case .actionResult(let payload): try container.encode(payload, forKey: .payload)
        case .stateEvent(let payload): try container.encode(payload, forKey: .payload)
        case .shortcutsRequest, .ping, .pong: break
        }
    }
}

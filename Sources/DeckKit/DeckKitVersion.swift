/// Version constants shared by both apps and the wire protocol.
///
/// `wireProtocol` is the `v` field carried on every protocol frame (PRD §5). Bump it
/// only for a breaking change to the message schema; `helloAck` negotiation is what
/// lets an older peer fail politely instead of misparsing.
public enum DeckKitVersion {
    /// Protocol version sent in every frame's `v` field.
    public static let wireProtocol = 1

    /// Semantic version of the DeckKit package itself.
    public static let package = "0.1.0"
}

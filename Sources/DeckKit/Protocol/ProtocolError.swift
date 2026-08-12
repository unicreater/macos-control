import Foundation

/// Everything that can go wrong reading the wire, as a typed error rather than a
/// `DecodingError` the caller has to pattern-match on strings.
public enum ProtocolError: Error, Hashable, Sendable, CustomStringConvertible {
    /// A message type this build doesn't know — usually a newer peer. Recoverable:
    /// skip the frame and carry on.
    case unsupportedMessageType(String)
    /// A protocol version this build can't speak. Not recoverable; the handshake fails.
    case unsupportedProtocolVersion(Int)
    /// A message type that requires a payload arrived without one.
    case missingPayload(MessageType)
    /// A frame larger than the cap. Not recoverable — the stream can no longer be
    /// resynchronized, so the connection must be torn down.
    case frameTooLarge(byteCount: Int)
    /// A frame header claiming a zero-length body. JSON is never empty, so this is a
    /// corrupt or hostile stream.
    case invalidFrameLength(UInt32)

    /// Whether the reader can keep going after this, or must drop the connection.
    public var isRecoverable: Bool {
        switch self {
        case .unsupportedMessageType, .missingPayload:
            return true
        case .unsupportedProtocolVersion, .frameTooLarge, .invalidFrameLength:
            return false
        }
    }

    public var description: String {
        switch self {
        case .unsupportedMessageType(let type):
            return "Unsupported message type '\(type)'"
        case .unsupportedProtocolVersion(let version):
            return "Unsupported protocol version \(version)"
        case .missingPayload(let type):
            return "Message '\(type.rawValue)' arrived without its payload"
        case .frameTooLarge(let byteCount):
            return "Frame of \(byteCount) bytes exceeds the maximum"
        case .invalidFrameLength(let length):
            return "Invalid frame length \(length)"
        }
    }
}

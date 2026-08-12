import Foundation

/// Length-prefixed JSON framing (PRD §5).
///
/// Each frame is a 4-byte big-endian body length followed by that many bytes of JSON.
/// TLS gives us a byte stream, not a message stream, so the length prefix is what turns
/// it back into discrete messages.
public enum FrameCodec {
    /// Bytes of length prefix in front of every body.
    public static let headerSize = 4

    /// Upper bound on a single frame. Generous because icon frames carry PNG data, but
    /// finite so a bad length field can't make the reader allocate without limit.
    public static let maxFrameBytes = 8 * 1024 * 1024

    public static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        // Deterministic output: easier to diff in logs, and it makes byte-level
        // assertions in tests meaningful.
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    public static func makeDecoder() -> JSONDecoder {
        JSONDecoder()
    }

    /// Encodes one envelope into a complete frame, prefix included.
    public static func encode(_ envelope: Envelope, using encoder: JSONEncoder? = nil) throws -> Data {
        let body = try (encoder ?? makeEncoder()).encode(envelope)
        guard body.count <= maxFrameBytes else {
            throw ProtocolError.frameTooLarge(byteCount: body.count)
        }

        var frame = Data(capacity: headerSize + body.count)
        let length = UInt32(body.count).bigEndian
        withUnsafeBytes(of: length) { frame.append(contentsOf: $0) }
        frame.append(body)
        return frame
    }

    /// Decodes a frame *body* — the bytes after the length prefix, as handed back by
    /// `FrameDecoder`.
    public static func decode(body: Data, using decoder: JSONDecoder? = nil) throws -> Envelope {
        try (decoder ?? makeDecoder()).decode(Envelope.self, from: body)
    }
}

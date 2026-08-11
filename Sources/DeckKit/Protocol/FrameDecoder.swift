import Foundation

/// Reassembles frames from a TLS byte stream.
///
/// Feed it whatever arrives — a partial header, three frames at once, one byte at a
/// time — and pull complete frames back out. This is the piece that has to be right
/// under adversarial input, because it is the first code to touch bytes from the
/// network.
///
/// Bytes are held as `[UInt8]` rather than `Data` deliberately: a `Data` produced by
/// slicing keeps its parent's indices, and index arithmetic that assumes a zero start
/// is a classic source of framing bugs.
public struct FrameDecoder {
    private var buffer: [UInt8] = []

    public let maxFrameBytes: Int

    public init(maxFrameBytes: Int = FrameCodec.maxFrameBytes) {
        self.maxFrameBytes = maxFrameBytes
    }

    /// Bytes received but not yet formed into a complete frame.
    public var bufferedByteCount: Int { buffer.count }

    public mutating func append(_ data: Data) {
        buffer.append(contentsOf: data)
    }

    /// The next complete frame body, or nil when more bytes are needed.
    ///
    /// Throws only for streams that can no longer be trusted — a length of zero or one
    /// beyond the cap. In both cases the buffer is left untouched, so the error repeats
    /// rather than silently resynchronizing onto garbage: the caller's job is to drop
    /// the connection, not to retry.
    public mutating func nextBody() throws -> Data? {
        guard buffer.count >= FrameCodec.headerSize else { return nil }

        let length = (UInt32(buffer[0]) << 24)
            | (UInt32(buffer[1]) << 16)
            | (UInt32(buffer[2]) << 8)
            | UInt32(buffer[3])

        guard length > 0 else { throw ProtocolError.invalidFrameLength(length) }
        guard length <= UInt32(clamping: maxFrameBytes) else {
            throw ProtocolError.frameTooLarge(byteCount: Int(length))
        }

        let total = FrameCodec.headerSize + Int(length)
        guard buffer.count >= total else { return nil }

        let body = Data(buffer[FrameCodec.headerSize..<total])
        buffer.removeFirst(total)
        return body
    }

    /// The next complete envelope, or nil when more bytes are needed.
    public mutating func nextEnvelope(using decoder: JSONDecoder? = nil) throws -> Envelope? {
        guard let body = try nextBody() else { return nil }
        return try FrameCodec.decode(body: body, using: decoder)
    }

    /// Drains every envelope currently available.
    ///
    /// A frame that fails to *decode* — unknown message type from a newer peer, say —
    /// has already been consumed, so the stream stays synchronized. Those errors are
    /// reported alongside the good envelopes rather than thrown, letting a caller skip
    /// what it doesn't understand. Framing errors still throw, because past one of
    /// those there is nothing left to read.
    public mutating func drain(using decoder: JSONDecoder? = nil) throws -> (envelopes: [Envelope], errors: [ProtocolError]) {
        var envelopes: [Envelope] = []
        var errors: [ProtocolError] = []

        while let body = try nextBody() {
            do {
                envelopes.append(try FrameCodec.decode(body: body, using: decoder))
            } catch let error as ProtocolError {
                errors.append(error)
            } catch {
                errors.append(.unsupportedMessageType("<malformed>"))
            }
        }
        return (envelopes, errors)
    }

    /// Forgets any partial frame. For use after a reconnect, when the old stream's
    /// leftovers must not be spliced onto the new one.
    public mutating func reset() {
        buffer.removeAll(keepingCapacity: true)
    }
}

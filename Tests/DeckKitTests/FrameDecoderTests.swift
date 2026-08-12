import Foundation
import XCTest
@testable import DeckKit

final class FrameDecoderTests: XCTestCase {
    func testSingleFrameRoundTrips() throws {
        let envelope = Envelope(message: .ping)
        var decoder = FrameDecoder()
        decoder.append(try FrameCodec.encode(envelope))

        XCTAssertEqual(try decoder.nextEnvelope(), envelope)
        XCTAssertNil(try decoder.nextEnvelope())
        XCTAssertEqual(decoder.bufferedByteCount, 0)
    }

    func testEmptyBufferYieldsNothing() throws {
        var decoder = FrameDecoder()
        XCTAssertNil(try decoder.nextBody())
    }

    func testPartialHeaderYieldsNothing() throws {
        var decoder = FrameDecoder()
        decoder.append(Data([0x00, 0x00]))
        XCTAssertNil(try decoder.nextBody())
        XCTAssertEqual(decoder.bufferedByteCount, 2)
    }

    func testPartialBodyYieldsNothingThenCompletes() throws {
        let envelope = Envelope(message: .pong)
        let frame = try FrameCodec.encode(envelope)

        var decoder = FrameDecoder()
        decoder.append(frame.prefix(frame.count - 1))
        XCTAssertNil(try decoder.nextEnvelope())

        decoder.append(frame.suffix(1))
        XCTAssertEqual(try decoder.nextEnvelope(), envelope)
    }

    func testCoalescedFramesAreSplitApart() throws {
        let envelopes = SampleMessages.allEnvelopes
        var stream = Data()
        for envelope in envelopes {
            stream.append(try FrameCodec.encode(envelope))
        }

        var decoder = FrameDecoder()
        decoder.append(stream)

        let drained = try decoder.drain()
        XCTAssertEqual(drained.errors, [])
        XCTAssertEqual(drained.envelopes, envelopes)
        XCTAssertEqual(decoder.bufferedByteCount, 0)
    }

    func testByteAtATimeDeliveryReassemblesEveryFrame() throws {
        let envelopes = SampleMessages.allEnvelopes
        var stream = Data()
        for envelope in envelopes {
            stream.append(try FrameCodec.encode(envelope))
        }

        var decoder = FrameDecoder()
        var received: [Envelope] = []
        for byte in stream {
            decoder.append(Data([byte]))
            while let envelope = try decoder.nextEnvelope() {
                received.append(envelope)
            }
        }
        XCTAssertEqual(received, envelopes)
    }

    /// The fuzz-ish case M1 calls for: the same stream chopped at arbitrary, seeded
    /// boundaries must always reassemble into exactly the frames that went in.
    func testRandomSplitsAlwaysReassemble() throws {
        let envelopes = SampleMessages.allEnvelopes
        var stream = Data()
        for envelope in envelopes {
            stream.append(try FrameCodec.encode(envelope))
        }

        for seed in UInt64(1)...50 {
            var generator = SeededGenerator(seed: seed)
            var decoder = FrameDecoder()
            var received: [Envelope] = []
            var offset = 0

            while offset < stream.count {
                let remaining = stream.count - offset
                let chunk = Int.random(in: 1...max(1, min(37, remaining)), using: &generator)
                let start = stream.startIndex + offset
                decoder.append(stream[start..<(start + chunk)])
                offset += chunk

                while let envelope = try decoder.nextEnvelope() {
                    received.append(envelope)
                }
            }

            XCTAssertEqual(received, envelopes, "seed \(seed) lost or reordered frames")
            XCTAssertEqual(decoder.bufferedByteCount, 0, "seed \(seed) left bytes behind")
        }
    }

    func testZeroLengthFrameIsRejected() {
        var decoder = FrameDecoder()
        decoder.append(Data([0x00, 0x00, 0x00, 0x00]))

        XCTAssertThrowsError(try decoder.nextBody()) { error in
            XCTAssertEqual(error as? ProtocolError, .invalidFrameLength(0))
            XCTAssertEqual((error as? ProtocolError)?.isRecoverable, false)
        }
    }

    func testOversizedLengthIsRejectedWithoutAllocating() {
        var decoder = FrameDecoder(maxFrameBytes: 1024)
        // Claims 16 MiB while only four bytes have actually arrived.
        decoder.append(Data([0x01, 0x00, 0x00, 0x00]))

        XCTAssertThrowsError(try decoder.nextBody()) { error in
            XCTAssertEqual(error as? ProtocolError, .frameTooLarge(byteCount: 16_777_216))
        }
    }

    func testFramingErrorsRepeatRatherThanResynchronize() {
        var decoder = FrameDecoder()
        decoder.append(Data([0x00, 0x00, 0x00, 0x00, 0x7B, 0x7D]))

        XCTAssertThrowsError(try decoder.nextBody())
        // Still throwing, still holding the bytes: the caller must drop the connection
        // rather than hope the stream recovers.
        XCTAssertThrowsError(try decoder.nextBody())
        XCTAssertEqual(decoder.bufferedByteCount, 6)
    }

    func testGarbageBodyIsReportedButKeepsTheStreamSynchronized() throws {
        var stream = Data()
        let garbage = Data("not json at all".utf8)
        var header = UInt32(garbage.count).bigEndian
        withUnsafeBytes(of: &header) { stream.append(contentsOf: $0) }
        stream.append(garbage)

        let good = Envelope(message: .ping)
        stream.append(try FrameCodec.encode(good))

        var decoder = FrameDecoder()
        decoder.append(stream)

        let drained = try decoder.drain()
        XCTAssertEqual(drained.errors.count, 1)
        XCTAssertEqual(drained.envelopes, [good], "a bad frame must not swallow the next one")
    }

    func testResetDropsAPartialFrame() throws {
        let frame = try FrameCodec.encode(Envelope(message: .ping))
        var decoder = FrameDecoder()
        decoder.append(frame.prefix(3))
        decoder.reset()
        XCTAssertEqual(decoder.bufferedByteCount, 0)

        decoder.append(frame)
        XCTAssertNotNil(try decoder.nextEnvelope())
    }

    func testEncodedFrameCarriesABigEndianLengthPrefix() throws {
        let frame = try FrameCodec.encode(Envelope(message: .ping))
        let bytes = Array(frame)
        let declared = (UInt32(bytes[0]) << 24) |
            (UInt32(bytes[1]) << 16) |
            (UInt32(bytes[2]) << 8) |
            UInt32(bytes[3])

        XCTAssertEqual(Int(declared), frame.count - FrameCodec.headerSize)
    }
}

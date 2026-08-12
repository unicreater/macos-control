import Foundation
import XCTest
@testable import DeckKit

final class EnvelopeCodingTests: XCTestCase {
    func testEveryMessageTypeRoundTrips() throws {
        for type in MessageType.allCases {
            let original = Envelope(message: SampleMessages.message(for: type))
            let data = try FrameCodec.makeEncoder().encode(original)
            let decoded = try FrameCodec.makeDecoder().decode(Envelope.self, from: data)
            XCTAssertEqual(decoded, original, "round trip changed \(type.rawValue)")
            XCTAssertEqual(decoded.type, type)
        }
    }

    func testWireShapeIsFlatWithVersionIDAndType() throws {
        let envelope = Envelope(message: .pairRequest(PairRequest(pin: PairingPIN("482913")!)))
        let data = try FrameCodec.makeEncoder().encode(envelope)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(json["v"] as? Int, DeckKitVersion.wireProtocol)
        XCTAssertEqual(json["type"] as? String, "pairRequest")
        XCTAssertNotNil(json["id"] as? String)
        let payload = try XCTUnwrap(json["payload"] as? [String: Any])
        XCTAssertEqual(payload["pin"] as? String, "482913")
    }

    func testPayloadlessMessagesOmitThePayloadKey() throws {
        for message in [Message.ping, .pong, .shortcutsRequest] {
            let data = try FrameCodec.makeEncoder().encode(Envelope(message: message))
            let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
            XCTAssertNil(json["payload"], "\(message.type.rawValue) should carry no payload")
        }
    }

    func testUnknownMessageTypeIsARecoverableProtocolError() throws {
        let json = #"{"v":1,"id":"E621E1F8-C36C-495A-93FC-0C247A3E6E5F","type":"teleport"}"#
        let data = Data(json.utf8)

        XCTAssertThrowsError(try FrameCodec.makeDecoder().decode(Envelope.self, from: data)) { error in
            guard let error = error as? ProtocolError else {
                return XCTFail("expected a ProtocolError, got \(error)")
            }
            XCTAssertEqual(error, .unsupportedMessageType("teleport"))
            XCTAssertTrue(error.isRecoverable)
        }
    }

    func testMissingPayloadIsReportedAsSuch() throws {
        let json = #"{"v":1,"id":"E621E1F8-C36C-495A-93FC-0C247A3E6E5F","type":"pairRequest"}"#
        let data = Data(json.utf8)

        XCTAssertThrowsError(try FrameCodec.makeDecoder().decode(Envelope.self, from: data)) { error in
            XCTAssertEqual(error as? ProtocolError, .missingPayload(.pairRequest))
        }
    }

    func testReplyReusesTheRequestID() {
        let request = Envelope(message: .action(ActionRequest(kind: .quitApp, target: "com.apple.Safari")))
        let reply = request.reply(.actionResult(.success(requestID: request.id)))
        XCTAssertEqual(reply.id, request.id)
    }

    func testIconPNGDataSurvivesTheWire() throws {
        let png = Data((0...255).map { UInt8($0) })
        let envelope = Envelope(message: .icon(IconResponse(hash: "h", png: png)))
        let data = try FrameCodec.makeEncoder().encode(envelope)
        let decoded = try FrameCodec.makeDecoder().decode(Envelope.self, from: data)

        guard case .icon(let response) = decoded.message else {
            return XCTFail("expected an icon message")
        }
        XCTAssertEqual(response.png, png)
    }
}

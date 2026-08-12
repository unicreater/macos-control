import Foundation
import XCTest
@testable import DeckKit

final class DeckKitVersionTests: XCTestCase {
    func testWireProtocolVersionIsPositive() {
        XCTAssertGreaterThan(DeckKitVersion.wireProtocol, 0)
    }

    func testPackageVersionIsNotEmpty() {
        XCTAssertFalse(DeckKitVersion.package.isEmpty)
    }
}

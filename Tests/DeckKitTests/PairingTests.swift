import Foundation
import XCTest
@testable import DeckKit

final class PairingPINTests: XCTestCase {
    func testAcceptsExactlySixDigits() {
        XCTAssertEqual(PairingPIN("482913")?.digits, "482913")
        XCTAssertEqual(PairingPIN("000000")?.digits, "000000")
    }

    func testToleratesSurroundingWhitespace() {
        XCTAssertEqual(PairingPIN("  482913\n")?.digits, "482913")
    }

    func testRejectsAnythingElse() {
        XCTAssertNil(PairingPIN(""))
        XCTAssertNil(PairingPIN("48291"))
        XCTAssertNil(PairingPIN("4829134"))
        XCTAssertNil(PairingPIN("48a913"))
        XCTAssertNil(PairingPIN("48 913"))
        XCTAssertNil(PairingPIN("４８２９１３"), "full-width digits are not ASCII digits")
    }

    func testRandomPINsAreAlwaysValidAndSixDigits() {
        var generator = SeededGenerator(seed: 99)
        for _ in 0..<500 {
            let pin = PairingPIN.random(using: &generator)
            XCTAssertEqual(pin.digits.count, PairingPIN.length)
            XCTAssertNotNil(PairingPIN(pin.digits))
        }
    }

    func testCharactersFeedTheSixDigitCells() {
        XCTAssertEqual(PairingPIN("482913")?.characters, ["4", "8", "2", "9", "1", "3"])
    }
}

final class TrustStoreTests: XCTestCase {
    private let mac = DeviceIdentity(deviceID: "MAC-1", name: "Nora's MacBook", publicKeyHash: "key-a")

    func testUnknownDeviceIsUnknown() {
        XCTAssertEqual(TrustStore().evaluate(mac), .unknown)
        XCTAssertTrue(TrustStore().hasNeverPaired)
    }

    func testPinnedDeviceIsTrusted() {
        var store = TrustStore()
        store.pin(mac)
        XCTAssertEqual(store.evaluate(mac), .trusted)
        XCTAssertFalse(store.hasNeverPaired)
    }

    /// FR-3: a different machine presenting the same name — and even the same device ID
    /// — is never silently trusted.
    func testSameDeviceIDWithADifferentKeyIsAnIdentityChange() {
        var store = TrustStore()
        store.pin(mac)

        let impostor = DeviceIdentity(deviceID: "MAC-1", name: "Nora's MacBook", publicKeyHash: "key-b")
        XCTAssertEqual(store.evaluate(impostor), .identityChanged(pinnedKeyHash: "key-a", presentedKeyHash: "key-b"))
        XCTAssertFalse(store.isTrusted(impostor))
    }

    func testRenamingAMacDoesNotBreakTrust() {
        var store = TrustStore()
        store.pin(mac)
        let renamed = DeviceIdentity(deviceID: "MAC-1", name: "The Studio Mac", publicKeyHash: "key-a")
        XCTAssertEqual(store.evaluate(renamed), .trusted)
    }

    func testForgettingRequiresPairingAgain() {
        var store = TrustStore()
        store.pin(mac)
        XCTAssertTrue(store.forget(deviceID: mac.deviceID))
        XCTAssertEqual(store.evaluate(mac), .unknown)
        XCTAssertFalse(store.forget(deviceID: mac.deviceID))
    }

    func testTrustStoreRoundTrips() throws {
        var store = TrustStore()
        store.pin(mac)
        let decoded = try JSONDecoder().decode(TrustStore.self, from: JSONEncoder().encode(store))
        XCTAssertEqual(decoded, store)
        XCTAssertEqual(decoded.pairedDeviceIDs, ["MAC-1"])
    }
}

final class PairingMachineTests: XCTestCase {
    private let mac = DeviceIdentity(deviceID: "MAC-1", name: "Nora's MacBook", publicKeyHash: "key-a")

    func testUnknownDeviceGoesToThePINScreen() {
        var machine = PairingMachine()
        machine.handle(.beginDiscovery)
        XCTAssertEqual(machine.state, .discovering)

        machine.handle(.deviceSelected(mac))
        XCTAssertEqual(machine.state, .awaitingPIN(mac))
        XCTAssertTrue(machine.isAcceptingPIN)
        XCTAssertNil(machine.attemptsLeft, "no counter is shown until something fails")
    }

    /// FR-2: force-quitting and relaunching both apps reconnects with no PIN prompt.
    func testAlreadyPairedDeviceSkipsThePIN() {
        var store = TrustStore()
        store.pin(mac)
        var machine = PairingMachine(trust: store)

        machine.handle(.deviceSelected(mac))
        XCTAssertEqual(machine.state, .paired(mac))
        XCTAssertTrue(machine.isPaired)
    }

    func testCorrectPINPairsAndPinsTheKey() {
        var machine = PairingMachine()
        machine.handle(.deviceSelected(mac))
        machine.handle(.pairAccepted(mac))

        XCTAssertEqual(machine.state, .paired(mac))
        XCTAssertTrue(machine.trust.isTrusted(mac))
    }

    /// FR-2: a wrong PIN is rejected with an error and stores no trust.
    func testWrongPINStoresNoTrustAndCountsDown() {
        var machine = PairingMachine()
        machine.handle(.deviceSelected(mac))

        machine.handle(.pairRejected)
        XCTAssertEqual(machine.state, .pairingError(mac, attemptsLeft: 2))
        XCTAssertEqual(machine.attemptsLeft, 2, "matches the designed 'Wrong PIN — 2 tries left'")
        XCTAssertTrue(machine.trust.hasNeverPaired)
        XCTAssertTrue(machine.isAcceptingPIN, "the flow never resets — the user stays put")

        machine.handle(.pairRejected)
        XCTAssertEqual(machine.state, .pairingError(mac, attemptsLeft: 1))
        XCTAssertEqual(machine.device, mac, "the screen keeps naming the Mac")
    }

    func testExhaustingAttemptsReturnsToTheDeviceList() {
        var machine = PairingMachine()
        machine.handle(.deviceSelected(mac))
        for _ in 0..<PairingMachine.maxAttempts {
            machine.handle(.pairRejected)
        }
        XCTAssertEqual(machine.state, .discovering)
        XCTAssertTrue(machine.trust.hasNeverPaired)
    }

    func testRecoveringFromAWrongPINStillPairs() {
        var machine = PairingMachine()
        machine.handle(.deviceSelected(mac))
        machine.handle(.pairRejected)
        machine.handle(.pairAccepted(mac))

        XCTAssertEqual(machine.state, .paired(mac))
        XCTAssertTrue(machine.trust.isTrusted(mac))
    }

    /// FR-3: a reinstalled Mac is shown as unpaired and prompts for the PIN again,
    /// but only after a deliberate confirmation.
    func testIdentityChangeRequiresADeliberateRePair() {
        var store = TrustStore()
        store.pin(mac)
        var machine = PairingMachine(trust: store)

        let reinstalled = DeviceIdentity(deviceID: "MAC-1", name: "Nora's MacBook", publicKeyHash: "key-b")
        machine.handle(.deviceSelected(reinstalled))
        XCTAssertEqual(machine.state, .identityChanged(reinstalled))
        XCTAssertFalse(machine.isAcceptingPIN, "no PIN entry until the user confirms")
        XCTAssertTrue(machine.trust.isTrusted(mac), "the old key stays pinned until then")

        machine.handle(.rePairConfirmed)
        XCTAssertEqual(machine.state, .awaitingPIN(reinstalled))
        XCTAssertEqual(machine.trust.evaluate(reinstalled), .unknown, "the stale key is dropped")
    }

    func testCancellingAnIdentityChangeLeavesTrustAlone() {
        var store = TrustStore()
        store.pin(mac)
        var machine = PairingMachine(trust: store)

        machine.handle(.deviceSelected(DeviceIdentity(deviceID: "MAC-1", name: "M", publicKeyHash: "key-b")))
        machine.handle(.cancelled)

        XCTAssertEqual(machine.state, .discovering)
        XCTAssertTrue(machine.trust.isTrusted(mac))
    }

    func testCancellingFromThePINScreenReturnsToDiscovery() {
        var machine = PairingMachine()
        machine.handle(.deviceSelected(mac))
        machine.handle(.cancelled)
        XCTAssertEqual(machine.state, .discovering)
    }

    /// FR-5: after unpairing, connecting again requires the PIN.
    func testUnpairingDropsTrustAndTheSession() {
        var machine = PairingMachine()
        machine.handle(.deviceSelected(mac))
        machine.handle(.pairAccepted(mac))

        machine.handle(.unpaired(deviceID: mac.deviceID))
        XCTAssertEqual(machine.state, .unpaired)

        machine.handle(.deviceSelected(mac))
        XCTAssertEqual(machine.state, .awaitingPIN(mac))
    }

    func testUnpairingADifferentMacLeavesThisSessionAlone() {
        var machine = PairingMachine()
        machine.handle(.deviceSelected(mac))
        machine.handle(.pairAccepted(mac))

        machine.handle(.unpaired(deviceID: "SOME-OTHER-MAC"))
        XCTAssertEqual(machine.state, .paired(mac))
    }

    func testRejectionOutsideThePINFlowIsIgnored() {
        var machine = PairingMachine()
        machine.handle(.beginDiscovery)
        machine.handle(.pairRejected)
        XCTAssertEqual(machine.state, .discovering)
    }
}

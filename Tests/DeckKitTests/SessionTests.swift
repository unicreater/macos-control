import Foundation
import XCTest
@testable import DeckKit

final class SessionMachineTests: XCTestCase {
    private func connected() -> SessionMachine {
        var machine = SessionMachine()
        machine.handle(.connectAttemptStarted)
        machine.handle(.handshakeCompleted)
        return machine
    }

    func testFirstAttemptConnectsRatherThanReconnects() {
        var machine = SessionMachine()
        XCTAssertEqual(machine.state, .disconnected)

        machine.handle(.connectAttemptStarted)
        XCTAssertEqual(machine.state, .connecting)
        XCTAssertTrue(machine.state.isEstablishing)
        XCTAssertFalse(machine.acceptsActions)
    }

    func testHandshakeGoesLive() {
        let machine = connected()
        XCTAssertEqual(machine.state, .connected(latencyMs: 0))
        XCTAssertTrue(machine.state.isLive)
        XCTAssertTrue(machine.acceptsActions)
    }

    func testPongCarriesLatencyToTheTopBar() {
        var machine = connected()
        machine.handle(.pongReceived(latencyMs: 12))
        XCTAssertEqual(machine.state, .connected(latencyMs: 12))
        XCTAssertEqual(machine.state.latencyMs, 12)
    }

    func testNegativeLatencyIsClamped() {
        var machine = connected()
        machine.handle(.pongReceived(latencyMs: -5))
        XCTAssertEqual(machine.state.latencyMs, 0)
    }

    /// PRD §5: 10s keepalive, two misses and the link is presumed dead.
    func testTwoMissedPongsTripReconnect() {
        var machine = connected()

        machine.handle(.pingSent)
        XCTAssertEqual(machine.state, .connected(latencyMs: 0), "one miss is not enough")
        XCTAssertEqual(machine.pingsOutstanding, 1)

        machine.handle(.pingSent)
        XCTAssertEqual(machine.state, .reconnecting)
        XCTAssertFalse(machine.acceptsActions)
    }

    func testAPongResetsTheMissCounter() {
        var machine = connected()
        machine.handle(.pingSent)
        machine.handle(.pongReceived(latencyMs: 8))
        XCTAssertEqual(machine.pingsOutstanding, 0)

        machine.handle(.pingSent)
        XCTAssertEqual(machine.state, .connected(latencyMs: 8), "the counter restarted")
    }

    func testALatePongRecoversFromReconnecting() {
        var machine = connected()
        machine.handle(.pingSent)
        machine.handle(.pingSent)
        XCTAssertEqual(machine.state, .reconnecting)

        machine.handle(.pongReceived(latencyMs: 30))
        XCTAssertEqual(machine.state, .connected(latencyMs: 30))
    }

    func testPingsWhileNotLiveAreIgnored() {
        var machine = SessionMachine()
        machine.handle(.pingSent)
        machine.handle(.pingSent)
        XCTAssertEqual(machine.state, .disconnected)
        XCTAssertEqual(machine.pingsOutstanding, 0)
    }

    /// FR-4: the link drops, the deck shows a reconnecting state and resumes without
    /// the user touching anything.
    func testDroppedTransportReconnectsWithoutUserAction() {
        var machine = connected()
        machine.handle(.transportFailed)

        XCTAssertEqual(machine.state, .reconnecting)
        XCTAssertEqual(machine.reconnectAttempt, 1)
        XCTAssertTrue(machine.state.isInert, "tiles stay visible but inert")

        machine.handle(.connectAttemptStarted)
        XCTAssertEqual(machine.state, .reconnecting, "not 'connecting' — this link has been up before")

        machine.handle(.handshakeCompleted)
        XCTAssertEqual(machine.state, .connected(latencyMs: 0))
        XCTAssertEqual(machine.reconnectAttempt, 0)
    }

    func testFailureBeforeEverConnectingFailsLoudly() {
        var machine = SessionMachine()
        machine.handle(.connectAttemptStarted)
        machine.handle(.transportFailed)
        XCTAssertEqual(machine.state, .disconnected, "the user is still in the pairing flow")
    }

    func testRepeatedFailuresAdvanceTheBackoffCounter() {
        var machine = connected()
        machine.handle(.transportFailed)
        machine.handle(.connectAttemptStarted)
        machine.handle(.transportFailed)
        machine.handle(.connectAttemptStarted)
        machine.handle(.transportFailed)
        XCTAssertEqual(machine.reconnectAttempt, 3)
    }

    /// Losing Wi-Fi entirely is the red-banner state, not the amber one — there is
    /// nothing to retry against until the network is back.
    func testLosingTheNetworkDisconnectsRatherThanReconnects() {
        var machine = connected()
        machine.handle(.reachabilityLost)
        XCTAssertEqual(machine.state, .disconnected)

        machine.handle(.reachabilityRestored)
        XCTAssertEqual(machine.state, .reconnecting)
        XCTAssertEqual(machine.reconnectAttempt, 0, "a fresh network deserves an immediate try")
    }

    func testReachabilityRestoredWhileLiveChangesNothing() {
        var machine = connected()
        machine.handle(.pongReceived(latencyMs: 5))
        machine.handle(.reachabilityRestored)
        XCTAssertEqual(machine.state, .connected(latencyMs: 5))
    }

    func testDisconnectRequestedResetsEverything() {
        var machine = connected()
        machine.handle(.pingSent)
        machine.handle(.transportFailed)
        machine.handle(.disconnectRequested)

        XCTAssertEqual(machine.state, .disconnected)
        XCTAssertEqual(machine.reconnectAttempt, 0)
        XCTAssertEqual(machine.pingsOutstanding, 0)
    }
}

final class ReconnectPolicyTests: XCTestCase {
    /// Jitter at the midpoint draw is a no-op, which makes the underlying curve visible.
    private let midpoint = 0.5

    func testBackoffGrowsExponentially() {
        let policy = ReconnectPolicy.default
        XCTAssertEqual(policy.delay(forAttempt: 0, randomUnit: midpoint), 0.5, accuracy: 0.0001)
        XCTAssertEqual(policy.delay(forAttempt: 1, randomUnit: midpoint), 1.0, accuracy: 0.0001)
        XCTAssertEqual(policy.delay(forAttempt: 2, randomUnit: midpoint), 2.0, accuracy: 0.0001)
        XCTAssertEqual(policy.delay(forAttempt: 3, randomUnit: midpoint), 4.0, accuracy: 0.0001)
    }

    /// FR-4 gives five seconds from reachability to a live deck, so no backoff step may
    /// ever exceed that — however long the Mac was away.
    func testDelayNeverExceedsFiveSeconds() {
        let policy = ReconnectPolicy.default
        for attempt in 0...200 {
            for unit in [0.0, 0.25, 0.5, 0.75, 1.0] {
                let delay = policy.delay(forAttempt: attempt, randomUnit: unit)
                XCTAssertLessThanOrEqual(delay, policy.maximumDelay, "attempt \(attempt), unit \(unit)")
                XCTAssertGreaterThanOrEqual(delay, 0)
            }
        }
    }

    func testJitterSpreadsEitherSideOfTheBase() {
        let policy = ReconnectPolicy.default
        let low = policy.delay(forAttempt: 1, randomUnit: 0)
        let high = policy.delay(forAttempt: 1, randomUnit: 1)

        XCTAssertEqual(low, 0.8, accuracy: 0.0001)
        XCTAssertEqual(high, 1.2, accuracy: 0.0001)
    }

    func testOutOfRangeRandomUnitsAreClamped() {
        let policy = ReconnectPolicy.default
        XCTAssertEqual(policy.delay(forAttempt: 1, randomUnit: -3), policy.delay(forAttempt: 1, randomUnit: 0))
        XCTAssertEqual(policy.delay(forAttempt: 1, randomUnit: 7), policy.delay(forAttempt: 1, randomUnit: 1))
    }

    func testNegativeAttemptsAreTreatedAsTheFirst() {
        let policy = ReconnectPolicy.default
        XCTAssertEqual(
            policy.delay(forAttempt: -4, randomUnit: midpoint),
            policy.delay(forAttempt: 0, randomUnit: midpoint)
        )
    }

    func testSessionMachineFeedsItsAttemptCountToThePolicy() {
        var machine = SessionMachine()
        machine.handle(.connectAttemptStarted)
        machine.handle(.handshakeCompleted)
        machine.handle(.transportFailed)

        XCTAssertEqual(machine.reconnectAttempt, 1)
        XCTAssertEqual(machine.nextRetryDelay(randomUnit: 0.5), 1.0, accuracy: 0.0001)
    }
}

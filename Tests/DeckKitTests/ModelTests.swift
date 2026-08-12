import Foundation
import XCTest
@testable import DeckKit

final class MacStateTests: XCTestCase {
    private let state = MacState(
        running: ["com.apple.Safari", "com.apple.dt.Xcode"],
        frontmost: "com.apple.Safari",
        recents: ["com.apple.Safari", "com.apple.dt.Xcode", "com.apple.Notes"]
    )

    /// The keycap state table: frontmost outranks running, running outranks idle.
    func testFrontmostOutranksRunning() {
        XCTAssertEqual(state.tileState(for: .app(bundleID: "com.apple.Safari")), .frontmost)
        XCTAssertEqual(state.tileState(for: .app(bundleID: "com.apple.dt.Xcode")), .running)
        XCTAssertEqual(state.tileState(for: .app(bundleID: "com.apple.Mail")), .idle)
    }

    func testNonAppTilesHaveNoLiveState() {
        XCTAssertEqual(state.tileState(for: .shortcut(name: "Ship It")), .idle)
        XCTAssertEqual(state.tileState(for: .website(url: "https://example.com")), .idle)
    }

    func testUnknownStateLightsNothingUp() {
        XCTAssertEqual(MacState.unknown.tileState(for: .app(bundleID: "com.apple.Safari")), .idle)
        XCTAssertTrue(MacState.unknown.visibleRecents.isEmpty)
    }

    func testRecentsColumnShowsFour() {
        var state = MacState()
        for index in 1...10 {
            state.recordActivation(of: "app\(index)")
        }
        XCTAssertEqual(state.visibleRecents, ["app10", "app9", "app8", "app7"])
    }

    /// FR-16: most recent first, deduplicated.
    func testReactivatingAnAppMovesItToTheFrontWithoutDuplicating() {
        var state = MacState()
        state.recordActivation(of: "a")
        state.recordActivation(of: "b")
        state.recordActivation(of: "a")

        XCTAssertEqual(state.recents, ["a", "b"])
    }

    func testHistoryIsCappedSoItCannotGrowForever() {
        var state = MacState()
        for index in 1...50 {
            state.recordActivation(of: "app\(index)")
        }
        XCTAssertEqual(state.recents.count, 8)
    }

    func testRoundTripsThroughJSON() throws {
        let decoded = try JSONDecoder().decode(MacState.self, from: JSONEncoder().encode(state))
        XCTAssertEqual(decoded, state)
    }
}

final class AppCatalogTests: XCTestCase {
    private let apps = [
        AppCatalogEntry(bundleID: "com.apple.dt.Xcode", name: "Xcode"),
        AppCatalogEntry(bundleID: "com.apple.Safari", name: "Safari"),
        AppCatalogEntry(bundleID: "com.tinyspeck.slackmacgap", name: "Slack"),
        AppCatalogEntry(bundleID: "com.apple.SafariTechnologyPreview", name: "Safari Technology Preview")
    ]

    /// FR-8's acceptance criterion, exactly: searching "saf" lists Safari.
    func testSearchingSafListsSafari() {
        let results = apps.searching("saf")
        XCTAssertEqual(results.first?.name, "Safari")
        XCTAssertEqual(results.map(\.name), ["Safari", "Safari Technology Preview"])
    }

    func testSearchIsCaseInsensitive() {
        XCTAssertEqual(apps.searching("XCODE").map(\.name), ["Xcode"])
    }

    func testSearchMatchesBundleIDsToo() {
        XCTAssertEqual(apps.searching("tinyspeck").map(\.name), ["Slack"])
    }

    func testNamePrefixMatchesOutrankMerelyContaining() {
        let apps = [
            AppCatalogEntry(bundleID: "com.example.a", name: "Ultra Notes"),
            AppCatalogEntry(bundleID: "com.example.b", name: "Notes")
        ]
        XCTAssertEqual(apps.searching("notes").map(\.name), ["Notes", "Ultra Notes"])
    }

    func testEmptyQueryReturnsEverythingAlphabetically() {
        XCTAssertEqual(
            apps.searching("  ").map(\.name),
            ["Safari", "Safari Technology Preview", "Slack", "Xcode"]
        )
    }

    func testNoMatchesIsEmptyRatherThanEverything() {
        XCTAssertTrue(apps.searching("zzzz").isEmpty)
    }
}

final class TileTargetTests: XCTestCase {
    func testKindAndValueSurviveTheWire() throws {
        let targets: [TileTarget] = [
            .app(bundleID: "com.apple.Safari"),
            .shortcut(name: "Ship It"),
            .website(url: "https://example.com/dash")
        ]
        for target in targets {
            let decoded = try JSONDecoder().decode(TileTarget.self, from: JSONEncoder().encode(target))
            XCTAssertEqual(decoded, target)
            XCTAssertEqual(decoded.kind, target.kind)
        }
    }

    func testEncodedShapeIsKindAndValue() throws {
        let data = try JSONEncoder().encode(TileTarget.app(bundleID: "com.apple.Safari"))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: String])
        XCTAssertEqual(json, ["kind": "app", "value": "com.apple.Safari"])
    }

    /// The website tab validates inline; ADD dims rather than disappears (design S6).
    func testWebsiteValidationAcceptsHTTPAndHTTPS() {
        XCTAssertTrue(TileTarget.isValidWebsiteURL("https://example.com"))
        XCTAssertTrue(TileTarget.isValidWebsiteURL("http://example.com/a/b?c=d"))
        XCTAssertTrue(TileTarget.isValidWebsiteURL("  https://example.com  "))
        XCTAssertTrue(TileTarget.isValidWebsiteURL("HTTPS://EXAMPLE.COM"))
    }

    func testWebsiteValidationRejectsEverythingElse() {
        XCTAssertFalse(TileTarget.isValidWebsiteURL(""))
        XCTAssertFalse(TileTarget.isValidWebsiteURL("example.com"), "a bare host has no scheme")
        XCTAssertFalse(TileTarget.isValidWebsiteURL("ftp://example.com"))
        XCTAssertFalse(TileTarget.isValidWebsiteURL("file:///etc/passwd"))
        XCTAssertFalse(TileTarget.isValidWebsiteURL("https://"), "no host")
    }

    func testTapOnATileBecomesTheRightAction() {
        XCTAssertEqual(ActionRequest(activating: .app(bundleID: "com.apple.Safari")).kind, .activateApp)
        XCTAssertEqual(ActionRequest(activating: .shortcut(name: "Ship It")).kind, .runShortcut)
        XCTAssertEqual(ActionRequest(activating: .website(url: "https://x.com")).kind, .openURL)
        XCTAssertEqual(ActionRequest(activating: .shortcut(name: "Ship It")).target, "Ship It")
    }
}

final class EntitlementAndPermissionTests: XCTestCase {
    func testTierLimits() {
        XCTAssertEqual(Entitlement.free.maxPages, 2)
        XCTAssertEqual(Entitlement.premium.maxPages, 8)
        XCTAssertFalse(Entitlement.free.unlocksRecentsColumn)
        XCTAssertTrue(Entitlement.premium.unlocksRecentsColumn)
    }

    /// FR-24: every permission ask states its degraded path — and local network is the
    /// one that honestly has none.
    func testOnlyLocalNetworkIsRequired() {
        XCTAssertTrue(PermissionKind.localNetwork.isRequired)
        XCTAssertNil(PermissionKind.localNetwork.degradedPath)
        XCTAssertNotNil(PermissionKind.automation.degradedPath)
        XCTAssertNotNil(PermissionKind.accessibility.degradedPath)
    }

    func testPermissionSubscriptReadsAndWrites() {
        var state = PermissionState()
        XCTAssertEqual(state[.automation], .notDetermined)

        state[.automation] = .denied
        XCTAssertEqual(state.automation, .denied)
        XCTAssertEqual(state[.automation], .denied)
    }

    /// The "2 of 3 granted" row in Settings (design S7).
    func testPermissionSummaryCounts() {
        var state = PermissionState()
        state[.localNetwork] = .granted
        state[.automation] = .granted
        state[.accessibility] = .denied

        XCTAssertEqual(state.grantedCount, 2)
        XCTAssertEqual(state.summary, "2 of 3 granted")
    }

    /// Enum-keyed dictionaries serialize as flat arrays; the named fields are what keep
    /// the persisted shape a real JSON object.
    func testPermissionStateRoundTripsAsAnObject() throws {
        var state = PermissionState()
        state[.localNetwork] = .granted
        let data = try JSONEncoder().encode(state)

        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["localNetwork"] as? String, "granted")
        XCTAssertEqual(try JSONDecoder().decode(PermissionState.self, from: data), state)
    }
}

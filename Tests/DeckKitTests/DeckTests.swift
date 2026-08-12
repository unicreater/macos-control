import Foundation
import XCTest
@testable import DeckKit

final class DeckTests: XCTestCase {
    private func tile(_ name: String) -> Tile {
        Tile(target: .app(bundleID: "com.example.\(name)"), label: name)
    }

    private func fullPage() -> Page {
        Page(tiles: (1...Page.maxTiles).map { tile("app\($0)") })
    }

    // MARK: - The eight-tile cap (FR-6, D15)

    func testPageStopsAtEightTiles() {
        var page = fullPage()
        XCTAssertTrue(page.isFull)
        XCTAssertNil(page.nextFreeSlot)
        XCTAssertFalse(page.append(tile("overflow")))
        XCTAssertEqual(page.tiles.count, Page.maxTiles)
    }

    func testPageInitializerTruncatesRatherThanOverflows() {
        let page = Page(tiles: (1...20).map { tile("app\($0)") })
        XCTAssertEqual(page.tiles.count, Page.maxTiles)
    }

    /// The cap has to survive decoding, not just the initializer — a deck file from a
    /// future or broken build must still open at eight tiles.
    func testDecodingAnOverfullPageTruncates() throws {
        let tiles = try JSONSerialization.jsonObject(
            with: JSONEncoder().encode((1...12).map { tile("app\($0)") })
        )
        let data = try JSONSerialization.data(
            withJSONObject: ["id": UUID().uuidString, "tiles": tiles]
        )

        let page = try JSONDecoder().decode(Page.self, from: data)
        XCTAssertEqual(page.tiles.count, Page.maxTiles)
    }

    func testInsertClampsOutOfRangeSlots() {
        var page = Page(tiles: [tile("a"), tile("b")])
        XCTAssertTrue(page.insert(tile("c"), at: 99))
        XCTAssertEqual(page.tiles.last?.label, "c")
        XCTAssertTrue(page.insert(tile("d"), at: -5))
        XCTAssertEqual(page.tiles.first?.label, "d")
    }

    func testMoveReordersWithinAPage() {
        var page = Page(tiles: [tile("a"), tile("b"), tile("c")])
        page.move(from: 0, to: 2)
        XCTAssertEqual(page.tiles.map(\.label), ["b", "c", "a"])
    }

    func testMoveIgnoresOutOfRangeIndices() {
        var page = Page(tiles: [tile("a"), tile("b")])
        page.move(from: 7, to: 0)
        XCTAssertEqual(page.tiles.map(\.label), ["a", "b"])
    }

    // MARK: - Pages and tiers (FR-17, D16)

    func testFreeTierStopsAtTwoPages() {
        var deck = Deck()
        XCTAssertEqual(deck.pageCount, 1)
        XCTAssertTrue(deck.addPage(for: .free))
        XCTAssertEqual(deck.pageCount, 2)
        // The third page is the paywall, not a dead tap.
        XCTAssertFalse(deck.canAddPage(for: .free))
        XCTAssertFalse(deck.addPage(for: .free))
        XCTAssertEqual(deck.pageCount, 2)
    }

    func testPremiumReachesEightPagesAndStops() {
        var deck = Deck()
        while deck.addPage(for: .premium) {}
        XCTAssertEqual(deck.pageCount, Deck.maxPages)
        XCTAssertFalse(deck.canAddPage(for: .premium))
    }

    func testDeckAlwaysKeepsOnePage() {
        var deck = Deck()
        XCTAssertFalse(deck.removePage(at: 0))
        XCTAssertEqual(deck.pageCount, 1)
    }

    func testDecodingAnEmptyDeckStillYieldsAPage() throws {
        let deck = try JSONDecoder().decode(Deck.self, from: Data(#"{"pages":[]}"#.utf8))
        XCTAssertEqual(deck.pageCount, 1)
    }

    /// Nothing already free is ever locked: a lapsed premium user keeps their pages,
    /// they just can't add more (FR-17).
    func testLapsedPremiumKeepsItsPagesButTheyReadAsLocked() {
        var deck = Deck()
        while deck.addPage(for: .premium) {}
        XCTAssertEqual(deck.pageCount, 8)

        let locked = deck.lockedPageIndices(for: .free)
        XCTAssertEqual(Array(locked), Array(2..<8))
        XCTAssertEqual(deck.pageCount, 8, "pages must never be removed by a downgrade")
    }

    func testLockedPageRangeIsEmptyForPremium() {
        var deck = Deck()
        deck.addPage(for: .premium)
        XCTAssertTrue(deck.lockedPageIndices(for: .premium).isEmpty)
    }

    // MARK: - Slots and moves

    func testNextFreeSlotSkipsFullPages() {
        var deck = Deck(pages: [fullPage(), Page()])
        XCTAssertEqual(deck.nextFreeSlot, DeckSlot(pageIndex: 1, slotIndex: 0))
        XCTAssertEqual(deck.add(tile("new")), DeckSlot(pageIndex: 1, slotIndex: 0))
    }

    func testNextFreeSlotIsNilWhenTheDeckIsFull() {
        let deck = Deck(pages: [fullPage()])
        XCTAssertNil(deck.nextFreeSlot)
    }

    func testSlotHumanReadableMatchesTheAddTileCopy() {
        XCTAssertEqual(
            DeckSlot(pageIndex: 0, slotIndex: 7).humanReadable,
            "Page 1 · slot 8 of 8"
        )
    }

    func testMovingATileAcrossPages() {
        let moving = tile("moving")
        var deck = Deck(pages: [Page(tiles: [tile("a"), moving]), Page()])

        XCTAssertTrue(deck.moveTile(id: moving.id, to: DeckSlot(pageIndex: 1, slotIndex: 0)))
        XCTAssertEqual(deck.pages[0].tiles.map(\.label), ["a"])
        XCTAssertEqual(deck.pages[1].tiles.map(\.label), ["moving"])
    }

    func testMovingIntoAFullPageFailsWithoutLosingTheTile() {
        let moving = tile("moving")
        var deck = Deck(pages: [Page(tiles: [moving]), fullPage()])

        XCTAssertFalse(deck.moveTile(id: moving.id, to: DeckSlot(pageIndex: 1, slotIndex: 0)))
        XCTAssertEqual(deck.pages[0].tiles.count, 1, "the tile must stay where it was")
        XCTAssertEqual(deck.pages[1].tiles.count, Page.maxTiles)
    }

    func testMovingAnUnknownTileIsANoOp() {
        var deck = Deck(pages: [Page(tiles: [tile("a")])])
        XCTAssertFalse(deck.moveTile(id: UUID(), to: DeckSlot(pageIndex: 0, slotIndex: 0)))
    }

    func testRemoveTileFindsItOnAnyPage() {
        let target = tile("target")
        var deck = Deck(pages: [Page(tiles: [tile("a")]), Page(tiles: [target])])

        XCTAssertEqual(deck.removeTile(id: target.id)?.label, "target")
        XCTAssertNil(deck.tile(withID: target.id))
        XCTAssertNil(deck.removeTile(id: target.id))
    }

    func testAppBundleIDsIgnoresShortcutAndWebsiteTiles() {
        let deck = Deck(pages: [Page(tiles: [
            Tile(target: .app(bundleID: "com.apple.Safari"), label: "Safari"),
            Tile(target: .shortcut(name: "Ship It"), label: "Ship", emoji: "🚀"),
            Tile(target: .website(url: "https://example.com"), label: "Docs")
        ])])
        XCTAssertEqual(deck.appBundleIDs, ["com.apple.Safari"])
    }

    // MARK: - Persistence

    func testDeckDocumentRoundTrips() throws {
        let deck = Deck(pages: [Page(tiles: [tile("a"), tile("b")]), Page()])
        let document = DeckDocument(deck: deck)

        let data = try JSONEncoder().encode(document)
        let decoded = try JSONDecoder().decode(DeckDocument.self, from: data)

        XCTAssertEqual(decoded, document)
        XCTAssertEqual(decoded.schemaVersion, DeckDocument.currentSchemaVersion)
        XCTAssertFalse(decoded.isFromFutureSchema)
    }

    /// A reordered layout has to survive relaunch — that is the FR-6 acceptance
    /// criterion, and this is the part of it that can be tested off-device.
    func testReorderedLayoutSurvivesARoundTrip() throws {
        let moved = tile("c")
        var deck = Deck(pages: [Page(tiles: [tile("a"), tile("b"), moved])])
        XCTAssertTrue(deck.moveTile(id: moved.id, to: DeckSlot(pageIndex: 0, slotIndex: 0)))
        let order = deck.pages[0].tiles.map(\.label)

        let data = try JSONEncoder().encode(DeckDocument(deck: deck))
        let decoded = try JSONDecoder().decode(DeckDocument.self, from: data)

        XCTAssertEqual(decoded.deck.pages[0].tiles.map(\.label), order)
        XCTAssertEqual(order, ["c", "a", "b"])
    }

    func testFutureSchemaIsFlagged() {
        let document = DeckDocument(deck: Deck(), schemaVersion: DeckDocument.currentSchemaVersion + 1)
        XCTAssertTrue(document.isFromFutureSchema)
    }
}

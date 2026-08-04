import XCTest
@testable import codepet

/// The rails' lane and height. Both used to be read off the CANVAS — rails were
/// `size.height` tall and centred at `size.height / 2` — which put the connector 12pt above
/// the row it appeared to continue and grew the slabs without bound as the board gained rows.
final class RoadmapRailSpineTests: XCTestCase {
    private func t(_ id: String, _ phase: RoadmapPhase, dept: String? = "eng",
                   deps: [String] = [], done: Bool = false) -> RoadmapTask {
        RoadmapTask(id: id, title: id, detail: "", phase: phase, who: .does,
                    dependsOn: deps, done: done, dept: dept)
    }

    // MARK: the lane

    /// The case in the screenshot: one task row, five collapsed phases. The spine must land on
    /// the card's centre line, not the canvas's.
    func testSpineSitsOnTheCardCentreAtOneRow() {
        let l = RoadmapLayoutEngine.layout([t("a", .find)])
        let cardCentre = RoadmapGeometry.top + RoadmapGeometry.cardH / 2   // 72
        XCTAssertEqual(l.spineY, cardCentre)
        XCTAssertEqual(l.nodes.first!.y + RoadmapGeometry.cardH / 2, l.spineY)
    }

    /// The old rule for comparison: it was off by exactly the 12pt the root edges were once
    /// fixed for, and the error moved with the row count instead of staying constant.
    func testSpineIsNotTheCanvasCentre() {
        let l = RoadmapLayoutEngine.layout([t("a", .find)])
        XCTAssertEqual(l.size.height / 2, 60, accuracy: 0.001,
                       "canvas centre — what the stubs used to use")
        XCTAssertEqual(l.spineY - l.size.height / 2, 12, accuracy: 0.001)
    }

    /// On a corridor-free board that 12pt is systematic, not a one-row accident: the canvas
    /// centre and the band centre both advance by half a `rowPitch` per lane, so the gap is
    /// the same at any row count. (`top + cardH/2` vs `(top + cardH + bottomPad)/2`.)
    func testTheOldCanvasCentreErrorWasTwelvePointsAtAnyRowCount() {
        let one = RoadmapLayoutEngine.layout([t("a", .find)])
        let three = RoadmapLayoutEngine.layout([t("a", .find, dept: "eng"),
                                                t("b", .find, dept: "design"),
                                                t("c", .find, dept: "mkt")])
        XCTAssertEqual(one.spineY - one.size.height / 2, 12, accuracy: 0.001)
        XCTAssertEqual(three.spineY - three.size.height / 2, 12, accuracy: 0.001)
    }

    /// …but it is not a constant you could have hard-coded around either: anything that grows
    /// the canvas moves the old anchor and leaves the lane where it is. A skip-level edge
    /// detouring through a corridor deepens the canvas to 132, and the error becomes 6pt.
    func testTheOldCanvasCentreErrorChangesWhenACorridorDeepensTheCanvas() {
        let l = RoadmapLayoutEngine.layout([t("a", .find),
                                            t("b", .foundation),
                                            t("c", .ship, deps: ["a"])])
        XCTAssertEqual(l.size.height, 132, "corridor-grown canvas")
        XCTAssertEqual(l.spineY, 72, "the lane does not move")
        XCTAssertEqual(l.spineY - l.size.height / 2, 6, accuracy: 0.001)
    }

    func testSpineIsTheCardBandCentreWithThreeLanes() {
        let l = RoadmapLayoutEngine.layout([t("a", .find, dept: "eng"),
                                            t("b", .find, dept: "design"),
                                            t("c", .find, dept: "mkt")])
        // Lanes at y = 40, 136, 232 → band 40…296, centre 168.
        XCTAssertEqual(l.spineY, 168)
        // …which is the middle lane's own centre, so the spine still runs along a real row.
        let middle = l.nodes.first { $0.row == 1 }!
        XCTAssertEqual(middle.y + RoadmapGeometry.cardH / 2, l.spineY)
    }

    // MARK: rail height

    func testRailHeightIsFlooredOnAShortBoard() {
        // One row: band 64 + 2×8 padding = 80, below the 112 floor the label needs.
        XCTAssertEqual(RoadmapGeometry.railHeight(rows: 1), RoadmapGeometry.railMinH)
        let l = RoadmapLayoutEngine.layout([t("a", .find)])
        XCTAssertEqual(l.railH, 112)
    }

    func testRailHeightTracksTheCardBandInBetween() {
        // Two rows: band 160 + 16 = 176, inside [112, 200].
        XCTAssertEqual(RoadmapGeometry.railHeight(rows: 2), 176)
    }

    func testRailHeightIsCappedOnATallBoard() {
        // Four rows: band 352 + 16 = 368 — a slab taller than every card on the board.
        XCTAssertEqual(RoadmapGeometry.railHeight(rows: 4), RoadmapGeometry.railMaxH)
        XCTAssertLessThan(RoadmapGeometry.railHeight(rows: 6), 201)
    }

    func testRailIsUniformAcrossPhases() {
        // Height is a board property, not a per-rail one: a longer name must not make a
        // taller station.
        let l = RoadmapLayoutEngine.layout([t("a", .find), t("b", .foundation, deps: ["a"])],
                                           expanded: [.find])
        XCTAssertGreaterThan(l.rails.count, 1)
        XCTAssertEqual(l.railH, RoadmapGeometry.railHeight(rows: 1))
    }

    // MARK: the canvas contains the rails

    func testCanvasGrowsToHoldARailThatOverhangsTheRows() {
        let l = RoadmapLayoutEngine.layout([t("a", .find)], expanded: [.find])
        XCTAssertFalse(l.rails.isEmpty)
        // 72 + 56 = 128 against a 120pt rows-height: without the growth the rail's foot is
        // clipped by the canvas.
        XCTAssertGreaterThanOrEqual(l.size.height, l.spineY + l.railH / 2)
    }

    func testRailNeverRunsOffTheTop() {
        for rows in 1...8 {
            let top = RoadmapGeometry.spineY(rows: rows) - RoadmapGeometry.railHeight(rows: rows) / 2
            XCTAssertGreaterThan(top, 0, "rail top for \(rows) rows")
        }
    }

    func testNoRailsMeansNoExtraCanvas() {
        // Every phase expanded → no rails → the height is exactly what the rows need, so a
        // fully expanded board picks up no rail padding it can't use. `hasRoot: false` keeps
        // the root's fan-out from opening a corridor and growing the canvas for its own
        // reasons (which is what makes the rooted version of this board 132 tall, not 120).
        let tasks = RoadmapPhase.allCases.map { t($0.rawValue, $0) }
        let l = RoadmapLayoutEngine.layout(tasks, hasRoot: false,
                                           expanded: Set(RoadmapPhase.allCases))
        XCTAssertTrue(l.rails.isEmpty)
        let rowsHeight = RoadmapGeometry.top + RoadmapGeometry.cardH + RoadmapGeometry.bottomPad
        XCTAssertEqual(l.size.height, rowsHeight)
    }
}

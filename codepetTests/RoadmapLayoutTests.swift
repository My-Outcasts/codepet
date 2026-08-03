import XCTest
@testable import codepet

final class RoadmapLayoutTests: XCTestCase {
    private func t(_ id: String, _ phase: RoadmapPhase, dept: String? = "eng",
                   deps: [String] = [], done: Bool = false) -> RoadmapTask {
        RoadmapTask(id: id, title: id, detail: "", phase: phase, who: .does,
                    dependsOn: deps, done: done, dept: dept)
    }
    private func node(_ l: RoadmapLayout, _ id: String) -> PositionedNode {
        l.nodes.first { $0.task.id == id }!
    }

    // MARK: geometry

    func testGeometryMatchesWeb() {
        XCTAssertEqual(RoadmapGeometry.cardW, 208)
        XCTAssertEqual(RoadmapGeometry.cardH, 64)
        XCTAssertEqual(RoadmapGeometry.colGap, 60)
        XCTAssertEqual(RoadmapGeometry.rowPitch, 96)
        XCTAssertEqual(RoadmapGeometry.top, 40)
        XCTAssertEqual(RoadmapGeometry.bottomPad, 16)
        XCTAssertEqual(RoadmapGeometry.rootW, 172)
        XCTAssertEqual(RoadmapGeometry.rootH, 118)
        XCTAssertEqual(RoadmapGeometry.rootLeft, 12)
        XCTAssertEqual(RoadmapGeometry.rootGap, 48)
    }

    func testColumnXIsRootRightPlusGapThenPitch() {
        let l = RoadmapLayoutEngine.layout([t("a", .find), t("b", .foundation)])
        XCTAssertEqual(node(l, "a").x, 12 + 172 + 48)              // 232
        XCTAssertEqual(node(l, "b").x, 232 + 208 + 60)             // 500
    }

    func testFirstRowTopIsTOP() {
        let l = RoadmapLayoutEngine.layout([t("a", .find)])
        XCTAssertEqual(node(l, "a").y, 40)
    }

    // MARK: department lanes

    // A dept keeps ONE row across every column it appears in — the horizontal track read.
    func testDeptKeepsOneLaneAcrossColumns() {
        let l = RoadmapLayoutEngine.layout([
            t("e1", .find, dept: "eng"), t("e2", .build, dept: "eng"),
            t("m1", .find, dept: "mkt"), t("m2", .build, dept: "mkt"),
        ])
        XCTAssertEqual(node(l, "e1").row, node(l, "e2").row)
        XCTAssertEqual(node(l, "m1").row, node(l, "m2").row)
        XCTAssertNotEqual(node(l, "e1").row, node(l, "m1").row)
    }

    // Lane order is the canonical DEPT_LANE_ORDER, not first-appearance order.
    func testLaneOrderIsCanonical() {
        let l = RoadmapLayoutEngine.layout([
            t("l1", .find, dept: "legal"), t("e1", .find, dept: "eng"),
        ])
        XCTAssertLessThan(node(l, "e1").row, node(l, "l1").row)   // eng is lane 0, legal last
    }

    // Depts that never share a column pack onto the same lane (compact layout).
    func testDisjointDeptsShareALane() {
        let l = RoadmapLayoutEngine.layout([
            t("e1", .find, dept: "eng"), t("s1", .build, dept: "sales"),
        ])
        XCTAssertEqual(node(l, "e1").row, node(l, "s1").row)
    }

    // A 2nd task in the same (phase, dept) cell spills to the nearest free row.
    func testSecondTaskInCellSpillsToFreeRow() {
        let l = RoadmapLayoutEngine.layout([
            t("e1", .find, dept: "eng"), t("e2", .find, dept: "eng"),
        ])
        XCTAssertNotEqual(node(l, "e1").row, node(l, "e2").row)
    }

    func testUnassignedDeptDoesNotCrash() {
        let l = RoadmapLayoutEngine.layout([t("a", .find, dept: nil), t("b", .find, dept: nil)])
        XCTAssertEqual(l.nodes.count, 2)
        XCTAssertNotEqual(node(l, "a").row, node(l, "b").row)
    }

    // MARK: edges

    func testAlignedRowsGiveAStraightTwoPointEdge() {
        let l = RoadmapLayoutEngine.layout([
            t("a", .find, dept: "eng"), t("b", .foundation, dept: "eng", deps: ["a"]),
        ])
        let e = l.edges.first { $0.from == "a" && $0.to == "b" }!
        XCTAssertEqual(e.points.count, 2)
        XCTAssertEqual(e.points[0].y, e.points[1].y)
        XCTAssertEqual(e.points[0].x, node(l, "a").x + 208)        // leaves the right edge
        XCTAssertEqual(e.points[1].x, node(l, "b").x)              // lands on the left edge
    }

    // Different rows → a 4-point elbow whose vertical sits in the gutter left of the TARGET
    // column, so it never crosses an intermediate column's cards.
    func testOffsetRowsGiveAnElbowInTheTargetGutter() {
        let l = RoadmapLayoutEngine.layout([
            t("e1", .find, dept: "eng"), t("m1", .find, dept: "mkt"),
            t("m2", .foundation, dept: "mkt", deps: ["e1"]),
        ])
        let e = l.edges.first { $0.from == "e1" && $0.to == "m2" }!
        XCTAssertEqual(e.points.count, 4)
        let gutter = (node(l, "m2").x - 30).rounded()
        XCTAssertEqual(e.points[1].x, gutter)
        XCTAssertEqual(e.points[2].x, gutter)
        XCTAssertEqual(e.points[1].y, e.points[0].y)
        XCTAssertEqual(e.points[2].y, e.points[3].y)
    }

    // Same-column deps hook through the column's LEFT gutter instead of doubling back.
    func testSameColumnEdgeHooksLeft() {
        let l = RoadmapLayoutEngine.layout([
            t("e1", .find, dept: "eng"), t("m1", .find, dept: "mkt", deps: ["e1"]),
        ])
        let e = l.edges.first { $0.from == "e1" && $0.to == "m1" }!
        XCTAssertEqual(e.points.count, 4)
        XCTAssertEqual(e.points[0].x, node(l, "e1").x)             // starts at the LEFT edge
        XCTAssertLessThan(e.points[1].x, node(l, "e1").x)          // hooks further left
    }

    func testDanglingDepIsDropped() {
        let l = RoadmapLayoutEngine.layout([t("a", .find, deps: ["ghost"])])
        XCTAssertTrue(l.edges.isEmpty)
    }

    // MARK: critical path

    // Web's rule: an edge is critical ONLY if it touches the current task. Not the whole
    // transitive chain — that lit up the entire board.
    func testCriticalIsOnlyEdgesTouchingCurrent() {
        // a done → b current → c. Edge a→b and b→c are critical; c→d is not.
        let l = RoadmapLayoutEngine.layout([
            t("a", .find, dept: "eng", done: true),
            t("b", .foundation, dept: "eng", deps: ["a"]),
            t("c", .build, dept: "eng", deps: ["b"]),
            t("d", .ship, dept: "eng", deps: ["c"]),
        ])
        XCTAssertEqual(RoadmapEngine.nextStep(l.nodes.map(\.task))?.id, "b")
        XCTAssertTrue(l.edges.first { $0.from == "a" && $0.to == "b" }!.critical)
        XCTAssertTrue(l.edges.first { $0.from == "b" && $0.to == "c" }!.critical)
        XCTAssertFalse(l.edges.first { $0.from == "c" && $0.to == "d" }!.critical)
    }

    // MARK: root

    func testRootBoxIsVerticallyCentered() {
        let l = RoadmapLayoutEngine.layout([
            t("e1", .find, dept: "eng"), t("m1", .find, dept: "mkt"),
        ])
        let r = l.root!
        XCTAssertEqual(r.origin.x, 12)
        XCTAssertEqual(r.size.width, 172)
        XCTAssertEqual(r.size.height, 118)
        XCTAssertEqual(r.origin.y, ((l.size.height - 118) / 2).rounded())
    }

    // Root fans out to ENTRY tasks only (no in-roadmap dependency), in any phase.
    func testRootEdgesGoToEntryTasksOnly() {
        let l = RoadmapLayoutEngine.layout([
            t("a", .find, dept: "eng"), t("b", .foundation, dept: "eng", deps: ["a"]),
        ])
        XCTAssertEqual(l.rootEdges.map(\.to), ["a"])
        XCTAssertTrue(l.rootEdges.allSatisfy { $0.from == RoadmapLayoutEngine.rootId })
        XCTAssertTrue(l.rootEdges.allSatisfy { !$0.critical })   // root edges are their own style
    }

    func testRootCanBeOmitted() {
        let l = RoadmapLayoutEngine.layout([t("a", .find)], hasRoot: false)
        XCTAssertNil(l.root)
        XCTAssertTrue(l.rootEdges.isEmpty)
        XCTAssertEqual(node(l, "a").x, 12)
    }

    // MARK: columns + canvas

    func testColumnsAreEveryPhaseInOrderWithCounts() {
        let l = RoadmapLayoutEngine.layout([
            t("a", .find, done: true), t("b", .find), t("c", .build),
        ])
        XCTAssertEqual(l.columns.map(\.phase), RoadmapPhase.allCases)
        XCTAssertEqual(l.columns[RoadmapPhase.find.order].done, 1)
        XCTAssertEqual(l.columns[RoadmapPhase.find.order].total, 2)
        XCTAssertEqual(l.columns[RoadmapPhase.ship.order].total, 0)
    }

    func testCurrentColumnIsFlagged() {
        let l = RoadmapLayoutEngine.layout([t("a", .find, done: true), t("b", .build)])
        XCTAssertEqual(l.columns.filter(\.current).map(\.phase), [.build])
    }

    func testCanvasSizeFromLastColumnAndLowestRow() {
        let l = RoadmapLayoutEngine.layout([t("a", .find)])
        let lastX = 232 + CGFloat(RoadmapPhase.allCases.count - 1) * 268
        XCTAssertEqual(l.size.width, lastX + 208 + 16)
        XCTAssertEqual(l.size.height, 40 + 64 + 16)                 // one row
    }

    func testEmptyTasksStillGivesRootAndSixColumns() {
        let l = RoadmapLayoutEngine.layout([])
        XCTAssertTrue(l.nodes.isEmpty)
        XCTAssertTrue(l.edges.isEmpty)
        XCTAssertNotNil(l.root)
        XCTAssertEqual(l.columns.count, RoadmapPhase.allCases.count)
        XCTAssertEqual(l.size.height, 120)
    }

    // MARK: spill search direction (takeRow)

    // eng/design/mkt all clash in column 0 (find) → lanes 0/1/2, laneCount 3. Column 2
    // (build) only has eng tasks, so lane 1 is free there. A 2nd eng task in column 2
    // must search DOWN from its lane and land on the first free lane below it.
    func testSpillSearchesDownIntoAFreeLane() {
        let l = RoadmapLayoutEngine.layout([
            t("e1", .find, dept: "eng"), t("d1", .find, dept: "design"),
            t("m1", .find, dept: "mkt"),
            t("a1", .build, dept: "eng"), t("a2", .build, dept: "eng"),
        ])
        XCTAssertEqual(node(l, "a1").row, 0)
        XCTAssertEqual(node(l, "a2").row, 1)   // DOWN search; would be 3 if both loops were gone
    }

    // Same lane setup, but this time column 2 (build) is occupied by mkt at its own lane
    // (2), the bottom lane, with nothing free below it. The spill must search UP instead.
    func testSpillSearchesUpWhenNothingIsFreeBelow() {
        let l = RoadmapLayoutEngine.layout([
            t("e1", .find, dept: "eng"), t("d1", .find, dept: "design"),
            t("m0", .find, dept: "mkt"),
            t("m1", .build, dept: "mkt"), t("m2", .build, dept: "mkt"),
        ])
        XCTAssertEqual(node(l, "m1").row, 2)
        XCTAssertEqual(node(l, "m2").row, 1)   // UP search; would be 3 if the UP loop were gone
    }

    // MARK: cross-column elbow

    // e1 (find/eng) → m1 (build/mkt) spans TWO columns with an intervening column
    // (foundation) in between. m0 forces eng and mkt onto different lanes so the edge is a
    // real elbow, not a straight line. The target-gutter and source-gutter formulas give
    // different x's here, so this actually distinguishes them (unlike the adjacent-column
    // case already covered by testOffsetRowsGiveAnElbowInTheTargetGutter).
    func testCrossColumnElbowClearsTheInterveningColumn() {
        let l = RoadmapLayoutEngine.layout([
            t("e1", .find, dept: "eng"), t("m0", .find, dept: "mkt"),
            t("m1", .build, dept: "mkt", deps: ["e1"]),
        ])
        let e = l.edges.first { $0.from == "e1" && $0.to == "m1" }!
        XCTAssertEqual(e.points.count, 4)
        XCTAssertEqual(e.points[0].x, 440)   // leaves e1's RIGHT edge (232 + 208)
        XCTAssertEqual(e.points[0].y, 72)
        XCTAssertEqual(e.points[3].y, 168)
        XCTAssertEqual(e.points[1].x, 738)   // gutter left of the TARGET column (768 - 30)
        XCTAssertEqual(e.points[2].x, 738)
        // Column 1 (foundation)'s right edge is 500 + 208 = 708. A source-gutter
        // implementation would put the vertical at 470 — straight through column 1's
        // cards. 738 > 708 proves the vertical actually clears the intervening column.
        XCTAssertGreaterThan(e.points[1].x, 708)
    }

    // MARK: unlisted departments

    // Pins `+ deptSeen.filter { !deptLaneOrder.contains($0) }`: canonical depts always lane
    // before unlisted ones, regardless of array order.
    func testUnlistedDeptGetsItsOwnLaneBelowCanonicalOnes() {
        // The unlisted dept (nil → "") appears FIRST in the task array — this ordering is
        // what makes the test discriminating. If the unlisted-dept term were dropped,
        // laneOf[""] would never be set and `laneOf[task.dept ?? ""] ?? 0` would default u1
        // to lane 0, taking row 0, while e1 (now unable to claim lane 0) spilled to row 1 —
        // i.e. these two assertions would reverse.
        let l = RoadmapLayoutEngine.layout([
            t("u1", .find, dept: nil), t("e1", .find, dept: "eng"),
        ])
        XCTAssertEqual(node(l, "e1").row, 0)
        XCTAssertEqual(node(l, "u1").row, 1)

        // Second layout: two unlisted depts, neither canonical — proves the order among
        // them is first-appearance, not alphabetical (z-custom appears first here but
        // would sort after a-custom alphabetically).
        let l2 = RoadmapLayoutEngine.layout([
            t("z1", .find, dept: "z-custom"), t("a1", .find, dept: "a-custom"),
        ])
        XCTAssertEqual(node(l2, "z1").row, 0)
        XCTAssertEqual(node(l2, "a1").row, 1)
    }

    // MARK: multi-row canvas height

    // testRootBoxIsVerticallyCentered recomputes the engine's own formula from its own
    // output (`((l.size.height - 118) / 2).rounded()`), so it can never fail. Pin absolute
    // numbers instead: two depts (eng, mkt) that never share a column but both sit in
    // column 0 (find) force 2 lanes.
    func testMultiRowCanvasHeightAndRootCentring() {
        let l = RoadmapLayoutEngine.layout([
            t("e1", .find, dept: "eng"), t("m1", .find, dept: "mkt"),
        ])
        // top 40 + 1 * rowPitch 96 + cardH 64 + bottomPad 16
        XCTAssertEqual(l.size.height, 216)
        // round((216 - 118) / 2)
        XCTAssertEqual(l.root!.origin.y, 49)
    }

    // MARK: rails (collapsed phases)

    func testRailGeometryConstants() {
        XCTAssertEqual(RoadmapGeometry.railW, 44)
        XCTAssertEqual(RoadmapGeometry.railGap, 20)
    }

    /// The all-expanded width must equal the pre-rails formula exactly — the last column
    /// contributes no trailing gap.
    func testBoardWidthAllExpandedMatchesTheOriginalFormula() {
        let all = Set(RoadmapPhase.allCases)
        let lastX = 232 + CGFloat(RoadmapPhase.allCases.count - 1) * 268
        XCTAssertEqual(RoadmapGeometry.boardWidth(expanded: all), lastX + 208 + 16)
    }

    func testBoardWidthShrinksWithEachCollapsedPhase() {
        let all = Set(RoadmapPhase.allCases)
        let three: Set<RoadmapPhase> = [.find, .foundation, .build]
        // 3 card columns + 3 rails, less the TRAILING gap (a rail's 20, not a column's 60),
        // plus bottomPad → 1224. Note it isn't `all - 3*268 + 3*64`: the trailing gap the
        // formula drops changes with the last slot's kind.
        // (Explicit CGFloat anchor below: the plain literal-chain form makes the type
        // checker time out inside this file's full @testable import surface, even though
        // the same expression checks instantly in isolation. Value is unchanged: 1224.)
        let expectedThreeWidth: CGFloat = 232 + 3 * 268 + 3 * 64 - 20 + 16
        XCTAssertEqual(RoadmapGeometry.boardWidth(expanded: three), expectedThreeWidth)
        XCTAssertLessThan(RoadmapGeometry.boardWidth(expanded: three),
                          RoadmapGeometry.boardWidth(expanded: all))
    }

    func testCollapsedPhasesBecomeRailsAndDropTheirCards() {
        let tasks = [t("a", .find), t("b", .build)]
        let l = RoadmapLayoutEngine.layout(tasks, expanded: [.find])
        XCTAssertEqual(l.nodes.map(\.id), ["a"])                       // b's phase collapsed
        XCTAssertEqual(l.columns.map(\.phase), [.find])                // headers only for columns
        XCTAssertEqual(l.rails.map(\.phase), [.foundation, .build, .ship, .launch, .grow])
        XCTAssertEqual(l.rails.first { $0.phase == .build }?.total, 1)  // the rail still counts
        XCTAssertEqual(l.rails.first { $0.phase == .foundation }?.total, 0)
    }

    func testRailXAccumulatesAfterTheExpandedColumn() {
        let l = RoadmapLayoutEngine.layout([t("a", .find), t("b", .build)], expanded: [.find])
        XCTAssertEqual(node(l, "a").x, 232)                            // unchanged start
        XCTAssertEqual(l.rails.first { $0.phase == .foundation }?.x, 232 + 208 + 60)  // 500
        XCTAssertEqual(l.rails.first { $0.phase == .build }?.x, 500 + 44 + 20)        // 564
    }

    func testExpandedColumnAfterARailStartsPastIt() {
        // find expanded, foundation collapsed, build expanded
        let l = RoadmapLayoutEngine.layout([t("a", .find), t("b", .build)],
                                           expanded: [.find, .build])
        XCTAssertEqual(node(l, "b").x, 232 + 268 + 64)                 // 564
    }

    /// Height and lanes come from the EXPANDED columns only, so a collapsed phase's extra
    /// department lane can't inflate the board the founder is looking at.
    func testHeightIgnoresCollapsedPhases() {
        let tasks = [t("a", .find, dept: "eng"),
                     t("b", .build, dept: "mkt"), t("c", .build, dept: "design")]
        // BUILD collapsed → its two department lanes leave the board entirely: one row.
        let expandedOnly = RoadmapLayoutEngine.layout(tasks, expanded: [.find])
        XCTAssertEqual(expandedOnly.size.height, 40 + 64 + 16)         // 120
        // BUILD expanded → eng and design share lane 0 (their columns don't clash), mkt takes
        // lane 1, so the board grows by exactly one row pitch.
        let withBuild = RoadmapLayoutEngine.layout(tasks, expanded: [.find, .build])
        XCTAssertEqual(withBuild.size.height, 40 + 96 + 64 + 16)       // 216
    }

    func testLayoutWidthMatchesBoardWidth() {
        let l = RoadmapLayoutEngine.layout([t("a", .find)], expanded: [.find])
        XCTAssertEqual(l.size.width, RoadmapGeometry.boardWidth(expanded: [.find]))
    }

    /// The default (nil) must be indistinguishable from the pre-rails engine.
    func testDefaultExpandedIsEveryPhase() {
        let l = RoadmapLayoutEngine.layout([t("a", .find), t("b", .build)])
        XCTAssertTrue(l.rails.isEmpty)
        XCTAssertEqual(l.columns.map(\.phase), RoadmapPhase.allCases)
        XCTAssertEqual(node(l, "b").x, 232 + 2 * 268)
    }

    /// A dependency into a collapsed phase draws no edge (its node doesn't exist) and must
    /// NOT resurrect the target as a root entry point.
    func testEdgeIntoACollapsedPhaseIsDroppedWithoutBecomingARootEdge() {
        let tasks = [t("a", .find), t("b", .build, deps: ["a"])]
        let l = RoadmapLayoutEngine.layout(tasks, expanded: [.build])
        XCTAssertTrue(l.edges.isEmpty)                                  // a has no node
        XCTAssertTrue(l.rootEdges.isEmpty)                              // b still depends on a
    }
}

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
    // column. The vertical is STAGGERED by the source's lane (lane 0 → the gutter's mid less
    // 16), so two edges arriving from different lanes don't stack onto one line.
    func testOffsetRowsGiveAnElbowInTheTargetGutter() {
        let l = RoadmapLayoutEngine.layout([
            t("e1", .find, dept: "eng"), t("m1", .find, dept: "mkt"),
            t("m2", .foundation, dept: "mkt", deps: ["e1"]),
        ])
        let e = l.edges.first { $0.from == "e1" && $0.to == "m2" }!
        XCTAssertEqual(e.points.count, 4)
        let trunk = RoadmapLayoutEngine.trunkX(rightWall: node(l, "m2").x, gutter: 60, lane: 0)
        XCTAssertEqual(trunk, 454)                                 // 500 - 30 (mid) - 16 (lane 0)
        XCTAssertEqual(e.points[1].x, trunk)
        XCTAssertEqual(e.points[2].x, trunk)
        XCTAssertEqual(e.points[1].y, e.points[0].y)
        XCTAssertEqual(e.points[2].y, e.points[3].y)
        // Inside the gutter: clear of the source column's right edge and the target's left one.
        XCTAssertGreaterThan(trunk, node(l, "e1").x + 208)
        XCTAssertLessThan(trunk, node(l, "m2").x)
    }

    // Same-column deps hook down the column's own left margin instead of doubling back — and
    // hug the card edge, INSIDE the inbound trunks' spread, so the two can't be superimposed.
    func testSameColumnEdgeHooksLeftInsideTheTrunkSpread() {
        let l = RoadmapLayoutEngine.layout([
            t("e1", .find, dept: "eng"), t("m1", .find, dept: "mkt", deps: ["e1"]),
        ])
        let e = l.edges.first { $0.from == "e1" && $0.to == "m1" }!
        XCTAssertEqual(e.points.count, 4)
        XCTAssertEqual(e.points[0].x, node(l, "e1").x)             // starts at the LEFT edge
        XCTAssertEqual(e.points[1].x, node(l, "e1").x - 8)         // sideHookInset
        XCTAssertLessThan(e.points[1].x, node(l, "e1").x)          // hooks further left
        // The widest inbound trunk any lane can claim still sits left of this hook, so an
        // in-phase hook and a cross-phase trunk can never be drawn on the same x.
        let widest = RoadmapLayoutEngine.trunkX(rightWall: node(l, "e1").x, gutter: 60, lane: 4)
        XCTAssertLessThan(widest, e.points[1].x)
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

    // The root is seated on the rows it FEEDS, not on the canvas. With two entry tasks on
    // lanes 0 and 1 that's the mean of their centres (72, 168) → 120, so origin.y = 120 - 59.
    // Canvas-centring gave 49 — a few points off both lanes, which is what put a needless jog
    // on every root edge and ran it parallel to the real edges on that lane.
    func testRootBoxIsSeatedOnItsEntryRows() {
        let l = RoadmapLayoutEngine.layout([
            t("e1", .find, dept: "eng"), t("m1", .find, dept: "mkt"),
        ])
        let r = l.root!
        XCTAssertEqual(r.origin.x, 12)
        XCTAssertEqual(r.size.width, 172)
        XCTAssertEqual(r.size.height, 118)
        XCTAssertEqual(r.origin.y, 61)
        XCTAssertNotEqual(r.origin.y, ((l.size.height - 118) / 2).rounded())   // was 49
    }

    /// A single entry task tall enough to reach → the root's first leg is DEAD STRAIGHT (2
    /// points), no jog. Three lanes so the 118pt root box can actually sit that low without
    /// being clamped by the canvas.
    func testRootEdgeToASingleEntryIsStraight() {
        let l = RoadmapLayoutEngine.layout([
            t("m1", .find, dept: "mkt"),
            t("e1", .find, dept: "eng", deps: ["m1"]),
            t("f1", .find, dept: "fin", deps: ["m1"]),
        ])
        XCTAssertEqual(node(l, "m1").row, 1)                    // the middle lane
        XCTAssertEqual(l.size.height, 312)                      // 40 + 2*96 + 64 + 16
        XCTAssertEqual(l.root!.origin.y, 109)                   // centre 168 - 59, unclamped
        XCTAssertEqual(l.rootEdges.count, 1)
        let e = l.rootEdges[0]
        XCTAssertEqual(e.points.count, 2)
        XCTAssertEqual(e.points[0].y, 168)
        XCTAssertEqual(e.points[1].y, 168)                      // same y → no jog at all
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
        XCTAssertEqual(e.points[1].x, 722)   // target gutter, staggered for lane 0 (768 - 30 - 16)
        XCTAssertEqual(e.points[2].x, 722)
        // Column 1 (foundation)'s right edge is 500 + 208 = 708. A source-gutter
        // implementation would put the vertical at 470 — straight through column 1's
        // cards. 722 > 708 proves the vertical actually clears the intervening column.
        XCTAssertGreaterThan(e.points[1].x, 708)
        // Column 1 holds NO card here, so nothing obstructs the horizontal leg and the plain
        // 4-point elbow is correct. That precision is the point: a detour is spent only when a
        // card really is in the way (see testSkipLevelEdgeDetoursAroundTheCardInItsPath).
        XCTAssertEqual(l.nodes.filter { $0.col == 1 }.count, 0)
    }

    // MARK: skip-level routing

    /// THE routing fix. `e0 → x2` skips column 1, and `e1` sits in column 1 on the very same
    /// department lane — so the old horizontal-at-the-source's-y ran straight through `e1`'s
    /// opaque card and re-emerged, rendering `e0 → x2` as the chain `e0 → e1 → x2`. All three
    /// share lane 0 here, so the old route was a 2-point STRAIGHT line right across `e1`.
    func testSkipLevelEdgeDetoursAroundTheCardInItsPath() {
        let l = RoadmapLayoutEngine.layout([
            t("e0", .find, dept: "eng"),
            t("e1", .foundation, dept: "eng"),
            t("x2", .build, dept: "eng", deps: ["e0"]),
        ])
        // All on lane 0 — this is what made the old straight line pass through e1.
        XCTAssertEqual(node(l, "e0").row, 0)
        XCTAssertEqual(node(l, "e1").row, 0)
        XCTAssertEqual(node(l, "x2").row, 0)

        let e = l.edges.first { $0.from == "e0" && $0.to == "x2" }!
        XCTAssertEqual(e.points.count, 6)                       // was 2 (straight, through e1)
        XCTAssertEqual(e.points[0], CGPoint(x: 440, y: 72))     // e0's right edge
        XCTAssertEqual(e.points[5], CGPoint(x: 768, y: 72))     // x2's left edge

        // The crossing happens in the corridor below row 0, not on row 0.
        let corridor = RoadmapGeometry.corridorY(below: 0)
        XCTAssertEqual(corridor, 120)                           // 40 + 64 + 16
        XCTAssertEqual(e.points[2].y, corridor)
        XCTAssertEqual(e.points[3].y, corridor)
        // e1's card occupies y 40...104 and x 500...708. The corridor clears it vertically,
        // and both verticals clear it horizontally.
        XCTAssertGreaterThan(corridor, node(l, "e1").y + 64)
        XCTAssertLessThan(e.points[1].x, node(l, "e1").x)       // exits before column 1
        XCTAssertGreaterThan(e.points[4].x, node(l, "e1").x + 208)  // re-enters after it

        // The canvas grows so the bottom-row corridor isn't stroked on the clipping edge:
        // one row is normally 120 tall, and corridorY(below: 0) lands exactly on that.
        XCTAssertEqual(l.size.height, 132)                      // 120 + corridorPad 12
    }

    /// Two edges arriving from DIFFERENT lanes get their own vertical; two leaving the SAME
    /// source stay bundled. The old `b.x - colGap / 2` gave every inbound edge of a column the
    /// same x, so one dependency and nine looked identical.
    func testInboundTrunksStaggerByLaneButBundlePerSource() {
        let l = RoadmapLayoutEngine.layout([
            t("e1", .find, dept: "eng"), t("m1", .find, dept: "mkt"),
            t("d1", .foundation, dept: "design"), t("s1", .foundation, dept: "sales"),
            t("f1", .foundation, dept: "fin", deps: ["e1", "m1"]),
        ])
        XCTAssertEqual(node(l, "e1").row, 0)
        XCTAssertEqual(node(l, "m1").row, 1)
        XCTAssertEqual(node(l, "f1").row, 2)

        let fromE = l.edges.first { $0.from == "e1" && $0.to == "f1" }!
        let fromM = l.edges.first { $0.from == "m1" && $0.to == "f1" }!
        XCTAssertEqual(fromE.points[1].x, 454)                  // lane 0 → mid - 16
        XCTAssertEqual(fromM.points[1].x, 462)                  // lane 1 → mid - 8
        XCTAssertNotEqual(fromE.points[1].x, fromM.points[1].x)
        // Both still inside the gutter between column 0's right edge (440) and column 1 (500).
        for x in [fromE.points[1].x, fromM.points[1].x] {
            XCTAssertGreaterThan(x, 440)
            XCTAssertLessThan(x, 500)
        }

        // Same source, two targets in the same column → deliberately ONE shared trunk: that
        // really is a single fan-out, so bundling it is honest rather than lossy.
        let l2 = RoadmapLayoutEngine.layout([
            t("e1", .find, dept: "eng"), t("m1", .find, dept: "mkt"),
            t("d1", .foundation, dept: "design"), t("s1", .foundation, dept: "sales", deps: ["e1"]),
            t("f1", .foundation, dept: "fin", deps: ["e1"]),
        ])
        let a = l2.edges.first { $0.from == "e1" && $0.to == "s1" }!
        let b = l2.edges.first { $0.from == "e1" && $0.to == "f1" }!
        XCTAssertEqual(a.points[1].x, b.points[1].x)
    }

    /// A column preceded by a RAIL has only `railGap` (20) in front of it, not `colGap` (60).
    /// The old fixed `b.x - colGap / 2` put the vertical 10pt INSIDE that rail.
    func testTrunkStaysOutOfAPrecedingRail() {
        let l = RoadmapLayoutEngine.layout([
            t("e1", .find, dept: "eng"), t("m1", .find, dept: "mkt"),
            t("m2", .build, dept: "mkt", deps: ["e1"]),
        ], expanded: [.find, .build])
        let railX = l.rails.first { $0.phase == .foundation }!.x
        XCTAssertEqual(railX, 500)
        XCTAssertEqual(node(l, "m2").x, 564)                    // 500 + railW 44 + railGap 20

        let e = l.edges.first { $0.from == "e1" && $0.to == "m2" }!
        XCTAssertEqual(e.points.count, 4)
        XCTAssertEqual(e.points[1].x, 554)                      // 564 - 10, the narrow gutter's mid
        XCTAssertGreaterThan(e.points[1].x, railX + 44)         // clear of the rail's right edge
        XCTAssertLessThan(e.points[1].x, node(l, "m2").x)
        // The old formula: 564 - 30 = 534, which is 34pt INSIDE the rail [500, 544].
        XCTAssertGreaterThan(e.points[1].x, 534)
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

    // Pin absolute numbers: two depts (eng, mkt) that never share a column but both sit in
    // column 0 (find) force 2 lanes. No edges here, so the canvas keeps its plain row height —
    // only a routing corridor along the bottom row grows it (see the skip-level test).
    func testMultiRowCanvasHeightAndRootSeating() {
        let l = RoadmapLayoutEngine.layout([
            t("e1", .find, dept: "eng"), t("m1", .find, dept: "mkt"),
        ])
        // top 40 + 1 * rowPitch 96 + cardH 64 + bottomPad 16
        XCTAssertEqual(l.size.height, 216)
        // Both are entry tasks → mean of lane 0 and lane 1 centres (72, 168) = 120, less 59.
        XCTAssertEqual(l.root!.origin.y, 61)
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
        let tasks = [t("a", .find), t("b", .build), t("c", .build, done: true)]
        let l = RoadmapLayoutEngine.layout(tasks, expanded: [.find])
        XCTAssertEqual(l.nodes.map(\.id), ["a"])                       // b/c's phase collapsed
        XCTAssertEqual(l.columns.map(\.phase), [.find])                // headers only for columns
        XCTAssertEqual(l.rails.map(\.phase), [.foundation, .build, .ship, .launch, .grow])
        XCTAssertEqual(l.rails.first { $0.phase == .build }?.total, 2)  // the rail still counts
        XCTAssertEqual(l.rails.first { $0.phase == .build }?.done, 1)   // and pins done, not swapped
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
        // lane 1, so the ROW contribution grows by exactly one row pitch. Isolated with
        // `hasRoot: false`, because with a root these depless BUILD tasks are entry tasks whose
        // root edges cross FIND — see the corridor case below.
        let rootless = RoadmapLayoutEngine.layout(tasks, hasRoot: false, expanded: [.find, .build])
        XCTAssertEqual(rootless.size.height, 40 + 96 + 64 + 16)        // 216

        // With the root, `b` (bottom lane, column 2) is fed by a root edge that has to cross
        // column 0's card, so it routes through the corridor below the bottom row — which lands
        // exactly on 216. The canvas grows by `corridorPad` to keep that line inside it. The
        // extra height is ROUTING, not a collapsed phase's lane: the claim above still holds.
        let withBuild = RoadmapLayoutEngine.layout(tasks, expanded: [.find, .build])
        XCTAssertEqual(withBuild.size.height, 228)                     // 216 + corridorPad 12
        XCTAssertEqual(RoadmapGeometry.corridorY(below: 1), 216)
        XCTAssertEqual(l6RootEdge(withBuild, to: "b")?.points.count, 6)
    }

    /// The root edge to `id`, for tests that care about its routing shape.
    private func l6RootEdge(_ l: RoadmapLayout, to id: String) -> EdgePath? {
        l.rootEdges.first { $0.to == id }
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

    /// Without a root, `boardWidth`'s origin must be `rootLeft` — NOT `rootRight + rootGap`.
    /// Pins the two disagreeing-origin bug: `layout(hasRoot: false)` places col 0 at
    /// `rootLeft` (12) while `boardWidth` used to always start from `rootRight + rootGap`
    /// (232), reporting a canvas 220pt wider than what was actually drawn.
    func testRootlessWidthDropsTheRootOffset() {
        let all = Set(RoadmapPhase.allCases)
        // (Explicit CGFloat anchor, as in testBoardWidthShrinksWithEachCollapsedPhase: long
        // inline literal arithmetic in this file has previously timed out the type checker.)
        let expectedRootlessWidth: CGFloat = 12 + 6 * 268 - 60 + 16
        XCTAssertEqual(expectedRootlessWidth, 1576)
        XCTAssertEqual(RoadmapGeometry.boardWidth(expanded: all, hasRoot: false), expectedRootlessWidth)
        // Pin the engine and the formula together so they can't drift apart again.
        let l = RoadmapLayoutEngine.layout([t("a", .find)], hasRoot: false, expanded: all)
        XCTAssertEqual(l.size.width, RoadmapGeometry.boardWidth(expanded: all, hasRoot: false))
    }
}

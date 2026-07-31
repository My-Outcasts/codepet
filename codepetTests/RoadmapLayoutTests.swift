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
}

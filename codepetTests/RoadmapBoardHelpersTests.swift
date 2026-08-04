// codepetTests/RoadmapBoardHelpersTests.swift
import XCTest
import SwiftUI
@testable import codepet

final class RoadmapBoardHelpersTests: XCTestCase {
    private func t(_ id: String, _ phase: RoadmapPhase) -> RoadmapTask {
        RoadmapTask(id: id, title: id, detail: "", phase: phase, who: .does)
    }

    // MARK: edge arrowheads

    /// Collect a `Path`'s corner points so the triangle's actual geometry can be asserted.
    private func points(of path: Path) -> [CGPoint] {
        var out: [CGPoint] = []
        path.forEach { element in
            switch element {
            case .move(let p):    out.append(p)
            case .line(let p):    out.append(p)
            default:              break
            }
        }
        return out
    }

    func testArrowheadPointsAlongARightwardRun() {
        let p = RoadmapBoardView.arrowhead([CGPoint(x: 0, y: 50), CGPoint(x: 100, y: 50)],
                                           length: 7, halfWidth: 4)
        let pts = points(of: p)
        XCTAssertEqual(pts.count, 3)
        XCTAssertEqual(pts[0], CGPoint(x: 100, y: 50))          // the tip is the terminal point
        // Base sits `length` BEHIND the tip, spread `halfWidth` either side of the run.
        XCTAssertEqual(Set(pts.dropFirst().map(\.x)), [93])
        XCTAssertEqual(Set(pts.dropFirst().map(\.y)), [46, 54])
    }

    /// A dependency reaching back to an EARLIER phase ends in a leftward run, and the head has
    /// to follow it. Pins that the direction comes from the polyline, not from an assumption
    /// that flow is always left-to-right.
    func testArrowheadFollowsALeftwardRun() {
        let p = RoadmapBoardView.arrowhead([CGPoint(x: 100, y: 50), CGPoint(x: 0, y: 50)],
                                           length: 7, halfWidth: 4)
        let pts = points(of: p)
        XCTAssertEqual(pts[0], CGPoint(x: 0, y: 50))
        XCTAssertEqual(Set(pts.dropFirst().map(\.x)), [7])      // base is to the RIGHT of the tip
        XCTAssertTrue(pts.dropFirst().allSatisfy { $0.x > pts[0].x })
    }

    /// Routes turn vertically inside a gutter; if one ever ended on that turn, the head must
    /// still be square to it rather than silently drawn sideways.
    func testArrowheadFollowsAVerticalRun() {
        let p = RoadmapBoardView.arrowhead([CGPoint(x: 50, y: 0), CGPoint(x: 50, y: 100)],
                                           length: 7, halfWidth: 4)
        let pts = points(of: p)
        XCTAssertEqual(pts[0], CGPoint(x: 50, y: 100))
        XCTAssertEqual(Set(pts.dropFirst().map(\.y)), [93])
        XCTAssertEqual(Set(pts.dropFirst().map(\.x)), [46, 54])
    }

    /// No direction to draw → no path, rather than NaNs from normalising a zero vector.
    func testArrowheadIsEmptyForADegenerateRun() {
        XCTAssertTrue(RoadmapBoardView.arrowhead([], length: 7, halfWidth: 4).isEmpty)
        XCTAssertTrue(RoadmapBoardView.arrowhead([CGPoint(x: 1, y: 1)],
                                                 length: 7, halfWidth: 4).isEmpty)
        XCTAssertTrue(RoadmapBoardView.arrowhead([CGPoint(x: 1, y: 1), CGPoint(x: 1, y: 1)],
                                                 length: 7, halfWidth: 4).isEmpty)
    }

    /// Every route the engine actually produces terminates ON the target card's left edge, so
    /// the head lands against the card it points at — not short of it, and not inside it.
    func testEveryRoutedEdgeEndsOnItsTargetsLeftEdge() {
        let tasks = [
            RoadmapTask(id: "a", title: "a", detail: "", phase: .find, who: .does, dept: "eng"),
            RoadmapTask(id: "b", title: "b", detail: "", phase: .find, who: .does,
                        dependsOn: ["a"], dept: "mkt"),                       // same column
            RoadmapTask(id: "c", title: "c", detail: "", phase: .foundation, who: .does,
                        dependsOn: ["a"], dept: "eng"),                       // straight
            // `e` puts a card in column 1 on b's lane, so b→d has to detour around it. `e` is
            // also depless, which makes it a root entry in a later column → a root detour too.
            RoadmapTask(id: "e", title: "e", detail: "", phase: .foundation, who: .does,
                        dept: "mkt"),
            RoadmapTask(id: "d", title: "d", detail: "", phase: .build, who: .does,
                        dependsOn: ["b"], dept: "eng"),                       // skip → detour
        ]
        let l = RoadmapLayoutEngine.layout(tasks)
        // All four route kinds plus both root kinds are present, so the assertion below covers
        // every shape the arrowhead has to sit on.
        XCTAssertEqual(l.edges.first { $0.to == "b" }?.points.count, 4)        // sideHook
        XCTAssertEqual(l.edges.first { $0.to == "c" }?.points.count, 2)        // straight
        XCTAssertEqual(l.edges.first { $0.to == "d" }?.points.count, 6)        // detour
        XCTAssertEqual(l.rootEdges.first { $0.to == "e" }?.points.count, 6)    // root detour
        for e in l.edges + l.rootEdges {
            let target = l.nodes.first { $0.task.id == e.to }!
            let tip = e.points.last!
            XCTAssertEqual(tip.x, target.x, "edge \(e.from)→\(e.to) must end on the card's edge")
            XCTAssertEqual(tip.y, target.y + RoadmapGeometry.cardH / 2)
            // A well-defined direction for the head to follow.
            XCTAssertGreaterThan(hypot(tip.x - e.points[e.points.count - 2].x,
                                       tip.y - e.points[e.points.count - 2].y), 0.01)
        }
    }

    func testOrderedColumnsAllPhasesInOrder() {
        let tasks = [t("a", .build), t("b", .find), t("c", .build)]
        let cols = RoadmapEngine.orderedColumns(tasks)
        XCTAssertEqual(cols.map(\.phase), RoadmapPhase.allCases)   // every phase, in declared order
        XCTAssertEqual(cols.map(\.phase.order), Array(0..<RoadmapPhase.allCases.count))
        XCTAssertEqual(cols[RoadmapPhase.find.order].tasks.map(\.id), ["b"])
        XCTAssertEqual(cols[RoadmapPhase.build.order].tasks.map(\.id), ["a", "c"]) // input order preserved
        XCTAssertTrue(cols[RoadmapPhase.ship.order].tasks.isEmpty)   // empty phase still present
        XCTAssertTrue(cols[RoadmapPhase.launch.order].tasks.isEmpty)
    }
    func testOrderedColumnsEmptyInputStillAllPhases() {
        XCTAssertEqual(RoadmapEngine.orderedColumns([]).map(\.phase), RoadmapPhase.allCases)
        XCTAssertTrue(RoadmapEngine.orderedColumns([]).allSatisfy { $0.tasks.isEmpty })
    }
    func testStatusLabelsDistinctNonEmptyBothLanguages() {
        let statuses: [TaskStatus] = [.done, .codepetCanDo, .needsApproval, .needsYou, .blocked]
        for lang in [AppLanguage.en, .vi] {
            let labels = statuses.map { $0.label(lang) }
            XCTAssertEqual(Set(labels).count, 5)                  // all distinct
            XCTAssertFalse(labels.contains(where: \.isEmpty))
        }
    }
    func testWhoLabelsDistinctNonEmptyBothLanguages() {
        let whos: [TaskWho] = [.does, .draft, .you]
        for lang in [AppLanguage.en, .vi] {
            let labels = whos.map { $0.label(lang) }
            XCTAssertEqual(Set(labels).count, 3)
            XCTAssertFalse(labels.contains(where: \.isEmpty))
        }
    }
}

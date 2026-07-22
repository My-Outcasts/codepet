import XCTest
@testable import codepet

final class RoadmapMapLayoutTests: XCTestCase {
    private func t(_ id: String, _ phase: RoadmapPhase, deps: [String] = []) -> RoadmapTask {
        RoadmapTask(id: id, title: id, detail: "", phase: phase, who: .does, dependsOn: deps)
    }
    func testRootPresentAtLeft() {
        let m = RoadmapMapLayout.layout([t("a", .find)])
        let root = m.nodes.first { $0.id == RoadmapMapLayout.rootId }
        XCTAssertNotNil(root)
        XCTAssertLessThan(root!.x, m.nodes.first { $0.id == "a" }!.x)
    }
    func testPhaseIsColumn() {
        let m = RoadmapMapLayout.layout([t("a", .find), t("b", .build)])
        XCTAssertLessThan(m.nodes.first { $0.id == "a" }!.x, m.nodes.first { $0.id == "b" }!.x)
    }
    func testRootEdgeToDeplessFirstPhase() {
        let m = RoadmapMapLayout.layout([t("a", .find)])
        XCTAssertTrue(m.edges.contains { $0.fromId == RoadmapMapLayout.rootId && $0.toId == "a" })
    }
    func testDepEdge() {
        let m = RoadmapMapLayout.layout([t("a", .find), t("b", .foundation, deps: ["a"])])
        XCTAssertTrue(m.edges.contains { $0.fromId == "a" && $0.toId == "b" })
    }
    func testCriticalPathFromBeacon() {
        // beacon = first not-done dep-satisfied = a; b depends on a → edge a→b critical
        let m = RoadmapMapLayout.layout([t("a", .find), t("b", .foundation, deps: ["a"])])
        XCTAssertTrue(m.edges.first { $0.fromId == "a" && $0.toId == "b" }!.critical)
    }
    func testEmpty() {
        let m = RoadmapMapLayout.layout([])
        XCTAssertEqual(m.nodes.map(\.id), [RoadmapMapLayout.rootId])
        XCTAssertTrue(m.edges.isEmpty)
    }
}

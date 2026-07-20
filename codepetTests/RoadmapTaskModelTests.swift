// codepetTests/RoadmapTaskModelTests.swift
import XCTest
@testable import codepet

final class RoadmapTaskModelTests: XCTestCase {
    func testPhaseOrderAndLabels() {
        XCTAssertEqual(RoadmapPhase.allCases.map(\.rawValue),
                       ["find", "foundation", "build", "ship", "launch"])
        XCTAssertEqual(RoadmapPhase.find.order, 0)
        XCTAssertEqual(RoadmapPhase.launch.order, 4)
        for p in RoadmapPhase.allCases {
            XCTAssertFalse(p.label(.en).isEmpty); XCTAssertFalse(p.label(.vi).isEmpty)
        }
    }
    func testTaskRoundTripsCodableWithDefaults() throws {
        let t = RoadmapTask(id: "t1", title: "Ship auth", detail: "wire sign-in", phase: .build, who: .does)
        XCTAssertEqual(t.dependsOn, []); XCTAssertFalse(t.done); XCTAssertFalse(t.drafted)
        let back = try JSONDecoder().decode(RoadmapTask.self, from: JSONEncoder().encode(t))
        XCTAssertEqual(back, t)
    }
}

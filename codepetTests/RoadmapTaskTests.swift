// codepetTests/RoadmapTaskTests.swift
import XCTest
@testable import codepet

final class RoadmapTaskTests: XCTestCase {
    func testRoadmapTaskRoundTripsCodable() throws {
        let t = RoadmapTask(id: "eng-0", deptKey: .engineering, title: "Ship auth",
                            detail: "Wire Firebase email sign-in", who: .draft, kind: "build", done: false)
        let data = try JSONEncoder().encode(t)
        let back = try JSONDecoder().decode(RoadmapTask.self, from: data)
        XCTAssertEqual(back, t)
    }

    func testTaskWhoDefaultsAndDoneToggleField() {
        let t = RoadmapTask(id: "x", deptKey: .marketing, title: "T", detail: "D")
        XCTAssertEqual(t.who, .draft)
        XCTAssertEqual(t.kind, "build")
        XCTAssertFalse(t.done)
    }
}

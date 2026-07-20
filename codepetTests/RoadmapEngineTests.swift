// codepetTests/RoadmapEngineTests.swift
import XCTest
@testable import codepet

final class RoadmapEngineTests: XCTestCase {
    private func task(_ id: String, _ dept: HealthPillar, done: Bool = false) -> RoadmapTask {
        RoadmapTask(id: id, deptKey: dept, title: "T-\(id)", detail: "d", done: done)
    }

    func testPicksFirstOpenTaskByPillarOrderThenPosition() {
        // marketing(order 2) task appears first in the array, but engineering(order 0) wins.
        let tasks = [task("m0", .marketing), task("e0", .engineering), task("e1", .engineering)]
        let next = RoadmapEngine.nextStep(tasks, stage: .building)
        XCTAssertEqual(next?.taskTitle, "T-e0")
        XCTAssertEqual(next?.deptKey, .engineering)
        XCTAssertFalse(next?.why.isEmpty ?? true)
    }

    func testSkipsDoneTasks() {
        let tasks = [task("e0", .engineering, done: true), task("e1", .engineering)]
        XCTAssertEqual(RoadmapEngine.nextStep(tasks, stage: .idea)?.taskTitle, "T-e1")
    }

    func testNilWhenNothingOpen() {
        XCTAssertNil(RoadmapEngine.nextStep([], stage: .idea))
        XCTAssertNil(RoadmapEngine.nextStep([task("e0", .engineering, done: true)], stage: .idea))
    }
}

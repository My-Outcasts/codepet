// codepetTests/RoadmapShapeLineTests.swift
import XCTest
@testable import codepet

/// One sentence telling the founder how much was lined up for her. The greeting jumped
/// straight from "your company is ready" to a single task, which undersold a board of a dozen.
final class RoadmapShapeLineTests: XCTestCase {

    /// Mirrors `FirstRunGreetingTests`' own helper — `detail` and `who` are required.
    private func task(_ id: String, _ phase: RoadmapPhase) -> RoadmapTask {
        RoadmapTask(id: id, title: id, detail: "", phase: phase, who: .does)
    }

    func testNoTasksProducesNothing() {
        XCTAssertNil(RoadmapShapeLine.compose(tasks: [], language: .en))
    }

    /// The plural trap: "1 tasks across 1 phases".
    func testOneTaskInOnePhaseIsSingular() {
        let out = RoadmapShapeLine.compose(tasks: [task("a", .foundation)], language: .en)!
        XCTAssertTrue(out.contains("1 task"))
        XCTAssertFalse(out.contains("1 tasks"))
        XCTAssertTrue(out.contains("1 phase"))
        XCTAssertFalse(out.contains("1 phases"))
    }

    func testManyTasksAcrossManyPhasesIsPlural() {
        let tasks = [task("a", .foundation), task("b", .foundation), task("c", .find)]
        let out = RoadmapShapeLine.compose(tasks: tasks, language: .en)!
        XCTAssertTrue(out.contains("3 tasks"))
        XCTAssertTrue(out.contains("2 phases"))
    }

    /// Phases are counted DISTINCT, not as the number of tasks.
    func testPhasesAreCountedOnce() {
        let tasks = [task("a", .foundation), task("b", .foundation), task("c", .foundation)]
        let out = RoadmapShapeLine.compose(tasks: tasks, language: .en)!
        XCTAssertTrue(out.contains("3 tasks"))
        XCTAssertTrue(out.contains("1 phase"))
        XCTAssertFalse(out.contains("3 phases"), "counted tasks as phases")
    }

    /// All six phases, so a real board's numbers are exercised rather than only two.
    func testAFullBoardCountsEveryPhaseOnce() {
        let tasks = RoadmapPhase.allCases.enumerated().map { task("t\($0.offset)", $0.element) }
        let out = RoadmapShapeLine.compose(tasks: tasks, language: .en)!
        XCTAssertTrue(out.contains("6 tasks"))
        XCTAssertTrue(out.contains("6 phases"))
    }

    func testVietnameseIsADifferentSentence() {
        let tasks = [task("a", .foundation), task("b", .find)]
        let vi = RoadmapShapeLine.compose(tasks: tasks, language: .vi)!
        let en = RoadmapShapeLine.compose(tasks: tasks, language: .en)!
        XCTAssertNotEqual(vi, en)
        XCTAssertTrue(vi.contains("2"))
    }
}

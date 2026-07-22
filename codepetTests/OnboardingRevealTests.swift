// codepetTests/OnboardingRevealTests.swift
import XCTest
@testable import codepet

final class OnboardingRevealTests: XCTestCase {
    private func t(_ id: String, done: Bool = false) -> RoadmapTask {
        RoadmapTask(id: id, title: "Task " + id, detail: "", phase: .build, who: .does, done: done)
    }

    func testEmptyTasksIsNotOk() {
        XCTAssertEqual(OnboardingReveal.build(tasks: []), OnboardingReveal.empty)
        XCTAssertFalse(OnboardingReveal.build(tasks: []).ok)
    }
    func testCountsNotDoneAndSamplesFirstThree() {
        let tasks = [t("a"), t("b"), t("c", done: true), t("d"), t("e")]
        let r = OnboardingReveal.build(tasks: tasks)
        XCTAssertTrue(r.ok)                              // scaffold produced tasks
        XCTAssertEqual(r.taskCount, 4)                   // done 'c' excluded from count
        XCTAssertEqual(r.sampleTasks, ["Task a", "Task b", "Task d"]) // ≤3 not-done titles, 'c' skipped
    }
    func testAllDoneStillOkButZeroSamples() {
        let r = OnboardingReveal.build(tasks: [t("a", done: true)])
        XCTAssertTrue(r.ok)                              // non-empty ⇒ ok
        XCTAssertEqual(r.taskCount, 0)
        XCTAssertEqual(r.sampleTasks, [])
    }
}

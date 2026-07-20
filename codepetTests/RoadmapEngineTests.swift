// codepetTests/RoadmapEngineTests.swift
import XCTest
@testable import codepet

final class RoadmapEngineTests: XCTestCase {
    private func t(_ id: String, _ phase: RoadmapPhase, who: TaskWho = .does,
                   deps: [String] = [], done: Bool = false, drafted: Bool = false) -> RoadmapTask {
        RoadmapTask(id: id, title: id, detail: "", phase: phase, who: who, dependsOn: deps, done: done, drafted: drafted)
    }

    func testStatusPrecedence() {
        let a = t("a", .build, done: true)
        let b = t("b", .build, drafted: true)                 // needsApproval
        let c = t("c", .build, deps: ["z"])                   // z not-done → blocked
        let z = t("z", .find)                                 // z is not done
        let y = t("y", .build, who: .you)                     // needsYou
        let d = t("d", .build, who: .does)                    // codepetCanDo
        let all = [a, b, c, z, y, d]
        XCTAssertEqual(RoadmapEngine.status(for: a, in: all), .done)
        XCTAssertEqual(RoadmapEngine.status(for: b, in: all), .needsApproval)
        XCTAssertEqual(RoadmapEngine.status(for: c, in: all), .blocked)
        XCTAssertEqual(RoadmapEngine.status(for: y, in: all), .needsYou)
        XCTAssertEqual(RoadmapEngine.status(for: d, in: all), .codepetCanDo)
    }

    func testNextStepPicksFirstUnblockedByPhaseOrder() {
        // build-phase task is ready; a ship-phase task is also ready but later phase.
        let all = [t("s", .ship), t("f", .find, done: true), t("b", .build, deps: ["f"])]
        XCTAssertEqual(RoadmapEngine.nextStep(all)?.id, "b")   // build(1) before ship(3)
    }
    func testNextStepNilWhenAllDoneOrBlocked() {
        XCTAssertNil(RoadmapEngine.nextStep([]))
        XCTAssertNil(RoadmapEngine.nextStep([t("a", .build, done: true)]))
        // All-blocked = a dependency cycle: each task is blocked by the other (a not-done
        // dep referencing a task that is itself not-done). No task is ever ready → nil.
        XCTAssertNil(RoadmapEngine.nextStep([t("a", .build, deps: ["b"]), t("b", .build, deps: ["a"])]))
    }
    func testProgressAndGrouping() {
        let all = [t("a", .find, done: true), t("b", .build), t("c", .build, done: true)]
        XCTAssertEqual(RoadmapEngine.progressPercent(all), 67)
        XCTAssertEqual(RoadmapEngine.progressPercent([]), 0)
        XCTAssertEqual(RoadmapEngine.tasksByPhase(all)[.build]?.count, 2)
    }
}

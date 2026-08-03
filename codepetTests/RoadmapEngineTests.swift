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

    /// Precedence must hold when conditions OVERLAP (not just in isolation):
    /// done > needsApproval > blocked > needsYou > codepetCanDo.
    func testStatusPrecedenceWhenConditionsOverlap() {
        let z = t("z", .find)                                       // an unmet dependency
        // drafted AND blocked → needsApproval wins over blocked
        let draftedBlocked = t("a", .build, deps: ["z"], drafted: true)
        // blocked AND who:.you → blocked wins over needsYou
        let blockedYou = t("b", .build, who: .you, deps: ["z"])
        // drafted AND who:.you → needsApproval wins over needsYou
        let draftedYou = t("c", .build, who: .you, drafted: true)
        // done AND drafted → done wins over needsApproval
        let doneDrafted = t("d", .build, done: true, drafted: true)
        let all = [z, draftedBlocked, blockedYou, draftedYou, doneDrafted]
        XCTAssertEqual(RoadmapEngine.status(for: draftedBlocked, in: all), .needsApproval)
        XCTAssertEqual(RoadmapEngine.status(for: blockedYou, in: all), .blocked)
        XCTAssertEqual(RoadmapEngine.status(for: draftedYou, in: all), .needsApproval)
        XCTAssertEqual(RoadmapEngine.status(for: doneDrafted, in: all), .done)
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

    func testDeliverableResolvesBySourceTaskId() {
        let done = t("a", .build, done: true)
        let lib = [Deliverable(kind: .doc, title: "Doc A", body: "b", sourceTaskId: "a")]
        XCTAssertEqual(RoadmapEngine.deliverable(for: done, in: lib)?.title, "Doc A")
    }

    func testDeliverableNilWhenNoLibraryMatchOrEmptyLibrary() {
        let done = t("a", .build, done: true)
        XCTAssertNil(RoadmapEngine.deliverable(for: done, in: []))
        let other = [Deliverable(kind: .doc, title: "Other", body: "b", sourceTaskId: "z")]
        XCTAssertNil(RoadmapEngine.deliverable(for: done, in: other))
    }

    // MARK: rolling window (RoadmapGating)

    func testStatusIsBlockedOutsideTheOpenWindow() {
        let gate = t("y", .find, who: .you)     // holds FIND shut
        let later = t("b", .build)              // .does, no deps → would otherwise be codepetCanDo
        let all = [gate, later]
        XCTAssertEqual(RoadmapEngine.status(for: later, in: all), .blocked)
        XCTAssertEqual(RoadmapEngine.status(for: gate, in: all), .needsYou)
    }

    /// A drafted task in a CLOSED phase still says "needs approval": the draft already exists,
    /// and hiding it behind a lock would strand finished work.
    func testDraftedBeatsThePhaseWindow() {
        let gate = t("y", .find, who: .you)
        let draft = t("d", .build, drafted: true)
        XCTAssertEqual(RoadmapEngine.status(for: draft, in: [gate, draft]), .needsApproval)
    }

    func testNextStepDoesNotSkipAheadOfAClosedPhase() {
        // FIND's two founder steps block each other, so FIND has no actionable task at all.
        // Without the window the beacon would jump to BUILD; with it, there is no beacon.
        let a = t("a", .find, who: .you, deps: ["b"])
        let b = t("b", .find, who: .you, deps: ["a"])
        let later = t("c", .build)
        XCTAssertNil(RoadmapEngine.nextStep([a, b, later]))
    }
}

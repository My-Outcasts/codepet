import XCTest
@testable import codepet

final class RoadmapGatingTests: XCTestCase {
    private func t(_ id: String, _ phase: RoadmapPhase, who: TaskWho = .does,
                   deps: [String] = [], done: Bool = false, drafted: Bool = false) -> RoadmapTask {
        RoadmapTask(id: id, title: id, detail: "", phase: phase, who: who,
                    dependsOn: deps, done: done, drafted: drafted)
    }

    // MARK: needsFounder

    func testOnlyFounderOwnedOrDraftedWorkCountsAsABlocker() {
        XCTAssertTrue(RoadmapGating.needsFounder(t("a", .find, who: .you)))
        XCTAssertTrue(RoadmapGating.needsFounder(t("b", .find, drafted: true)))
        XCTAssertFalse(RoadmapGating.needsFounder(t("c", .find, who: .does)))
        XCTAssertFalse(RoadmapGating.needsFounder(t("d", .find, who: .draft)))   // drafted:false → nothing to approve yet
        XCTAssertFalse(RoadmapGating.needsFounder(t("e", .find, who: .you, done: true)))
        XCTAssertFalse(RoadmapGating.needsFounder(t("f", .find, done: true, drafted: true)))
    }

    // MARK: settled

    func testPhaseWithNoFounderWorkIsSettled() {
        let all = [t("a", .find), t("b", .find, who: .draft)]
        XCTAssertTrue(RoadmapGating.settled(.find, in: all))
    }

    func testPhaseHoldingFounderWorkIsNotSettled() {
        XCTAssertFalse(RoadmapGating.settled(.find, in: [t("a", .find, who: .you)]))
        XCTAssertFalse(RoadmapGating.settled(.find, in: [t("a", .find, drafted: true)]))
    }

    func testEmptyPhaseIsSettled() {
        XCTAssertTrue(RoadmapGating.settled(.launch, in: [t("a", .find, who: .you)]))
        XCTAssertTrue(RoadmapGating.settled(.find, in: []))
    }

    // MARK: openPhases

    func testOpenSetIsAPrefixEndingAtTheFirstUnsettledPhase() {
        // FIND settled (Codepet-owned), FOUNDATION holds a founder step → the window stops there.
        let all = [t("f", .find), t("y", .foundation, who: .you), t("b", .build)]
        let open = RoadmapGating.openPhases(all)
        XCTAssertTrue(open.contains(.find))
        XCTAssertTrue(open.contains(.foundation))      // the unsettled phase is itself open
        XCTAssertFalse(open.contains(.build))
        XCTAssertFalse(open.contains(.grow))
    }

    func testCodepetLeftoversDoNotHoldTheWindowShut() {
        // A Codepet-owned FIND task nobody has run yet must not lock FOUNDATION.
        let all = [t("f", .find), t("d", .foundation)]
        XCTAssertEqual(RoadmapGating.openPhases(all), Set(RoadmapPhase.allCases))
    }

    func testFirstPhaseIsAlwaysOpen() {
        XCTAssertTrue(RoadmapGating.openPhases([t("y", .find, who: .you)]).contains(.find))
        XCTAssertTrue(RoadmapGating.openPhases([]).contains(.find))
    }

    func testEmptyPhasesAreTransparentToTheWindow() {
        // Nothing in FIND or FOUNDATION; BUILD holds founder work → SHIP is closed, BUILD open.
        let all = [t("y", .build, who: .you), t("s", .ship)]
        let open = RoadmapGating.openPhases(all)
        XCTAssertTrue(open.contains(.build))
        XCTAssertFalse(open.contains(.ship))
    }

    // MARK: states

    func testStatesPrecedenceCompleteBeatsOpen() {
        let all = [t("f", .find, done: true), t("y", .foundation, who: .you), t("b", .build)]
        let s = RoadmapGating.states(all)
        XCTAssertEqual(s[.find], .complete)
        XCTAssertEqual(s[.foundation], .open)
        XCTAssertEqual(s[.build], .preview)
        XCTAssertEqual(s[.ship], .later)
    }

    func testPreviewSkipsEmptyPhases() {
        // FIND holds founder work; FOUNDATION is empty → the preview is BUILD, the next
        // phase that actually has tasks.
        let all = [t("y", .find, who: .you), t("b", .build)]
        let s = RoadmapGating.states(all)
        XCTAssertEqual(s[.find], .open)
        XCTAssertEqual(s[.foundation], .later)
        XCTAssertEqual(s[.build], .preview)
    }

    func testEmptyPhaseIsNeverCompleteOrPreview() {
        let s = RoadmapGating.states([t("y", .find, who: .you)])
        XCTAssertEqual(s[.grow], .later)
        XCTAssertEqual(s.count, RoadmapPhase.allCases.count)
    }

    // MARK: founderStep

    func testFounderStepReturnsTheEarliestUnsettledPhasesTask() {
        // Both FIND and FOUNDATION hold founder work, but FIND is the earlier unsettled
        // phase — founderStep must stop there, not walk on to FOUNDATION's task.
        let a = t("a", .find, who: .you)
        let b = t("b", .foundation, who: .you)
        XCTAssertEqual(RoadmapGating.founderStep(in: [a, b])?.id, "a")
    }

    func testFounderStepCountsADraftAsFounderWork() {
        // Not `who: .you` — a draft still needs the founder's approval to move.
        let d = t("d", .find, drafted: true)
        XCTAssertEqual(RoadmapGating.founderStep(in: [d])?.id, "d")
    }

    func testFounderStepIsNilWhenEveryPhaseIsSettled() {
        let all = [t("a", .find), t("b", .foundation, done: true)]
        XCTAssertNil(RoadmapGating.founderStep(in: all))
    }

    // MARK: blocker

    func testBlockerOfAPhaseGatedTaskIsTheEarliestFounderStep() {
        let gate = t("y", .find, who: .you)
        let later = t("b", .build)
        XCTAssertEqual(RoadmapGating.blocker(for: later, in: [gate, later])?.id, "y")
    }

    func testBlockerAndBeaconCoincideWhenTheOpenPrefixIsOnePhase() {
        // When the open prefix holds exactly one populated phase, the founder step holding
        // the window shut is also what nextStep points at, so the locked-card explanation
        // and the beacon coincide here. That's fixture-scoped, not a general invariant: once
        // the prefix spans more than one populated phase, `nextStep` minimises over the whole
        // window while `blocker` always names the earliest unsettled phase, so they can
        // legitimately point at different (both valid) tasks — see `blocker`'s doc comment.
        let gate = t("y", .find, who: .you)
        let later = t("b", .build)
        let all = [gate, later]
        XCTAssertEqual(RoadmapGating.blocker(for: later, in: all)?.id,
                       RoadmapEngine.nextStep(all)?.id)
    }

    func testBlockerOfADependencyGatedTaskIsItsUnmetDependency() {
        // Both in the open window; b waits on a, which is not done.
        let a = t("a", .find)
        let b = t("b", .find, deps: ["a"])
        XCTAssertEqual(RoadmapGating.blocker(for: b, in: [a, b])?.id, "a")
    }

    func testBlockerIsNilWhenNothingResolves() {
        let a = t("a", .find, deps: ["ghost"])     // dangling dep → fail-open, nothing blocks
        XCTAssertNil(RoadmapGating.blocker(for: a, in: [a]))
    }

    func testEscapeHatchChainResolvesToAnActionableTaskNotABlockedOne() {
        // y is founder-owned (so it's the naive "earliest founder step" answer) but y itself
        // is blocked on z, its own unmet dependency — handing the founder y would be a second
        // dead end. The escape hatch must walk past y to z, which is actually actionable.
        let z = t("z", .find)
        let y = t("y", .find, who: .you, deps: ["z"])
        let later = t("b", .build)
        let all = [z, y, later]
        let escapeHatch = RoadmapGating.escapeHatch(for: later, in: all)
        XCTAssertEqual(escapeHatch?.id, "z")
        XCTAssertNotEqual(RoadmapEngine.status(for: escapeHatch!, in: all), .blocked)
    }

    // MARK: strict blocker (display) vs escapeHatch (dispatch)

    /// The card face shows this string, so it must never name a task the tapped card has no
    /// dependency relationship with. On a cycle the strict blocker reports nothing rather than
    /// pointing somewhere misleading.
    func testStrictBlockerReturnsNilOnACycleRatherThanAnUnrelatedTask() {
        let a = t("a", .find, who: .you, deps: ["b"])
        let b = t("b", .find, who: .you, deps: ["a"])
        let elsewhere = t("z", .find)                     // actionable, unrelated to a/b
        let all = [a, b, elsewhere]
        // `a`'s only dependency is `b`, which is not done → strict blocker is `b`, full stop.
        XCTAssertEqual(RoadmapGating.blocker(for: a, in: all)?.id, "b")
        // The escape hatch may legitimately walk past the cycle to something actionable.
        XCTAssertNotNil(RoadmapGating.escapeHatch(for: a, in: all))
    }

    func testStrictBlockerOfAPhaseGatedTaskIsTheFounderStepItself() {
        // FIND's founder step is itself dependency-blocked, so the escape hatch walks past it
        // while the strict blocker still names it — that IS what's holding the window shut.
        let gate = t("y", .find, who: .you, deps: ["p"])
        let pre = t("p", .find)
        let later = t("b", .build)
        let all = [gate, pre, later]
        XCTAssertEqual(RoadmapGating.blocker(for: later, in: all)?.id, "y")
        XCTAssertEqual(RoadmapGating.escapeHatch(for: later, in: all)?.id, "p")
    }

    func testStrictBlockerIsNilWhenNothingBlocks() {
        let a = t("a", .find)
        XCTAssertNil(RoadmapGating.blocker(for: a, in: [a]))
    }
}

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

    // MARK: blocker

    func testBlockerOfAPhaseGatedTaskIsTheEarliestFounderStep() {
        let gate = t("y", .find, who: .you)
        let later = t("b", .build)
        XCTAssertEqual(RoadmapGating.blocker(for: later, in: [gate, later])?.id, "y")
    }

    func testBlockerAgreesWithTheBeacon() {
        // The founder step holding the window shut is also what nextStep points at, so the
        // locked-card explanation and the beacon can never disagree.
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
}

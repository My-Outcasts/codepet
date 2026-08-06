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

    /// CHANGED Aug 5: only unreviewed OUTPUT holds a phase. A founder-owned task no longer
    /// does — one parked step used to switch the whole AI team off, measured four times in the
    /// app that day. This is the assertion that flips, and it is the whole product change.
    func testOnlyAnUnapprovedDraftHoldsAPhase() {
        XCTAssertFalse(RoadmapGating.settled(.find, in: [t("a", .find, drafted: true)]))
        XCTAssertTrue(RoadmapGating.settled(.find, in: [t("a", .find, who: .you)]),
                      "a founder-owned task must not gate the phase any more")
        // Still the right answer to "what is waiting on you" — only no longer a gate.
        XCTAssertTrue(RoadmapGating.needsFounder(t("a", .find, who: .you)))
    }

    func testEmptyPhaseIsSettled() {
        XCTAssertTrue(RoadmapGating.settled(.launch, in: [t("a", .find, who: .you)]))
        XCTAssertTrue(RoadmapGating.settled(.find, in: []))
    }

    // MARK: openPhases

    func testOpenSetIsAPrefixEndingAtTheFirstUNREVIEWEDPhase() {
        // FOUNDATION holds a DRAFT → the window stops there, and that phase is itself open.
        let all = [t("f", .find), t("y", .foundation, drafted: true), t("b", .build)]
        let open = RoadmapGating.openPhases(all)
        XCTAssertTrue(open.contains(.find))
        XCTAssertTrue(open.contains(.foundation))
        XCTAssertFalse(open.contains(.build))
        XCTAssertFalse(open.contains(.grow))
    }

    /// The reason the rule changed: the founder's own open step must not shut the phases behind
    /// it. This is the exact shape she was stuck in — "Talk to 5 potential users" open in `.find`
    /// with eight Codepet-owned tasks reading `.blocked` behind it.
    func testAFounderOwnedStepNoLongerShutsTheRoadmap() {
        let all = [t("interviews", .find, who: .you),
                   t("brand", .foundation), t("landing", .foundation), t("waitlist", .build)]
        XCTAssertEqual(RoadmapGating.openPhases(all), Set(RoadmapPhase.allCases))
        // And the work behind it is genuinely runnable, not merely "open".
        for id in ["brand", "landing", "waitlist"] {
            let task = all.first { $0.id == id }!
            XCTAssertEqual(RoadmapEngine.status(for: task, in: all), .codepetCanDo, id)
        }
        // Her own step is untouched: still hers, still counted as needing her.
        XCTAssertEqual(RoadmapEngine.status(for: all[0], in: all), .needsYou)
    }

    /// What must NOT have changed: a task that genuinely depends on her step still waits. The
    /// phase stopped gating; the dependency did not, because the input really does not exist.
    func testWorkThatDependsOnHerStepStillWaits() {
        let all = [t("interviews", .find, who: .you),
                   t("copy", .foundation, deps: ["interviews"])]
        XCTAssertTrue(RoadmapGating.openPhases(all).contains(.foundation))   // phase is open…
        XCTAssertEqual(RoadmapEngine.status(for: all[1], in: all), .blocked) // …the dependency is not
        XCTAssertEqual(RoadmapGating.blocker(for: all[1], in: all)?.id, "interviews")
    }

    /// The pipeline stays self-limiting: Codepet may run ahead, but never further ahead than the
    /// founder has reviewed. Three drafts in FOUNDATION shut BUILD until she approves them.
    func testUnreviewedOutputStillCapsHowFarAheadCodepetRuns() {
        let all = [t("a", .foundation, drafted: true), t("b", .build)]
        XCTAssertFalse(RoadmapGating.openPhases(all).contains(.build))
        XCTAssertEqual(RoadmapEngine.status(for: all[1], in: all), .blocked)
        XCTAssertEqual(RoadmapGating.blockingDraft(in: all)?.id, "a")
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
        // Nothing in FIND or FOUNDATION; BUILD holds unreviewed output → SHIP closed, BUILD open.
        let all = [t("y", .build, drafted: true), t("s", .ship)]
        let open = RoadmapGating.openPhases(all)
        XCTAssertTrue(open.contains(.build))
        XCTAssertFalse(open.contains(.ship))
    }

    // MARK: states

    func testStatesPrecedenceCompleteBeatsOpen() {
        let all = [t("f", .find, done: true), t("y", .foundation, drafted: true), t("b", .build)]
        let s = RoadmapGating.states(all)
        XCTAssertEqual(s[.find], .complete)
        XCTAssertEqual(s[.foundation], .open)
        XCTAssertEqual(s[.build], .preview)
        XCTAssertEqual(s[.ship], .later)
    }

    func testPreviewSkipsEmptyPhases() {
        // FIND holds unreviewed output; FOUNDATION is empty → the preview is BUILD, the next
        // phase that actually has tasks.
        let all = [t("y", .find, drafted: true), t("b", .build)]
        let s = RoadmapGating.states(all)
        XCTAssertEqual(s[.find], .open)
        XCTAssertEqual(s[.foundation], .later)
        XCTAssertEqual(s[.build], .preview)
    }

    func testEmptyPhaseIsNeverCompleteOrPreview() {
        let s = RoadmapGating.states([t("y", .find, drafted: true)])
        XCTAssertEqual(s[.grow], .later)
        XCTAssertEqual(s.count, RoadmapPhase.allCases.count)
    }

    // MARK: blockingDraft

    func testFounderStepReturnsTheEarliestUnsettledPhasesTask() {
        // Both FIND and FOUNDATION hold an unapproved draft, but FIND is the earlier unsettled
        // phase — blockingDraft must stop there, not walk on to FOUNDATION's task. (Founder-OWNED
        // work no longer makes a phase unsettled, so the fixture uses drafts.)
        let a = t("a", .find, drafted: true)
        let b = t("b", .foundation, drafted: true)
        XCTAssertEqual(RoadmapGating.blockingDraft(in: [a, b])?.id, "a")
    }

    /// And the case the change created: an open founder-owned step with no drafts behind it
    /// holds nothing, so there is no step to name.
    func testFounderStepIsNilWhenOnlyFounderOwnedWorkIsOpen() {
        XCTAssertNil(RoadmapGating.blockingDraft(in: [t("mine", .find, who: .you),
                                                    t("theirs", .build)]))
    }

    func testFounderStepCountsADraftAsFounderWork() {
        // Not `who: .you` — a draft still needs the founder's approval to move.
        let d = t("d", .find, drafted: true)
        XCTAssertEqual(RoadmapGating.blockingDraft(in: [d])?.id, "d")
    }

    func testFounderStepIsNilWhenEveryPhaseIsSettled() {
        let all = [t("a", .find), t("b", .foundation, done: true)]
        XCTAssertNil(RoadmapGating.blockingDraft(in: all))
    }

    // MARK: blocker

    func testBlockerOfAPhaseGatedTaskIsTheEarliestFounderStep() {
        let gate = t("y", .find, drafted: true)
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
        let gate = t("y", .find, drafted: true)
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

    /// The walk past a dead end, now exercised through a DEPENDENCY chain — which is the only
    /// way left to reach it. `c` waits on `b`, which waits on `a`: handing the founder `b` would
    /// be a second dead end, so the hatch walks to `a`.
    ///
    /// The old fixture used a founder-owned phase gate that was itself dependency-blocked. That
    /// shape is now unreachable BY CONSTRUCTION: only a draft closes a phase, and
    /// `RoadmapEngine.status` returns `.needsApproval` for a draft before it ever consults
    /// dependencies — so a gating task can never be `.blocked`. Recorded rather than deleted,
    /// because "why is there no phase-gate case here" is otherwise a fair question.
    func testEscapeHatchChainResolvesToAnActionableTaskNotABlockedOne() {
        let a = t("a", .find)
        let b = t("b", .find, deps: ["a"])
        let c = t("c", .find, deps: ["b"])
        let all = [a, b, c]
        let escapeHatch = RoadmapGating.escapeHatch(for: c, in: all)
        XCTAssertEqual(escapeHatch?.id, "a")
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

    /// A phase-gated card names the draft holding the window — and its escape hatch now lands
    /// on that same draft rather than walking past it. That is the better answer, not a
    /// regression: the draft is `.needsApproval`, so tapping through puts the founder one tap
    /// from unblocking the phase. Under the old rule the gate was a founder-owned task that
    /// could itself be dependency-blocked, which is why the hatch had to walk at all.
    func testStrictBlockerOfAPhaseGatedTaskIsTheGatingDraft() {
        let gate = t("y", .find, drafted: true)
        let later = t("b", .build)
        let all = [gate, later]
        XCTAssertEqual(RoadmapGating.blocker(for: later, in: all)?.id, "y")
        XCTAssertEqual(RoadmapGating.escapeHatch(for: later, in: all)?.id, "y")
        XCTAssertEqual(RoadmapEngine.status(for: gate, in: all), .needsApproval)
    }

    func testStrictBlockerIsNilWhenNothingBlocks() {
        let a = t("a", .find)
        XCTAssertNil(RoadmapGating.blocker(for: a, in: [a]))
    }
}

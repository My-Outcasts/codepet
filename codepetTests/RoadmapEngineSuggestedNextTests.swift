import XCTest
@testable import codepet

final class RoadmapEngineSuggestedNextTests: XCTestCase {
    private func t(_ id: String, _ phase: RoadmapPhase, dept: String?, who: TaskWho = .does,
                   deps: [String] = [], done: Bool = false, drafted: Bool = false) -> RoadmapTask {
        RoadmapTask(id: id, title: id, detail: "", phase: phase, who: who,
                    dependsOn: deps, done: done, drafted: drafted, dept: dept)
    }

    func testEmptyWhenNothingIsActionable() {
        XCTAssertTrue(RoadmapEngine.suggestedNext([], limit: 3).isEmpty)
        XCTAssertTrue(RoadmapEngine.suggestedNext([t("a", .find, dept: "eng", done: true)], limit: 3).isEmpty)
    }

    func testLimitZeroReturnsNothing() {
        XCTAssertTrue(RoadmapEngine.suggestedNext([t("a", .find, dept: "eng")], limit: 0).isEmpty)
    }

    /// The beacon and the suggestion list must never disagree, so nextStep is always first —
    /// even when the loop's own roadmap-order winner is a DIFFERENT task than the beacon.
    ///
    /// "dr" is a drafted task with an unmet dependency ("dep") and sorts earliest (offset 0,
    /// phase .find). Its status is `.needsApproval` (drafted outranks blocked), which the dedup
    /// loop treats as actionable — so without the beacon forcing, the loop would emit "dr"
    /// first. But `nextStep` excludes "dr": it requires `depsSatisfied`, and "dr" depends on
    /// "dep", which isn't done. So `nextStep` instead picks "e" (.find, no deps, `.codepetCanDo`).
    /// Forcing the beacon in must override the loop's natural pick of "dr" and put "e" first —
    /// that's what this test is actually pinning.
    ///
    /// Hand trace: openPhases({dr, dep, e}) = {.find} only ("dr" is drafted+undone in .find, so
    /// .find never settles and the window never advances to .build). status(dr) = .needsApproval
    /// (drafted short-circuits before the window/deps checks). status(dep) = .blocked (.build is
    /// closed). status(e) = .codepetCanDo (.find open, no deps, who = .does). nextStep's filter
    /// (!done && open.contains(phase) && depsSatisfied) admits only "e" — "dr" fails
    /// depsSatisfied, "dep" fails the open-phase check — so nextStep(tasks) == "e".
    ///
    /// If the `if let beacon = nextStep(tasks) { out.append(beacon); … }` forcing block were
    /// deleted, the dedup loop would walk `ordered` = [dr, e, dep] and hit "dr" first (actionable,
    /// unseen department), making it index 0 instead of "e" — this fixture would then fail both
    /// assertions below, which is what makes it discriminating (confirmed by hand: commenting
    /// out the forcing block flips `result.first` to "dr" and the "not at index 0" assertion
    /// fails too).
    func testBeaconIsAlwaysFirst() {
        let dr = t("dr", .find, dept: "design", deps: ["dep"], drafted: true)
        let dep = t("dep", .build, dept: "ops")               // undone dep, closed phase
        let e = t("e", .find, dept: "eng")                    // nextStep's actual pick
        let tasks = [dr, dep, e]

        let picked = RoadmapEngine.suggestedNext(tasks, limit: 3).map(\.id)
        XCTAssertEqual(picked.first, RoadmapEngine.nextStep(tasks)?.id)
        XCTAssertEqual(picked.first, "e")
        // Not merely "the roadmap-order-first task": "dr" sorts before "e" and IS suggestible,
        // but the beacon forcing must keep it out of the lead slot.
        XCTAssertTrue(picked.contains("dr"))
        XCTAssertNotEqual(picked.first, "dr")
    }

    /// The gap that rules out nextMoves: a founder-owned task must be suggestible.
    func testIncludesNeedsYouAndNeedsApproval() {
        let you = t("y", .find, dept: "mkt", who: .you)
        let draft = t("dr", .find, dept: "design", drafted: true)
        let picked = RoadmapEngine.suggestedNext([you, draft], limit: 3).map(\.id)
        XCTAssertTrue(picked.contains("y"))
        XCTAssertTrue(picked.contains("dr"))
    }

    func testOneSuggestionPerDepartment() {
        let tasks = [t("e1", .find, dept: "eng"), t("e2", .find, dept: "eng"),
                     t("m1", .find, dept: "mkt")]
        XCTAssertEqual(RoadmapEngine.suggestedNext(tasks, limit: 3).map(\.id), ["e1", "m1"])
    }

    func testRespectsLimit() {
        let tasks = [t("a", .find, dept: "eng"), t("b", .find, dept: "mkt"),
                     t("c", .find, dept: "design"), t("d", .find, dept: "sales")]
        XCTAssertEqual(RoadmapEngine.suggestedNext(tasks, limit: 2).count, 2)
    }

    /// Confined to the open phase window, exactly like the beacon.
    func testConfinedToTheOpenWindow() {
        let gate = t("y", .find, dept: "mkt", who: .you)   // holds FIND shut
        let later = t("b", .build, dept: "eng")            // would otherwise be suggestible
        XCTAssertEqual(RoadmapEngine.suggestedNext([gate, later], limit: 3).map(\.id), ["y"])
    }

    /// Legacy dept-less tasks are eligible and don't collapse into one shared slot.
    func testDeptLessTasksEachTakeASlot() {
        let tasks = [t("a", .find, dept: nil), t("b", .find, dept: nil)]
        XCTAssertEqual(RoadmapEngine.suggestedNext(tasks, limit: 3).map(\.id), ["a", "b"])
    }

    /// Deliberate product decision, NOT a leak: a drafted task in a CLOSED phase is still
    /// suggested. `status` ranks `needsApproval` above the phase-window check (drafted
    /// short-circuits before `RoadmapGating.openPhases` is even consulted), so a finished draft
    /// waiting on the founder's approval must never become unreachable just because its phase
    /// closed underneath it. This is the one way `suggestedNext` differs from `nextStep`, which
    /// filters `open.contains(phase)` strictly and would never surface "b" here.
    ///
    /// Hand trace: openPhases({y, b}) = {.find} only — "y" (who: .you, undone) sits in .find and
    /// keeps that phase unsettled, so the window never advances to .build. "b" is drafted, in
    /// .build (closed), status = .needsApproval regardless. nextStep(tasks) = "y" (only task
    /// inside the open window with satisfied deps).
    func testDraftedTaskInAClosedPhaseIsStillSuggested() {
        let you = t("y", .find, dept: "mkt", who: .you)        // holds the window shut
        let draft = t("b", .build, dept: "eng", drafted: true) // closed phase, but drafted
        let picked = RoadmapEngine.suggestedNext([you, draft], limit: 3).map(\.id)
        XCTAssertTrue(picked.contains("b"))
    }

    func testBlockedTasksAreNeverSuggested() {
        let a = t("a", .find, dept: "eng")
        let b = t("b", .find, dept: "mkt", deps: ["a"])     // a not done → blocked
        XCTAssertEqual(RoadmapEngine.suggestedNext([a, b], limit: 3).map(\.id), ["a"])
    }
}

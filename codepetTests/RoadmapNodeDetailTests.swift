import XCTest
@testable import codepet

final class RoadmapNodeDetailTests: XCTestCase {
    private func t(_ id: String, _ phase: RoadmapPhase, who: TaskWho = .does, dept: String? = "design",
                   detail: String = "", deps: [String] = [], done: Bool = false,
                   drafted: Bool = false) -> RoadmapTask {
        RoadmapTask(id: id, title: id, detail: detail, phase: phase, who: who,
                    dependsOn: deps, done: done, drafted: drafted, dept: dept)
    }

    func testHeaderFieldsComeFromTheTask() {
        let a = t("a", .foundation, dept: "design")
        let d = RoadmapNodeDetail.build(for: a, in: [a], lang: .en)
        XCTAssertEqual(d.title, "a")
        XCTAssertEqual(d.phaseLabel, RoadmapPhase.foundation.label(.en).uppercased())
        XCTAssertEqual(d.deptName, DepartmentCatalog.find("design")?.name)
        XCTAssertEqual(d.status, RoadmapEngine.status(for: a, in: [a]))
    }

    /// A legacy task with no department must still build a panel.
    func testDeptLessTaskHasNilDeptName() {
        let a = t("a", .find, dept: nil)
        XCTAssertNil(RoadmapNodeDetail.build(for: a, in: [a], lang: .en).deptName)
    }

    func testBecomesTrueIsThePhasesSentence() {
        let a = t("a", .build)
        XCTAssertEqual(RoadmapNodeDetail.build(for: a, in: [a], lang: .en).becomesTrue,
                       RoadmapBoardCopy.becomesTrue(.build, .en))
    }

    func testHowToMoveForwardUsesTheTaskDetailWhenPresent() {
        let a = t("a", .find, detail: "Ask five founders what they use today.")
        XCTAssertEqual(RoadmapNodeDetail.build(for: a, in: [a], lang: .en).howToMoveForward,
                       "Ask five founders what they use today.")
    }

    func testHowToMoveForwardFallsBackWhenDetailIsBlank() {
        let a = t("a", .find, detail: "   ")
        let d = RoadmapNodeDetail.build(for: a, in: [a], lang: .en)
        XCTAssertEqual(d.howToMoveForward, RoadmapBoardCopy.howToFallback(for: d.status, .en))
    }

    func testToCompleteComesFromWho() {
        let a = t("a", .find, who: .you)
        XCTAssertEqual(RoadmapNodeDetail.build(for: a, in: [a], lang: .en).toComplete,
                       RoadmapBoardCopy.toComplete(for: .you, .en))
    }

    // MARK: requiredFirst

    /// Dependencies render whether or not they're met, so the panel shows progress rather than
    /// only obstacles — and each carries its own live status.
    func testDependenciesRenderWithLiveStatusAndSatisfaction() {
        let doneDep = t("d1", .find, done: true)
        let openDep = t("d2", .find, who: .you)
        let target = t("x", .find, deps: ["d1", "d2"])
        let all = [doneDep, openDep, target]
        let reqs = RoadmapNodeDetail.build(for: target, in: all, lang: .en).requiredFirst
        XCTAssertEqual(reqs.count, 2)
        XCTAssertEqual(reqs[0].kind, .task("d1"))
        XCTAssertTrue(reqs[0].satisfied)
        XCTAssertEqual(reqs[1].kind, .task("d2"))
        XCTAssertFalse(reqs[1].satisfied)
        XCTAssertEqual(reqs[1].statusNote, RoadmapEngine.status(for: openDep, in: all).label(.en))
    }

    func testDanglingDependencyIdsAreSkipped() {
        let a = t("a", .find, deps: ["ghost"])
        XCTAssertTrue(RoadmapNodeDetail.build(for: a, in: [a], lang: .en).requiredFirst.isEmpty)
    }

    /// `dependsOn` can carry a repeated id; a `ForEach` over `requiredFirst` needs unique ids,
    /// so a duplicate must collapse to a single requirement rather than producing two rows with
    /// the same `NodeRequirement.id`.
    func testRepeatedDependencyIdYieldsOneRequirement() {
        let d1 = t("d1", .find)
        let target = t("x", .find, deps: ["d1", "d1"])
        let reqs = RoadmapNodeDetail.build(for: target, in: [d1, target], lang: .en).requiredFirst
        XCTAssertEqual(reqs.count, 1)
        XCTAssertEqual(reqs[0].kind, .task("d1"))
    }

    /// The phase window is a requirement too — and it names the phase that has to settle plus
    /// the step holding it shut, which is the one thing Cofounder's panel can't show.
    func testPhaseGatedTaskGetsAPhaseWindowRequirement() {
        let gate = t("y", .find, who: .you)
        let later = t("b", .build)
        let all = [gate, later]
        let reqs = RoadmapNodeDetail.build(for: later, in: all, lang: .en).requiredFirst
        XCTAssertEqual(reqs.count, 1)
        XCTAssertEqual(reqs[0].kind, .phaseWindow(.find))
        XCTAssertFalse(reqs[0].satisfied)
        XCTAssertEqual(reqs[0].label, RoadmapBoardCopy.phaseMustSettle(.find, .en))
        XCTAssertEqual(reqs[0].statusNote, RoadmapBoardCopy.waitingOn("y", lang: .en))
    }

    /// The phase named is the earliest UNSETTLED phase, not the task's own phase.
    func testPhaseWindowRequirementNamesTheEarliestUnsettledPhase() {
        let f = t("f", .find)                      // Codepet-owned → FIND settles
        let gate = t("y", .foundation, who: .you)  // FOUNDATION is what's unsettled
        let later = t("s", .ship)
        let reqs = RoadmapNodeDetail.build(for: later, in: [f, gate, later], lang: .en).requiredFirst
        XCTAssertEqual(reqs.first?.kind, .phaseWindow(.foundation))
    }

    func testInWindowTaskGetsNoPhaseWindowRequirement() {
        let a = t("a", .find)
        let b = t("b", .find, deps: ["a"])
        let reqs = RoadmapNodeDetail.build(for: b, in: [a, b], lang: .en).requiredFirst
        XCTAssertEqual(reqs.count, 1)
        XCTAssertEqual(reqs[0].kind, .task("a"))
    }

    // MARK: unlocks

    func testUnlocksReadsReverseEdgesAndCaps() {
        let src = t("src", .find)
        let dependents = (1...6).map { t("u\($0)", .foundation, deps: ["src"]) }
        let d = RoadmapNodeDetail.build(for: src, in: [src] + dependents, lang: .en)
        XCTAssertEqual(d.unlocks.count, RoadmapNodeDetail.maxUnlocks)
        XCTAssertEqual(d.unlocks.first, "u1")
    }

    func testUnlocksEmptyWhenNothingDependsOnIt() {
        let a = t("a", .find)
        XCTAssertTrue(RoadmapNodeDetail.build(for: a, in: [a], lang: .en).unlocks.isEmpty)
    }

    func testBuildsInVietnameseToo() {
        let a = t("a", .find, who: .you)
        let en = RoadmapNodeDetail.build(for: a, in: [a], lang: .en)
        let vi = RoadmapNodeDetail.build(for: a, in: [a], lang: .vi)
        XCTAssertNotEqual(en.becomesTrue, vi.becomesTrue)
        XCTAssertNotEqual(en.toComplete, vi.toComplete)
    }
}

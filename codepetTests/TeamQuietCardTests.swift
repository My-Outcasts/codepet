// codepetTests/TeamQuietCardTests.swift
import XCTest
@testable import codepet

/// The quieter Team Build cards (6 Oct design pass): the plan reads as First / Then / Last instead
/// of a "waits for" line under every row, the waiting states are one line with no second
/// "Cooking…" signal, and a finished run leads with seeing the page. The views only read these.
final class TeamQuietCardTests: XCTestCase {
    private func step(_ id: String, _ dept: String, _ deps: [String] = []) -> WorkStep {
        WorkStep(id: id, dept: dept, title: "T \(id)", instruction: "i", kind: "doc", dependsOn: deps)
    }

    /// The build-8 plan from the 6 Oct run: one spec, four steps that each wait only on it, then
    /// the build. Three stages, the middle one four wide.
    private var lockerPlan: WorkPlan {
        WorkPlan(title: "Lockerly Slot Booking", slug: "slots", summary: "s", projectType: "web app", steps: [
            step("s1", "eng"),
            step("s2", "design", ["s1"]), step("s3", "support", ["s1"]),
            step("s4", "legal", ["s1"]), step("s5", "ops", ["s1"]),
            step("build", "eng", ["s1", "s2", "s3", "s4", "s5"]),
        ])
    }

    // MARK: stages

    func testStepsGroupByHowManyStepsTheyWaitOn() {
        let stages = TeamPlanStages.group(lockerPlan)
        XCTAssertEqual(stages.map { $0.map(\.id) }, [["s1"], ["s2", "s3", "s4", "s5"], ["build"]])
    }

    /// A step's stage is one past its DEEPEST dependency, not its first: in a chain s1 → s2 → s3
    /// with s3 also waiting on s1, s3 still belongs after s2.
    func testAStepSitsAfterItsDeepestDependency() {
        let plan = WorkPlan(title: "t", slug: "t", summary: "", projectType: "", steps: [
            step("s1", "support"), step("s2", "support", ["s1"]), step("s3", "legal", ["s1", "s2"]),
            step("build", "eng", ["s1", "s2", "s3"]),
        ])
        XCTAssertEqual(TeamPlanStages.group(plan).map { $0.map(\.id) }, [["s1"], ["s2"], ["s3"], ["build"]])
    }

    /// Independent steps share the first stage, in plan order. A dependency on an id the plan does
    /// not contain is ignored rather than pushing the step later.
    func testIndependentStepsShareAStageAndUnknownDependenciesAreIgnored() {
        let plan = WorkPlan(title: "t", slug: "t", summary: "", projectType: "", steps: [
            step("s1", "mkt"), step("s2", "legal", ["nope"]), step("build", "eng", ["s1", "s2"]),
        ])
        XCTAssertEqual(TeamPlanStages.group(plan).map { $0.map(\.id) }, [["s1", "s2"], ["build"]])
    }

    func testStageLabels() {
        XCTAssertNil(TeamPlanStages.label(0, of: 1, lang: .en), "one stage needs no label")
        XCTAssertEqual(TeamPlanStages.label(0, of: 2, lang: .en), "First")
        XCTAssertEqual(TeamPlanStages.label(1, of: 2, lang: .en), "Last")
        XCTAssertEqual((0..<4).map { TeamPlanStages.label($0, of: 4, lang: .en) }, ["First", "Then", "Then", "Last"])
        XCTAssertEqual((0..<3).map { TeamPlanStages.label($0, of: 3, lang: .vi) }, ["Trước", "Sau đó", "Cuối"])
    }

    // MARK: ready

    private func finished(_ minutes: [Double], depts: [String]) -> TeamRun {
        let steps = depts.enumerated().map { step("s\($0.offset)", $0.element) }
        var r = TeamRun(request: "r", createdAt: Date(), brief: nil,
                        plan: WorkPlan(title: "t", slug: "t", summary: "", projectType: "", steps: steps))
        let t0 = Date(timeIntervalSince1970: 1_000_000)
        for i in r.steps.indices {
            r.steps[i].status = .done
            r.steps[i].startedAt = t0
            r.steps[i].finishedAt = t0.addingTimeInterval(minutes[i] * 60)
        }
        r.phase = .ready
        return r
    }

    /// The finished card's one line: how long from the first start to the last finish, and how
    /// many departments (each counted once — two Engineering steps are one department).
    func testTheReadyLineCountsElapsedTimeAndDistinctDepartments() {
        let r = finished([2, 5, 16.4], depts: ["eng", "design", "eng"])
        XCTAssertEqual(TeamBuildCopy.readySummary(r, lang: .en), "Built in 16 min by 2 departments.")
        XCTAssertEqual(TeamBuildCopy.readySummary(r, lang: .vi), "Xong trong 16 phút, 2 phòng ban cùng làm.")
    }

    func testTheReadyLineHandlesOneDepartmentAndUnderAMinute() {
        let r = finished([0.5], depts: ["eng"])
        XCTAssertEqual(TeamBuildCopy.readySummary(r, lang: .en), "Built in under a minute by 1 department.")
    }

    /// A run restored without timestamps says nothing about time rather than "0 min".
    func testTheReadyLineWithoutTimesNamesOnlyTheDepartments() {
        var r = finished([3], depts: ["eng"])
        r.steps[0].startedAt = nil
        XCTAssertEqual(TeamBuildCopy.readySummary(r, lang: .en), "Built by 1 department.")
    }

    // MARK: primary action

    /// Founder decision (6 Oct): see the page first, approve beside it. With nothing to open,
    /// Approve is the primary action — a card must never have no primary.
    func testOpeningThePageIsPrimaryWhenThereIsOne() {
        XCTAssertEqual(TeamReadyAction.primary(isNodeProject: true, hasIndexHTML: false), .runDev)
        XCTAssertEqual(TeamReadyAction.primary(isNodeProject: false, hasIndexHTML: true), .openIndex)
        XCTAssertEqual(TeamReadyAction.primary(isNodeProject: false, hasIndexHTML: false), .approve)
    }

    // MARK: one waiting signal

    /// While the team is being gathered or the work planned, that row IS the progress signal;
    /// the generic "Cooking…" typing row under it was a second one saying less.
    func testTheTypingRowStepsAsideWhileTheTeamGathersOrPlans() {
        XCTAssertTrue(TeamWaiting.showsTypingRow(typing: true, convening: false, planning: false))
        XCTAssertFalse(TeamWaiting.showsTypingRow(typing: true, convening: true, planning: false))
        XCTAssertFalse(TeamWaiting.showsTypingRow(typing: true, convening: false, planning: true))
        XCTAssertFalse(TeamWaiting.showsTypingRow(typing: false, convening: false, planning: false))
    }

    /// The planning line shows who the room seated: department keys only, each once, in seat
    /// order. Chief of staff and the devil's advocate carry no department key.
    func testThePlanningPetsAreTheRoomsDepartments() {
        let meta: [(String, String?)] = [("cos", nil), ("eng_lead", "eng"), ("da", nil), ("fin_lead", "fin"), ("eng2", "eng")]
        XCTAssertEqual(TeamWaiting.departments(seated: meta.map { $0.1 }), ["eng", "fin"])
    }
}

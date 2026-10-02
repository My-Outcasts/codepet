// codepetTests/DepartmentWorkingStatusTests.swift
import XCTest
@testable import codepet

/// Build 6, bug #10: Engineering read "LATER" on the Company page while it was building the
/// founder's project — it had no roadmap tasks, and live work never reached the status.
final class DepartmentWorkingStatusTests: XCTestCase {
    private let plan = WorkPlan(
        title: "Page", slug: "page", summary: "s", projectType: "static landing page",
        steps: [
            WorkStep(id: "s1", dept: "mkt", title: "Copy", instruction: "i", kind: "doc", dependsOn: []),
            WorkStep(id: "s2", dept: "legal", title: "Consent", instruction: "i", kind: "doc", dependsOn: []),
            WorkStep(id: "build", dept: "eng", title: "Build", instruction: "i", kind: "other", dependsOn: ["s1", "s2"]),
        ])

    private func run(_ statuses: [String: TeamStepStatus], phase: TeamRunPhase = .running) -> TeamRun {
        var r = TeamRun(request: "a page", createdAt: Date(), brief: nil, plan: plan)
        r.phase = phase
        for (id, s) in statuses {
            if let i = r.steps.firstIndex(where: { $0.stepId == id }) { r.steps[i].status = s }
        }
        return r
    }

    func testRunningTeamStepsMarkTheirDepartments() {
        let keys = DepartmentCatalog.workingKeys(teamRun: run(["s1": .running, "s2": .done]),
                                                 producingDeptNames: [], codeRunning: false)
        XCTAssertEqual(keys, ["mkt"])
    }

    func testAssemblingIsEngineeringsWork() {
        let keys = DepartmentCatalog.workingKeys(teamRun: run(["s1": .done, "s2": .done], phase: .assembling),
                                                 producingDeptNames: [], codeRunning: false)
        XCTAssertEqual(keys, ["eng"])
    }

    func testChatRunsAndCodeRunsCount() {
        let keys = DepartmentCatalog.workingKeys(teamRun: nil, producingDeptNames: ["Finance", "Nobody"],
                                                 codeRunning: true)
        XCTAssertEqual(keys, ["fin", "eng"])
    }

    /// The bug itself: a department with no roadmap tasks but live work is "working", not "later".
    func testWorkingOutranksLaterAndTheRoadmap() {
        let tasks = [RoadmapTask(id: "t1", title: "Price it", detail: "", phase: .build, who: .does, dept: "fin")]
        let s = DepartmentCatalog.summaries(tasks: tasks, working: ["eng", "fin"])
        XCTAssertEqual(s.first { $0.department.key == "eng" }?.status, .working)
        XCTAssertEqual(s.first { $0.department.key == "fin" }?.status, .working)
        XCTAssertEqual(DepartmentCatalog.summaries(tasks: tasks).first { $0.department.key == "eng" }?.status,
                       .later, "nothing running → unchanged")
    }
}

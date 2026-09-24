// codepetTests/TeamRunPersistenceTests.swift
import XCTest
@testable import codepet

final class TeamRunPersistenceTests: XCTestCase {
    func testCompanyStateWithoutTeamRunsDecodesToEmpty() throws {
        let json = #"{"brief":{},"departments":[],"library":[],"stage":"idea","companionId":"byte"}"#
        let state = try JSONDecoder().decode(CompanyState.self, from: Data(json.utf8))
        XCTAssertEqual(state.teamRuns, [])
    }
    func testTeamRunRoundTripsIncludingAFailedReason() throws {
        let plan = WorkPlan(title: "t", slug: "t", summary: "", projectType: "",
                            steps: [WorkStep(id: "build", dept: "eng", title: "b", instruction: "", kind: "other", dependsOn: [])])
        var run = TeamRun(request: "pants", createdAt: Date(timeIntervalSince1970: 0), brief: nil, plan: plan)
        run.steps[0].status = .failed("Timed out")
        let back = try JSONDecoder().decode(TeamRun.self, from: JSONEncoder().encode(run))
        XCTAssertEqual(back, run)
    }
    func testANewRunStartsPlannedWithEveryStepWaiting() {
        let plan = WorkPlan(title: "t", slug: "t", summary: "", projectType: "",
                            steps: [WorkStep(id: "s1", dept: "mkt", title: "a", instruction: "", kind: "doc", dependsOn: []),
                                    WorkStep(id: "build", dept: "eng", title: "b", instruction: "", kind: "other", dependsOn: ["s1"])])
        let run = TeamRun(request: "x", createdAt: Date(), brief: nil, plan: plan)
        XCTAssertEqual(run.phase, .planned)
        XCTAssertEqual(run.steps.map(\.status), [.waiting, .waiting])
        XCTAssertTrue(run.isActive)
    }
}

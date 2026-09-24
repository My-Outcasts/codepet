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

    // MARK: - Lenient decoding (one bad run must not lose the company)

    private func run(_ phase: TeamRunPhase, at t: TimeInterval, draft: Bool = true) -> TeamRun {
        let plan = WorkPlan(title: "t", slug: "t", summary: "", projectType: "",
                            steps: [WorkStep(id: "s1", dept: "mkt", title: "a", instruction: "", kind: "doc", dependsOn: []),
                                    WorkStep(id: "build", dept: "eng", title: "b", instruction: "", kind: "other", dependsOn: ["s1"])])
        var r = TeamRun(request: "r\(Int(t))", createdAt: Date(timeIntervalSince1970: t), brief: nil, plan: plan)
        r.phase = phase
        if draft {
            r.steps[0].status = .done
            r.steps[0].draft = Deliverable(kind: .doc, title: "a", body: "body")
        }
        return r
    }

    /// A doc whose teamRuns array holds one element that no longer decodes, next to a good one.
    private func docJSON() throws -> Data {
        let good = try JSONSerialization.jsonObject(with: JSONEncoder().encode(run(.filed, at: 1)))
        let bad: [String: Any] = ["id": "x", "phase": "not-a-phase"]
        let dict: [String: Any] = ["brief": ["projectName": "Pants"], "stage": "idea", "companionId": "byte",
                                   "teamRuns": [good, bad]]
        return try JSONSerialization.data(withJSONObject: dict)
    }

    func testOneMalformedRunDoesNotLoseTheCompanyDoc() throws {
        let doc = try JSONDecoder().decode(CompanyDoc.self, from: docJSON())
        let state = CompanyData.state(from: doc)
        XCTAssertEqual(state.brief.projectName, "Pants", "the company itself must still load")
        XCTAssertEqual(state.teamRuns.map(\.request), ["r1"], "the good run survives, the bad one is skipped")
    }

    func testOneMalformedRunDoesNotLoseTheCompanyState() throws {
        let state = try JSONDecoder().decode(CompanyState.self, from: docJSON())
        XCTAssertEqual(state.brief.projectName, "Pants")
        XCTAssertEqual(state.teamRuns.map(\.request), ["r1"])
    }

    // MARK: - Retention (the doc has a 1 MiB limit)

    func testRetentionKeepsAtMostTenAndDropsTheOldestFirst() {
        let runs = (0..<14).map { run(.filed, at: TimeInterval($0)) }
        let kept = TeamRun.retained(runs)
        XCTAssertEqual(kept.count, 10)
        XCTAssertEqual(kept.map(\.request), (4..<14).map { "r\($0)" })
    }

    func testRetentionNeverDropsAnActiveOrReadyRun() {
        // The two oldest are the ones the founder can still act on.
        let runs = [run(.ready, at: 0), run(.running, at: 1)] + (2..<14).map { run(.filed, at: TimeInterval($0)) }
        let kept = TeamRun.retained(runs)
        XCTAssertEqual(kept.count, 10)
        XCTAssertTrue(kept.contains { $0.request == "r0" && $0.phase == .ready })
        XCTAssertTrue(kept.contains { $0.request == "r1" && $0.phase == .running })
        XCTAssertEqual(kept.first?.request, "r0", "order is preserved")
    }

    func testFiledAndCancelledRunsPersistWithoutDrafts() {
        let kept = TeamRun.retained([run(.filed, at: 0), run(.cancelled, at: 1), run(.ready, at: 2), run(.running, at: 3)])
        XCTAssertNil(kept[0].steps[0].draft, "a filed run's drafts are in the Library already")
        XCTAssertNil(kept[1].steps[0].draft)
        XCTAssertNotNil(kept[2].steps[0].draft, "a ready run still needs its drafts to be approved")
        XCTAssertNotNil(kept[3].steps[0].draft, "a running run feeds drafts downstream")
        XCTAssertEqual(kept[0].steps[0].status, .done, "only the draft is stripped")
        XCTAssertEqual(kept[0].plan, run(.filed, at: 0).plan, "the plan stays: the Library resolves departments from it")
    }

    // MARK: - The real load path

    /// Round-trips a run the way `CompanyData.load` reads it back: the saver's payload, through
    /// JSONSerialization (standing in for Firestore's dictionary), decoded as a `CompanyDoc`, then
    /// mapped by `CompanyData.state(from:)`. Dates and a `.failed` reason included.
    func testATeamRunSurvivesTheRealSaveAndLoadPath() throws {
        var r = run(.failed, at: 1_700_000_000.25)
        r.steps[0].startedAt = Date(timeIntervalSince1970: 1_700_000_001.5)
        r.steps[0].finishedAt = Date(timeIntervalSince1970: 1_700_000_002.75)
        r.steps[1].status = .failed("x")
        r.projectPath = "/tmp/p"
        let payload = CompanyData.teamRunsPayload([r])
        XCTAssertNotNil(payload["teamRuns"], "the payload must carry the runs")
        let data = try JSONSerialization.data(withJSONObject: payload)
        let doc = try JSONDecoder().decode(CompanyDoc.self, from: data)
        let state = CompanyData.state(from: doc)
        XCTAssertEqual(state.teamRuns, [r])
        XCTAssertEqual(state.teamRuns.first?.steps[1].status, .failed("x"))
        XCTAssertEqual(state.teamRuns.first?.createdAt, Date(timeIntervalSince1970: 1_700_000_000.25))
    }
}

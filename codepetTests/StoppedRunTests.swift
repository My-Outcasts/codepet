// codepetTests/StoppedRunTests.swift
import XCTest
@testable import codepet

/// CP-034: a stopped Team Build said what did NOT happen — every row marked Cancelled — and
/// offered nothing to do next. It now says what happened in one sentence and offers Discard.
@MainActor
final class StoppedRunTests: XCTestCase {
    private typealias F = TeamBuildFixture
    private var root: URL!

    override func setUp() {
        super.setUp()
        CompanyStore.execStepNanos = 0
        root = FileManager.default.temporaryDirectory.appendingPathComponent("stop-\(UUID().uuidString)")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: root)
        super.tearDown()
    }

    private func run(done: Int, started: Bool) -> TeamRun {
        var r = TeamRun(request: "pants", createdAt: Date(), brief: nil, plan: F.plan)
        r.phase = .cancelled
        for i in r.steps.indices {
            r.steps[i].status = i < done ? .done : .cancelled
            if started && i <= done { r.steps[i].startedAt = Date() }
        }
        return r
    }

    func testTheSummarySaysHowFarItGot() {
        XCTAssertEqual(TeamBuildCopy.stoppedSummary(run(done: 1, started: true), lang: .en),
                       "Stopped after 1 of 3 steps. Marketing's work is kept here.")
        XCTAssertEqual(TeamBuildCopy.stoppedSummary(run(done: 0, started: true), lang: .en),
                       "Stopped before any step finished. Nothing was built.")
        XCTAssertEqual(TeamBuildCopy.stoppedSummary(run(done: 0, started: false), lang: .en),
                       "Cancelled before it started. Nothing ran.")
        XCTAssertEqual(TeamBuildCopy.stoppedSummary(run(done: 0, started: false), lang: .vi),
                       "Đã huỷ trước khi bắt đầu. Chưa có gì chạy.")
    }

    /// Discard removes the run from the chat and from the saved list, and the next Team build can
    /// start; a run that is still going cannot be discarded.
    func testDiscardRemovesAStoppedRun() async throws {
        let probe = F.Probe()
        let s = F.store(probe: probe, root: root)
        let planned = await F.planned(s)
        XCTAssertTrue(planned)
        let id = try XCTUnwrap(s.teamRun?.run?.id)

        await s.discardTeamRun()
        XCTAssertNotNil(s.teamRun, "a planned run is not discarded")

        s.cancelTeamPlan()
        XCTAssertEqual(s.teamRun?.run?.phase, .cancelled)
        await s.discardTeamRun()
        XCTAssertNil(s.teamRun)
        // The stop's own save is still queued behind the coordinator's save chain; it must not
        // put the discarded run back when it lands.
        try? await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertFalse(s.company.teamRuns.contains { $0.id == id })
        XCTAssertFalse(probe.saves.last?.runs.contains { $0.id == id } ?? true, "the saved list drops it too")
        XCTAssertTrue(s.teamBuildAvailable)
    }
}

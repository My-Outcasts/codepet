// codepetTests/TeamRunFollowTests.swift
import XCTest
@testable import codepet

/// The transcript follows a Team Build card through the moments the founder must act on.
///
/// 1 Oct, build 6, real account: a Team Build finished and the chat did not move. The card is ONE
/// message that grows, and the transcript only scrolled when the message COUNT changed, so the
/// finished card's Approve / Run it / Open in Finder row sat under the composer, out of sight.
final class TeamRunFollowTests: XCTestCase {
    private func run(_ phase: TeamRunPhase, done: Int = 0, total: Int = 3) -> TeamRun {
        let steps = (0..<total).map { WorkStep(id: "s\($0)", dept: "mkt", title: "t\($0)", instruction: "", kind: "doc", dependsOn: []) }
        var r = TeamRun(id: "r1", request: "landing page", createdAt: Date(timeIntervalSince1970: 0),
                        brief: nil, plan: WorkPlan(title: "p", slug: "p", summary: "", projectType: "web", steps: steps))
        r.phase = phase
        for i in 0..<done { r.steps[i].status = .done }
        return r
    }

    func testReachingReadyChangesTheKey() {
        XCTAssertNotEqual(TeamRunFollow.key(run(.assembling, done: 3)), TeamRunFollow.key(run(.ready, done: 3)),
                          "the Approve row appears on .ready — the transcript must move to it")
    }

    func testTheGoCancelPlanAndAFailureChangeTheKeyToo() {
        XCTAssertNotEqual(TeamRunFollow.key(nil), TeamRunFollow.key(run(.planned)))
        XCTAssertNotEqual(TeamRunFollow.key(run(.running, done: 1)), TeamRunFollow.key(run(.failed, done: 1)))
    }

    func testAFinishedStepChangesTheKey() {
        XCTAssertNotEqual(TeamRunFollow.key(run(.running, done: 1)), TeamRunFollow.key(run(.running, done: 2)))
    }

    /// A step merely starting is not news the card grows for; following it would yank a founder
    /// who scrolled up to read a draft every few seconds.
    func testAStepStartingDoesNotChangeTheKey() {
        var a = run(.running, done: 1); var b = a
        b.steps[1].status = .running
        a.steps[1].status = .waiting
        XCTAssertEqual(TeamRunFollow.key(a), TeamRunFollow.key(b))
    }

    func testTheTargetIsTheMessageCarryingTheRunElseTheUnanchoredCard() {
        var m = CopilotMessage(role: .companion, text: "")
        m.teamRunId = "r1"
        XCTAssertEqual(TeamRunFollow.target(runId: "r1", messages: [m]), m.id)
        XCTAssertEqual(TeamRunFollow.target(runId: "r1", messages: []), TeamRunFollow.unanchoredId)
    }
}

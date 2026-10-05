// codepetTests/TeamRunPlacementTests.swift
import XCTest
@testable import codepet

/// Where the store's team run is drawn: inline under its message, or at the transcript's
/// bottom when no message carries it (a run restored on relaunch) — never both, and never
/// leaking a finished run into later conversations.
final class TeamRunPlacementTests: XCTestCase {
    private func run(_ phase: TeamRunPhase) -> TeamRun {
        let plan = WorkPlan(title: "Pants", slug: "pants", summary: "", projectType: "site",
                            steps: [WorkStep(id: "build", dept: "eng", title: "Build", instruction: "",
                                             kind: "other", dependsOn: [])])
        var r = TeamRun(id: "run-1", request: "pants page", createdAt: Date(), brief: nil, plan: plan)
        r.phase = phase
        return r
    }

    func testActiveOrReadyRunWithNoMessageIsShownAtTheBottom() {
        for phase in [TeamRunPhase.planned, .running, .assembling, .failed, .ready] {
            XCTAssertTrue(TeamRunPlacement.showsUnanchored(run: run(phase), messageRunIds: [],
                                                           stickyRunId: nil, stickyKey: nil,
                                                           transcriptKey: "t1"), "\(phase)")
        }
    }

    func testRunCarriedByAMessageIsNeverDrawnTwice() {
        XCTAssertFalse(TeamRunPlacement.showsUnanchored(run: run(.running), messageRunIds: ["run-1"],
                                                        stickyRunId: "run-1", stickyKey: "t1",
                                                        transcriptKey: "t1"))
    }

    func testNoRunShowsNothing() {
        XCTAssertFalse(TeamRunPlacement.showsUnanchored(run: nil, messageRunIds: [],
                                                        stickyRunId: nil, stickyKey: nil, transcriptKey: nil))
    }

    func testFinishedRunStaysInTheConversationItWasDrawnIn() {
        for phase in [TeamRunPhase.filed, .cancelled] {
            XCTAssertTrue(TeamRunPlacement.showsUnanchored(run: run(phase), messageRunIds: [],
                                                           stickyRunId: "run-1", stickyKey: "t1",
                                                           transcriptKey: "t1"), "\(phase)")
        }
    }

    /// The review's bug: drawn at the bottom of one conversation, then approved or stopped,
    /// the card followed the founder into every later conversation.
    func testFinishedRunDoesNotFollowIntoAnotherConversation() {
        for phase in [TeamRunPhase.filed, .cancelled] {
            XCTAssertFalse(TeamRunPlacement.showsUnanchored(run: run(phase), messageRunIds: [],
                                                            stickyRunId: "run-1", stickyKey: "t1",
                                                            transcriptKey: "t2"), "\(phase)")
            XCTAssertFalse(TeamRunPlacement.showsUnanchored(run: run(phase), messageRunIds: [],
                                                            stickyRunId: "run-1", stickyKey: "t1",
                                                            transcriptKey: nil), "\(phase)")
        }
    }

    func testFinishedRunNeverDrawnHereIsNotShown() {
        XCTAssertFalse(TeamRunPlacement.showsUnanchored(run: run(.filed), messageRunIds: [],
                                                        stickyRunId: nil, stickyKey: nil, transcriptKey: "t1"))
    }

    /// 5 Oct, real account: a finished build waiting on Approve was drawn at the foot of EVERY
    /// conversation — new ones included, and below every reply. Its own thread carries it
    /// inline (threads are archived with `teamRunId`), so it belongs there and nowhere else.
    /// Same for every phase that waits on the founder (Go, Continue, Approve) — those can sit
    /// for days.
    func testRunWaitingOnTheFounderCarriedByAnotherThreadIsNotDrawnHere() {
        for phase in [TeamRunPhase.planned, .failed, .ready] {
            XCTAssertFalse(TeamRunPlacement.showsUnanchored(run: run(phase), messageRunIds: [],
                                                            elsewhereRunIds: ["run-1"],
                                                            stickyRunId: nil, stickyKey: nil,
                                                            transcriptKey: "t2"), "\(phase)")
        }
    }

    /// The fallback the bottom card exists for: no thread carries the run, so Approve must
    /// stay reachable somewhere.
    func testReadyRunNoThreadCarriesIsStillDrawn() {
        XCTAssertTrue(TeamRunPlacement.showsUnanchored(run: run(.ready), messageRunIds: [],
                                                       elsewhereRunIds: ["other-run"],
                                                       stickyRunId: nil, stickyKey: nil,
                                                       transcriptKey: "t2"))
    }

    /// A run still working keeps following the founder: it lasts minutes, and Stop has to be
    /// within reach wherever they are.
    func testWorkingRunCarriedByAnotherThreadStillFollows() {
        for phase in [TeamRunPhase.running, .assembling] {
            XCTAssertTrue(TeamRunPlacement.showsUnanchored(run: run(phase), messageRunIds: [],
                                                           elsewhereRunIds: ["run-1"],
                                                           stickyRunId: nil, stickyKey: nil,
                                                           transcriptKey: "t2"), "\(phase)")
        }
    }
}

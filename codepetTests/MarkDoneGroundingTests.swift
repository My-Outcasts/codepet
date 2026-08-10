// codepetTests/MarkDoneGroundingTests.swift
import XCTest
@testable import codepet

/// The companion may OFFER to complete a task, and must not speak as though it already did.
///
/// Aug 7 this grounding said "you cannot mark a roadmap task done — you have no tool". Aug 8
/// `complete_task` shipped and that sentence became a lie sitting beside the tool that contradicts
/// it: the model handed a verb and told in the same prompt it has no such verb would either refuse
/// to use it or produce a confused turn. What survives is the half that was never about capability
/// — never narrate a change the founder has not confirmed.
final class MarkDoneGroundingTests: XCTestCase {

    private func ctx(_ tasks: [RoadmapTask]) -> String {
        ChatContext.compose(brief: CompanyBrief(), tasks: tasks)
    }

    private var mine: [RoadmapTask] {
        [RoadmapTask(id: "a", title: "Define the riskiest assumption", detail: "",
                     phase: .find, who: .you)]
    }

    /// The contradiction that would have silenced the new verb.
    func testTheGroundingDoesNotDenyTheToolItIsGivenAlongside() {
        let c = ctx(mine)
        XCTAssertFalse(c.contains("You cannot mark a roadmap task done"),
                       "the model must not be told it lacks a tool it was just handed")
        XCTAssertTrue(c.contains("complete_task"))
    }

    /// The half that survives: an offer is not a change.
    func testItStillForbidsNarratingAChangeThatHasNotHappened() {
        let c = ctx(mine)
        XCTAssertTrue(c.contains("consider it done"))
        XCTAssertTrue(c.contains("nothing changes until they"))
    }

    /// A Codepet-drafted task is completed by approval, never by this verb — stated in the prompt
    /// as well as enforced by the `open_tasks` filter, because the model should not have to infer
    /// it from an absence.
    func testItNamesTheDraftedTaskRule() {
        XCTAssertTrue(ctx(mine).contains("approving the draft"))
    }

    /// No roadmap, nothing to promise about — the block would be noise.
    func testNoRoadmapMeansNoMarkDoneBlock() {
        XCTAssertFalse(ctx([]).contains("complete_task"))
    }
}

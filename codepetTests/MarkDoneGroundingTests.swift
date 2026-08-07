// codepetTests/MarkDoneGroundingTests.swift
import XCTest
@testable import codepet

/// The companion must not narrate completing a task it cannot complete.
final class MarkDoneGroundingTests: XCTestCase {

    private func ctx(_ tasks: [RoadmapTask]) -> String {
        ChatContext.compose(brief: CompanyBrief(), tasks: tasks)
    }

    /// Aug 7: "You can consider this step done" → "let's mark it done in the roadmap" → "Sure —
    /// this takes you there" + a nav chip. Nothing was marked.
    func testTheGroundingForbidsImplyingTheRoadmapChanged() {
        let c = ctx([RoadmapTask(id: "a", title: "Define the riskiest assumption", detail: "",
                                 phase: .find, who: .you)])
        XCTAssertTrue(c.contains("You cannot mark a roadmap task done"))
        XCTAssertTrue(c.contains("consider it done"))
        XCTAssertTrue(c.contains("cannot do it from here"))
    }

    /// No roadmap, nothing to promise about — the block would be noise.
    func testNoRoadmapMeansNoMarkDoneBlock() {
        XCTAssertFalse(ctx([]).contains("You cannot mark a roadmap task done"))
    }
}

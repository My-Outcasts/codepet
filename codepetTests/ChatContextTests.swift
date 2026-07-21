// codepetTests/ChatContextTests.swift
import XCTest
@testable import codepet

final class ChatContextTests: XCTestCase {
    func testComposeIncludesBriefNextStepAndProgress() {
        let brief = CompanyBrief(projectName: "Codepet", oneLiner: "AI coding companion")
        let tasks = [
            RoadmapTask(id: "a", title: "Interview users", detail: "", phase: .find, who: .you),
            RoadmapTask(id: "b", title: "Ship auth", detail: "", phase: .build, who: .does, done: true),
        ]
        let ctx = ChatContext.compose(brief: brief, tasks: tasks)
        XCTAssertTrue(ctx.contains("Codepet"))          // brief signal
        XCTAssertTrue(ctx.contains("Interview users"))  // next step / open task
        XCTAssertTrue(ctx.contains("%"))                // progress
    }
    func testComposeEmptyStillNonEmpty() {
        let ctx = ChatContext.compose(brief: CompanyBrief(), tasks: [])
        XCTAssertFalse(ctx.isEmpty)
        XCTAssertTrue(ctx.contains("No brief yet"))
    }
    func testCopilotMessageIdentityAndEquatable() {
        let m = CopilotMessage(id: "1", role: .me, text: "hi")
        XCTAssertEqual(m.id, "1")
        XCTAssertEqual(m, CopilotMessage(id: "1", role: .me, text: "hi"))
        XCTAssertNotEqual(m, CopilotMessage(id: "2", role: .companion, text: "hi"))
    }
}

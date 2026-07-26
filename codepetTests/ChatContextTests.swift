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

    // MARK: - selectPriorWork

    func testSelectPriorWorkRanksByQueryOverlap() {
        let relevant = Deliverable(id: "1", kind: .doc, title: "Pricing strategy",
                                    body: "We priced the subscription at $9 per month for early adopters.",
                                    createdAt: "2026-01-01T00:00:00Z")
        let unrelated = Deliverable(id: "2", kind: .post, title: "Launch tweet",
                                     body: "Excited to announce our new mascot artwork today.",
                                     createdAt: "2026-01-02T00:00:00Z")
        let picked = ChatContext.selectPriorWork([unrelated, relevant], query: "What was our pricing subscription plan?")
        XCTAssertEqual(picked.first?.id, "1", "the deliverable sharing words with the query should rank first")
    }

    func testSelectPriorWorkNilQueryFallsBackToMostRecent() {
        let older = Deliverable(id: "old", kind: .doc, title: "Old doc", body: "some body text",
                                 createdAt: "2026-01-01T00:00:00Z")
        let newer = Deliverable(id: "new", kind: .doc, title: "New doc", body: "some body text",
                                 createdAt: "2026-02-01T00:00:00Z")
        let picked = ChatContext.selectPriorWork([older, newer], query: nil)
        XCTAssertEqual(picked.map { $0.id }, ["new", "old"])
    }

    func testSelectPriorWorkCapsAtMax() {
        let items = (0..<10).map { i in
            Deliverable(id: "\(i)", kind: .doc, title: "Doc \(i)", body: "body \(i)",
                        createdAt: "2026-01-0\(i)T00:00:00Z")
        }
        let picked = ChatContext.selectPriorWork(items, query: nil, max: 3)
        XCTAssertEqual(picked.count, 3)
    }

    // MARK: - compose richer grounding

    func testComposeIncludesDepartmentLineWhenTasksHaveDepts() {
        let brief = CompanyBrief(projectName: "Codepet")
        let tasks = [
            RoadmapTask(id: "a", title: "Ship auth", detail: "", phase: .build, who: .does, dept: "eng"),
        ]
        let ctx = ChatContext.compose(brief: brief, tasks: tasks)
        XCTAssertTrue(ctx.contains("Departments:"))
        XCTAssertTrue(ctx.contains("Engineering"))
        XCTAssertTrue(ctx.contains("Ship auth"))
    }

    func testComposeIncludesPriorWorkExcerptWhenLibraryNonEmpty() {
        let brief = CompanyBrief(projectName: "Codepet")
        let deliverable = Deliverable(id: "1", kind: .doc, title: "Pricing strategy",
                                       body: "We priced the subscription at $9 per month.",
                                       createdAt: "2026-01-01T00:00:00Z")
        let ctx = ChatContext.compose(brief: brief, tasks: [], library: [deliverable], query: "pricing")
        XCTAssertTrue(ctx.contains("Already-shipped work"))
        XCTAssertTrue(ctx.contains("Pricing strategy"))
    }

    func testComposeUnchangedForEmptyCase() {
        let ctx = ChatContext.compose(brief: CompanyBrief(), tasks: [])
        XCTAssertTrue(ctx.contains("No brief yet"))
        XCTAssertTrue(ctx.contains("Roadmap progress:"))
        XCTAssertFalse(ctx.contains("Open tasks:"))
        XCTAssertFalse(ctx.contains("Departments:"))
        XCTAssertFalse(ctx.contains("Already-shipped work"))
    }
}

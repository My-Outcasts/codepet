// codepetTests/ApprovalParityTests.swift
import XCTest
@testable import codepet

/// Approving is approving, wherever the button is.
///
/// There were two Approve buttons with two different outcomes. `approveTask` (the Tasks board's
/// draft preview) filed the deliverable AND completed the task; `approveDraft` (the chat card, on
/// the surface the founder actually uses) filed the deliverable and stopped — so the roadmap task
/// stayed `drafted` forever, the card kept reading "Review", the phase never settled, and every
/// task behind it stayed blocked. Permanently, because the chat card will not offer Approve twice.
///
/// It also broke the founder's stated model — "only after the user reviews and approves it is the
/// task considered complete" — on the chat path specifically. Found Aug 6.
///
/// Both paths now call one `fileApproval`. These tests drive the REAL flow (a chat run produces the
/// draft, then it is approved) rather than injecting a message, because `chatMessages` has a
/// private setter and adding a seam just for a test would be the wrong trade.
@MainActor
final class ApprovalParityTests: XCTestCase {

    private static let failingStreamer: (CompanyChatRequest) -> AsyncThrowingStream<CompanyChatStreamEvent, Error> = { _ in
        AsyncThrowingStream { $0.finish(throwing: CompanyChatStreamError.notSignedIn) }
    }

    private func store(tasks: [RoadmapTask],
                       taskSaves: @escaping () -> Void = {}) -> CompanyStore {
        CompanyStore(
            loader: { _ in
                CompanyState(brief: CompanyBrief(), departments: [], library: [], stage: .idea,
                             companionId: "byte", onboardedAt: Date(), tasks: tasks)
            },
            saver: { _, _ in true },
            tasksSaver: { _, _ in taskSaves(); return true },
            chatSender: { _ in CompanyChatReply(text: "On it", runTaskId: "t1") },
            chatStreamer: Self.failingStreamer,
            taskRunner: { _ in RunTaskResponse(kind: "doc", title: "Landing copy", body: "# hi") },
            librarySaver: { _, _ in true },
            firstApprovalSaver: { _, _ in true },
            decisionExtractor: { _, _ in [] })
    }

    private func runnable(_ id: String = "t1") -> RoadmapTask {
        RoadmapTask(id: id, title: "Write your landing page copy", detail: "", phase: .find,
                    who: .does, dept: "mkt")
    }

    /// Run a task through chat so a real draft card exists, and hand back its message id.
    private func produceDraft(_ s: CompanyStore) async throws -> String {
        await s.hydrate(companyId: "u")
        await s.sendChat("run it", language: .en)
        let id = try XCTUnwrap(s.chatMessages.last { $0.draft != nil }?.id, "no draft card landed")
        XCTAssertTrue(s.company.tasks[0].drafted, "the run should have left the task awaiting approval")
        return id
    }

    /// THE BUG. Approving in chat must complete the task, not just file the deliverable.
    func testApprovingFromChatCompletesTheTask() async throws {
        let s = store(tasks: [runnable()])
        let id = try await produceDraft(s)
        await s.approveDraft(messageId: id)

        XCTAssertTrue(s.company.tasks[0].done, "the chat Approve left the task unfinished")
        XCTAssertFalse(s.company.tasks[0].drafted, "the card would still read Review")
        XCTAssertNil(s.company.tasks[0].draft)
        XCTAssertEqual(s.company.library.count, 1)
        XCTAssertTrue(s.chatMessages.first { $0.id == id }?.draftApproved ?? false)
    }

    /// Both buttons, one outcome — asserted against each other rather than against a copy of the
    /// expected state, because the property that matters is that they AGREE.
    func testBothApprovePathsLeaveTheSameState() async throws {
        let a = store(tasks: [runnable()])
        let id = try await produceDraft(a)
        await a.approveDraft(messageId: id)

        let b = store(tasks: [runnable()])
        _ = try await produceDraft(b)
        await b.approveTask(id: "t1")

        XCTAssertEqual(a.company.tasks[0].done, b.company.tasks[0].done)
        XCTAssertEqual(a.company.tasks[0].drafted, b.company.tasks[0].drafted)
        XCTAssertEqual(a.company.tasks[0].draft, b.company.tasks[0].draft)
        XCTAssertEqual(a.company.library.count, b.company.library.count)
    }

    /// Filed exactly once. The guard is the message's `draftApproved`, and it has to hold.
    func testApprovingTwiceFromChatFilesOneCopy() async throws {
        let s = store(tasks: [runnable()])
        let id = try await produceDraft(s)
        await s.approveDraft(messageId: id)
        await s.approveDraft(messageId: id)
        XCTAssertEqual(s.company.library.count, 1)
    }

    /// The loop the bug broke: approving completes the task, which settles its phase, which makes
    /// the work behind it runnable. Without this, the founder approved in chat and stayed stuck.
    func testApprovingFromChatUnblocksTheWorkBehindIt() async throws {
        let blocked = RoadmapTask(id: "t2", title: "Set up a waitlist signup", detail: "",
                                  phase: .build, who: .does, dependsOn: ["t1"], dept: "eng")
        let s = store(tasks: [runnable(), blocked])
        let id = try await produceDraft(s)
        XCTAssertEqual(RoadmapEngine.status(for: s.company.tasks[1], in: s.company.tasks), .blocked)

        await s.approveDraft(messageId: id)
        XCTAssertEqual(RoadmapEngine.status(for: s.company.tasks[1], in: s.company.tasks),
                       .codepetCanDo, "approving in chat must unblock what it was holding up")
    }
}

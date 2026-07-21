// codepetTests/CompanyStoreChatRunTests.swift
import XCTest
@testable import codepet

@MainActor
final class CompanyStoreChatRunTests: XCTestCase {
    private func seeded() -> CompanyState {
        CompanyState(brief: CompanyBrief(), departments: [], library: [], stage: .idea,
                     companionId: "byte", onboardedAt: Date(),
                     tasks: [RoadmapTask(id: "t1", title: "Survey users", detail: "wtp", phase: .find, who: .does)])
    }
    private func store(reply: CompanyChatReply?,
                       runner: @escaping (RunTaskRequest) async -> RunTaskResponse?,
                       saver: @escaping (String, [Deliverable]) async -> Bool = { _, _ in true })
        -> CompanyStore {
        CompanyStore(loader: { _ in self.seeded() }, saver: { _, _ in true },
                     chatSender: { _ in reply }, taskRunner: runner, librarySaver: saver)
    }

    func testRunnableReplyProducesDraftNotInLibrary() async {
        let s = store(reply: CompanyChatReply(text: "On it", runTaskId: "t1"),
                      runner: { _ in RunTaskResponse(kind: "doc", title: "WTP", body: "# Q1") })
        await s.hydrate(companyId: "u")
        await s.sendChat("run the survey", language: .en)
        XCTAssertEqual(s.chatMessages.map(\.role), [.me, .companion, .companion])
        XCTAssertEqual(s.chatMessages[1].text, "On it")           // lead-in
        let draftMsg = s.chatMessages[2]
        XCTAssertEqual(draftMsg.draft?.sourceTaskId, "t1")
        XCTAssertFalse(draftMsg.draft?.id.isEmpty ?? true)
        XCTAssertTrue(draftMsg.draft?.createdAt?.hasSuffix("Z") ?? false)
        XCTAssertTrue(s.company.library.isEmpty)                  // draft NOT in library
        XCTAssertFalse(s.isCompanionTyping)
    }
    func testUnknownRunTaskIdNoDraft() async {
        let s = store(reply: CompanyChatReply(text: "hm", runTaskId: "nope"),
                      runner: { _ in RunTaskResponse(kind: "doc", title: "x", body: "# y") })
        await s.hydrate(companyId: "u")
        await s.sendChat("hi", language: .en)
        XCTAssertEqual(s.chatMessages.count, 2)                   // me + lead-in only
        XCTAssertNil(s.chatMessages.last?.draft)
    }
    func testChatRunFailureHonestBubble() async {
        let s = store(reply: CompanyChatReply(text: "On it", runTaskId: "t1"),
                      runner: { _ in nil })
        await s.hydrate(companyId: "u")
        await s.sendChat("run it", language: .en)
        XCTAssertEqual(s.chatMessages.count, 3)
        XCTAssertNil(s.chatMessages[2].draft)                     // failure bubble, no draft
        XCTAssertFalse(s.chatMessages[2].text.isEmpty)
    }
    func testApproveDraftMovesToLibraryAndPersists() async {
        var saved: [Deliverable] = []
        let s = store(reply: CompanyChatReply(text: "On it", runTaskId: "t1"),
                      runner: { _ in RunTaskResponse(kind: "doc", title: "WTP", body: "# Q1") },
                      saver: { _, lib in saved = lib; return true })
        await s.hydrate(companyId: "u")
        await s.sendChat("run", language: .en)
        let mid = s.chatMessages[2].id
        await s.approveDraft(messageId: mid)
        XCTAssertEqual(s.company.library.count, 1)
        XCTAssertEqual(saved.count, 1)
        XCTAssertTrue(s.chatMessages[2].draftApproved)
        // second approve is a no-op
        await s.approveDraft(messageId: mid)
        XCTAssertEqual(s.company.library.count, 1)
    }
    /// If an Approve races an in-flight Redo, Approve wins: the redo must not overwrite
    /// the just-approved draft (card body would mismatch the persisted library entry).
    func testRedoDiscardsWhenApprovedMidRun() async {
        var ref: CompanyStore?
        var mid = ""
        var n = 0
        let s = CompanyStore(loader: { _ in self.seeded() }, saver: { _, _ in true },
                             chatSender: { _ in CompanyChatReply(text: "On it", runTaskId: "t1") },
                             taskRunner: { _ in
                                 n += 1
                                 if n == 2 { await ref?.approveDraft(messageId: mid) }
                                 return RunTaskResponse(kind: "doc", title: "WTP", body: n == 1 ? "# first" : "# second")
                             },
                             librarySaver: { _, _ in true })
        ref = s
        await s.hydrate(companyId: "u")
        await s.sendChat("run", language: .en)          // n=1 → draft "# first"
        mid = s.chatMessages[2].id
        await s.redoDraft(messageId: mid, language: .en) // n=2 → approve mid-run → redo discards "# second"
        XCTAssertTrue(s.chatMessages[2].draftApproved)
        XCTAssertEqual(s.chatMessages[2].draft?.body, "# first")   // not overwritten
        XCTAssertEqual(s.company.library.first?.body, "# first")   // card matches library
    }
    func testRedoReplacesDraft() async {
        var body = "# first"
        let s = store(reply: CompanyChatReply(text: "On it", runTaskId: "t1"),
                      runner: { _ in RunTaskResponse(kind: "doc", title: "WTP", body: body) })
        await s.hydrate(companyId: "u")
        await s.sendChat("run", language: .en)
        let mid = s.chatMessages[2].id
        let firstId = s.chatMessages[2].draft?.id
        body = "# second"
        await s.redoDraft(messageId: mid, language: .en)
        XCTAssertEqual(s.chatMessages[2].draft?.body, "# second")
        XCTAssertNotEqual(s.chatMessages[2].draft?.id, firstId)   // fresh deliverable
    }
}

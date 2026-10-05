// codepetTests/DiscardChatDraftTests.swift
import XCTest
@testable import codepet

/// Discarding a draft from its chat card. The Tasks preview gained Discard in #220; the chat card
/// — where most drafts first appear — still offered only Approve, Redo and the revise chips.
/// Drives the real flow (a chat run produces the draft), like `ApprovalParityTests`, because
/// `chatMessages` has a private setter.
@MainActor
final class DiscardChatDraftTests: XCTestCase {
    private static let failingStreamer: (CompanyChatRequest) -> AsyncThrowingStream<CompanyChatStreamEvent, Error> = { _ in
        AsyncThrowingStream { $0.finish(throwing: CompanyChatStreamError.notSignedIn) }
    }

    private func store(librarySaves: @escaping () -> Void = {}) -> CompanyStore {
        CompanyStore(
            loader: { _ in
                CompanyState(brief: CompanyBrief(), departments: [], library: [], stage: .idea,
                             companionId: "byte", onboardedAt: Date(),
                             tasks: [RoadmapTask(id: "t1", title: "Write your landing page copy", detail: "",
                                                 phase: .find, who: .does, dept: "mkt")])
            },
            saver: { _, _ in true },
            tasksSaver: { _, _ in true },
            chatSender: { _ in CompanyChatReply(text: "On it", runTaskId: "t1") },
            chatStreamer: Self.failingStreamer,
            taskRunner: { _ in RunTaskResponse(kind: "doc", title: "Landing copy", body: "# hi") },
            librarySaver: { _, _ in librarySaves(); return true },
            firstApprovalSaver: { _, _ in true },
            decisionExtractor: { _, _ in [] })
    }

    private func produceDraft(_ s: CompanyStore) async throws -> String {
        await s.hydrate(companyId: "u")
        await s.sendChat("run it", language: .en)
        return try XCTUnwrap(s.chatMessages.last { $0.draft != nil }?.id, "no draft card landed")
    }

    func testDiscardFromChatReopensTheTaskAndFilesNothing() async throws {
        var librarySaves = 0
        let s = store(librarySaves: { librarySaves += 1 })
        let id = try await produceDraft(s)
        await s.discardDraft(messageId: id)
        let m = try XCTUnwrap(s.chatMessages.first { $0.id == id })
        XCTAssertTrue(m.draftDiscarded)
        XCTAssertFalse(m.draftApproved)
        XCTAssertFalse(s.company.tasks[0].drafted)        // the board's copy goes too
        XCTAssertNil(s.company.tasks[0].draft)
        XCTAssertFalse(s.company.tasks[0].done)
        XCTAssertTrue(s.company.library.isEmpty)
        XCTAssertEqual(librarySaves, 0)
    }

    /// A discarded card cannot then be approved — that would file what the founder threw away.
    func testADiscardedDraftCannotBeApproved() async throws {
        let s = store()
        let id = try await produceDraft(s)
        await s.discardDraft(messageId: id)
        await s.approveDraft(messageId: id)
        XCTAssertTrue(s.company.library.isEmpty)
        XCTAssertFalse(s.company.tasks[0].done)
    }

    func testAnApprovedDraftCannotBeDiscarded() async throws {
        let s = store()
        let id = try await produceDraft(s)
        await s.approveDraft(messageId: id)
        await s.discardDraft(messageId: id)
        XCTAssertFalse(try XCTUnwrap(s.chatMessages.first { $0.id == id }).draftDiscarded)
        XCTAssertEqual(s.company.library.count, 1)
    }

    /// Survives the thread archive, so a restored card does not offer Approve again.
    func testDiscardedSurvivesTheArchive() {
        var m = CopilotMessage(role: .companion, text: "",
                               draft: Deliverable(kind: .doc, title: "D", body: "b", sourceTaskId: "t1"))
        m.draftDiscarded = true
        XCTAssertEqual(StoredMessage(m)?.message.draftDiscarded, true)
    }
}

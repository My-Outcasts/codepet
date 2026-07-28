// codepetTests/CompanyStorePersistenceTests.swift
import XCTest
@testable import codepet

/// Chat persistence wiring in CompanyStore: hydrate loads the Recent list (opening
/// to the hero), a sent turn persists its thread, delete removes it — all via the
/// injected fail-soft seam (no Firestore).
@MainActor
final class CompanyStorePersistenceTests: XCTestCase {
    /// Spy for the thread persistence seam.
    private final class Spy {
        var saved: [ChatThread] = []
        var deleted: [String] = []
        var toLoad: [ChatThread] = []
    }

    private func seeded() -> CompanyState {
        CompanyState(brief: CompanyBrief(), departments: [], library: [], stage: .idea,
                     companionId: "byte", onboardedAt: Date(), tasks: [])
    }
    private static let plainStreamer: (CompanyChatRequest) -> AsyncThrowingStream<CompanyChatStreamEvent, Error> = { _ in
        AsyncThrowingStream { c in
            c.yield(.delta("reply")); c.yield(.done(model: "m", cacheHit: false, action: ChatDoneAction())); c.finish()
        }
    }
    private func store(_ spy: Spy) -> CompanyStore {
        CompanyStore(loader: { _ in self.seeded() }, saver: { _, _ in true },
                     chatSender: { _ in nil }, chatStreamer: Self.plainStreamer,
                     taskRunner: { _ in nil }, decisionExtractor: { _, _ in [] },
                     threadSaver: { _, t in spy.saved.append(t); return true },
                     threadDeleter: { _, id in spy.deleted.append(id); return true },
                     threadsLoader: { _ in spy.toLoad })
    }
    /// Let fire-and-forget @MainActor Tasks (flush/delete persistence) run.
    private func drain() async { for _ in 0..<10 { await Task.yield() } }

    /// Stale history (last touched well outside the resume window) hydrates the
    /// Recent list but still opens the hero — history lives in the switcher.
    func testHydrateLoadsRecentAndOpensHeroWhenHistoryIsStale() async {
        let spy = Spy()
        spy.toLoad = [
            ChatThread(id: "a", title: "First", messages: [], createdAt: Date(timeIntervalSince1970: 1), updatedAt: Date(timeIntervalSince1970: 2)),
            ChatThread(id: "b", title: "Second", messages: [], createdAt: Date(timeIntervalSince1970: 3), updatedAt: Date(timeIntervalSince1970: 4)),
        ]
        let s = store(spy)
        await s.hydrate(companyId: "u")
        XCTAssertEqual(s.threads.map(\.id), ["a", "b"])   // Recent list hydrated
        XCTAssertNil(s.activeThreadId)                     // opens to the hero
        XCTAssertTrue(s.chatMessages.isEmpty)
    }

    /// Launch inside the resume window reopens the newest thread with its
    /// messages already in the working buffer.
    func testHydrateResumesRecentThread() async {
        let spy = Spy()
        let now = Date()
        spy.toLoad = [
            ChatThread(id: "old", title: "Older", messages: [CopilotMessage(role: .me, text: "older ask")],
                       createdAt: now.addingTimeInterval(-7200), updatedAt: now.addingTimeInterval(-3600)),
            ChatThread(id: "recent", title: "Recent", messages: [CopilotMessage(role: .me, text: "where we left off")],
                       createdAt: now.addingTimeInterval(-1800), updatedAt: now.addingTimeInterval(-300)),
        ]
        let s = store(spy)
        await s.hydrate(companyId: "u")
        XCTAssertEqual(s.activeThreadId, "recent")
        XCTAssertEqual(s.chatMessages.map(\.text), ["where we left off"])
        XCTAssertEqual(s.threads.count, 2)               // full Recent list still hydrated
    }

    /// Resuming must not re-persist the thread it just opened (hydrate is a read).
    func testHydrateResumeDoesNotRewriteTheThread() async {
        let spy = Spy()
        let now = Date()
        spy.toLoad = [ChatThread(id: "recent", title: "Recent", messages: [CopilotMessage(role: .me, text: "hi")],
                                 createdAt: now.addingTimeInterval(-600), updatedAt: now.addingTimeInterval(-60))]
        let s = store(spy)
        await s.hydrate(companyId: "u")
        await drain()
        XCTAssertTrue(spy.saved.isEmpty)
    }

    /// Resuming, then sending, appends to the SAME thread rather than forking a
    /// second one — the resumed id stays the active buffer's identity.
    func testSendAfterResumeAppendsToSameThread() async {
        let spy = Spy()
        let now = Date()
        spy.toLoad = [ChatThread(id: "recent", title: "Recent", messages: [CopilotMessage(role: .me, text: "first")],
                                 createdAt: now.addingTimeInterval(-600), updatedAt: now.addingTimeInterval(-60))]
        let s = store(spy)
        await s.hydrate(companyId: "u")
        await s.sendChat("second", language: .en)
        await drain()
        XCTAssertEqual(s.activeThreadId, "recent")
        XCTAssertEqual(s.threads.count, 1)
        XCTAssertTrue(s.chatMessages.map(\.text).contains("first"))
        XCTAssertTrue(s.chatMessages.map(\.text).contains("second"))
        XCTAssertEqual(spy.saved.last?.id, "recent")
    }

    // MARK: - Resuming a thread that stopped mid enrichment interview

    /// A persisted thread whose last message is byte's unanswered `gap` question.
    private func interviewThread(gap: InterviewGap, answeredBefore: [InterviewGap] = []) -> ChatThread {
        let now = Date()
        var messages: [CopilotMessage] = answeredBefore.map {
            CopilotMessage(role: .companion, text: "asked \($0)", interview: $0, interviewAnswered: true)
        }
        messages.append(CopilotMessage(role: .companion, text: "what's your main goal?", interview: gap))
        return ChatThread(id: "mid-interview", title: nil, messages: messages,
                          createdAt: now.addingTimeInterval(-600), updatedAt: now.addingTimeInterval(-60))
    }

    /// The relaunch case: `interviewState` is session-only and gone, so answering
    /// the resumed question must still save AND ask the next gap — not go silent.
    func testAnsweringResumedInterviewQuestionAsksTheNextGap() async {
        let spy = Spy()
        spy.toLoad = [interviewThread(gap: .goal)]
        let s = store(spy)
        await s.hydrate(companyId: "u")
        guard let pending = s.pendingInterview else { return XCTFail("expected the resumed question to be pending") }
        XCTAssertEqual(pending.gap, .goal)

        await s.answerInterview(messageId: pending.id, gap: .goal, answer: "Ship v1", language: .en)
        XCTAssertEqual(s.company.brief.goal, "Ship v1")
        XCTAssertEqual(s.chatMessages.last?.interview, .traction)   // chain continued
    }

    /// Skipping (blank answer) after a relaunch must not re-ask the skipped gap —
    /// a skip saves nothing, so only the transcript remembers it happened.
    func testSkippingResumedInterviewQuestionDoesNotReAskIt() async {
        let spy = Spy()
        spy.toLoad = [interviewThread(gap: .goal)]
        let s = store(spy)
        await s.hydrate(companyId: "u")
        guard let pending = s.pendingInterview else { return XCTFail("expected a pending question") }

        await s.answerInterview(messageId: pending.id, gap: .goal, answer: "  ", language: .en)
        XCTAssertNil(s.company.brief.goal)                          // skip saves nothing
        XCTAssertEqual(s.chatMessages.last?.interview, .traction)   // moved on, not re-asked
        XCTAssertEqual(s.chatMessages.filter { $0.interview == .goal }.count, 1)
    }

    /// Answering the LAST outstanding gap after a relaunch hands off to the
    /// first-run greeting, exactly as a normally-completed interview does.
    func testAnsweringFinalResumedGapSeedsTheGreeting() async {
        let spy = Spy()
        spy.toLoad = [interviewThread(gap: .problem, answeredBefore: [.goal, .traction])]
        let filled = CompanyState(brief: CompanyBrief(goal: "Ship v1", traction: "None yet"),
                                  departments: [], library: [], stage: .idea,
                                  companionId: "byte", onboardedAt: Date(), tasks: [])
        let s = CompanyStore(loader: { _ in filled }, saver: { _, _ in true },
                            chatSender: { _ in nil }, chatStreamer: Self.plainStreamer,
                            taskRunner: { _ in nil }, decisionExtractor: { _, _ in [] },
                            threadSaver: { _, t in spy.saved.append(t); return true },
                            threadDeleter: { _, id in spy.deleted.append(id); return true },
                            threadsLoader: { _ in spy.toLoad })
        await s.hydrate(companyId: "u")
        guard let pending = s.pendingInterview else { return XCTFail("expected a pending question") }
        XCTAssertEqual(pending.gap, .problem)

        await s.answerInterview(messageId: pending.id, gap: .problem, answer: "Founders lose context", language: .en)
        guard let last = s.chatMessages.last else { return XCTFail("no messages") }
        XCTAssertEqual(last.role, .companion)
        XCTAssertNil(last.interview, "the interview is over — this should be the greeting")
        XCTAssertNil(s.pendingInterview)
    }

    func testSentTurnPersistsThread() async {
        let spy = Spy()
        let s = store(spy)
        await s.hydrate(companyId: "u")
        await s.sendChat("hi there", language: .en)
        await drain()
        XCTAssertFalse(spy.saved.isEmpty)                              // thread was persisted
        XCTAssertTrue(spy.saved.last?.messages.contains { $0.text == "hi there" } ?? false)
    }

    func testDeletePersistsRemoval() async {
        let spy = Spy()
        let s = store(spy)
        await s.hydrate(companyId: "u")
        await s.sendChat("hello", language: .en)
        await drain()
        guard let id = s.activeThreadId else { return XCTFail("no active thread") }
        s.deleteThread(id)
        await drain()
        XCTAssertTrue(spy.deleted.contains(id))
    }
}

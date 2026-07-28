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

    func testHydrateLoadsRecentAndOpensHero() async {
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

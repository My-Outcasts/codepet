// codepetTests/ThreadKindTests.swift
import XCTest
@testable import codepet

/// Guards on spec §10 — "one thread collection, one new field".
///
/// The bug these describe was visible in a screenshot and in nothing else: the
/// founder finished the walkthrough, landed back in Ask, and found the Developer
/// code run — the ask, the ENGINEERING card, the branch name — sitting in the Ask
/// conversation between two questions about the roadmap. One buffer stood behind
/// both doors, so "which conversation am I in" had no answer.
final class ThreadKindTests: XCTestCase {

    private func thread(_ id: String, _ kind: ChatThreadKind, minutesAgo: Int = 0) -> ChatThread {
        let t = Date(timeIntervalSince1970: 10_000 - Double(minutesAgo) * 60)
        return ChatThread(id: id, title: id, messages: [], createdAt: t, updatedAt: t, kind: kind)
    }

    /// Two filters over one collection, which is the whole design.
    func testTheTwoListsAreDisjointAndCoverEverything() {
        let all = [thread("a1", .ask), thread("d1", .dev), thread("a2", .ask)]
        let ask = threadsOfKind(.ask, in: all)
        let dev = threadsOfKind(.dev, in: all)
        XCTAssertEqual(ask.map(\.id), ["a1", "a2"])
        XCTAssertEqual(dev.map(\.id), ["d1"])
        XCTAssertEqual(ask.count + dev.count, all.count,
                       "a thread belongs to exactly one door, or it is unreachable from both")
    }

    /// **The leak, stated as a test.** Ask's Recent must never list a dev session.
    /// It did — the rail passed `companyStore.threads` unfiltered — so clicking one
    /// loaded a code run's transcript into Ask.
    func testAskRecentNeverListsADeveloperSession() {
        let all = [thread("chat", .ask), thread("fix the signup validation", .dev)]
        let recent = threadsOfKind(.ask, in: all)
        XCTAssertFalse(recent.contains { $0.kind == .dev })
        XCTAssertEqual(recent.count, 1)
    }

    /// A thread written by code that predates `kind` is an Ask conversation, not a
    /// silent member of both lists.
    func testTheDefaultIsAsk() {
        let t = ChatThread(id: "x", title: nil, messages: [],
                           createdAt: Date(), updatedAt: Date())
        XCTAssertEqual(t.kind, .ask)
    }

    /// Sorting is shared, so a filtered list still comes back newest-first — a
    /// sessions list in creation order would put the run you are watching at the
    /// bottom.
    func testEachListIsStillNewestFirst() {
        let all = [thread("old", .dev, minutesAgo: 30), thread("new", .dev, minutesAgo: 1)]
        XCTAssertEqual(sortThreadsByRecent(threadsOfKind(.dev, in: all)).map(\.id),
                       ["new", "old"])
    }
}

/// The same rule against the real store, because the leak was in the buffer and not
/// in the filter — a pure test of `threadsOfKind` would have stayed green through
/// every version of this bug.
@MainActor
final class WorkspaceSwitchTests: XCTestCase {

    /// **The screenshot, as an assertion.** Describe a change in Developer, go back
    /// to Ask, and the code run must not be in the Ask transcript.
    ///
    /// Driven only through the store's real entry points — `startCodeRun` is exactly
    /// what the Developer composer calls — so this fails for the same reason the
    /// screenshot happened rather than for a reason a test invented.
    func testACodeRunDescribedInDeveloperStaysOutOfAsk() {
        let store = CompanyStore()
        store.switchWorkspace(to: .dev)
        store.startCodeRun(ask: "Fix the signup validation — it rejects valid emails")
        XCTAssertEqual(store.chatMessages.count, 1, "the ask should be in the SESSION")

        store.switchWorkspace(to: .ask)
        XCTAssertTrue(store.chatMessages.isEmpty,
                      "the code run leaked into the Ask conversation — this is the bug: "
                      + "one buffer stood behind both doors")
    }

    /// Each door remembers where it was. Coming back must not dump you in a
    /// different session — a session owns a branch, so "which one am I in" is not a
    /// cosmetic question.
    func testEachDoorReturnsToTheConversationItLeft() {
        let store = CompanyStore()
        store.switchWorkspace(to: .dev)
        store.startCodeRun(ask: "first session")
        let first = store.activeThreadId

        store.newChat()
        store.startCodeRun(ask: "second session")
        XCTAssertNotEqual(store.activeThreadId, first)

        store.switchThread(first!)
        store.switchWorkspace(to: .ask)
        store.switchWorkspace(to: .dev)
        XCTAssertEqual(store.activeThreadId, first,
                       "came back to a different session than the one left")
        XCTAssertEqual(store.chatMessages.map(\.text), ["first session"])
    }

    /// Developer conversations are filed as sessions, so the rail's SESSIONS list
    /// can find them and Ask's RECENT cannot.
    func testDeveloperConversationsAreFiledAsSessions() {
        let store = CompanyStore()
        store.switchWorkspace(to: .dev)
        store.startCodeRun(ask: "a session")
        store.switchWorkspace(to: .ask)

        XCTAssertEqual(threadsOfKind(.dev, in: store.threads).compactMap(\.title), ["a session"])
        XCTAssertTrue(threadsOfKind(.ask, in: store.threads).isEmpty,
                      "a Developer session is showing up in Ask's Recent")
    }

    /// **A mode switch must not kill a live run.** `switchThread` cancels the coding
    /// run on purpose — an anchored run would float to the bottom of the incoming
    /// thread. Reusing that behaviour for a mode switch would mean glancing at Ask
    /// mid-run destroys the run, and a Developer session is supposed to own its
    /// branch and keep going.
    func testGlancingAtAskDoesNotDestroyARunningSession() {
        let store = CompanyStore()
        store.switchWorkspace(to: .dev)
        store.startCodeRun(ask: "Fix the signup validation")
        XCTAssertNotNil(store.codingRun.run)

        store.switchWorkspace(to: .ask)
        XCTAssertNotNil(store.codingRun.run, "the run was cancelled by looking at Ask")
        store.switchWorkspace(to: .dev)
        XCTAssertNotNil(store.codingRun.run)
    }
}

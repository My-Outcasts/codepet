// codepetTests/CompanyStoreChatTests.swift
import XCTest
@testable import codepet

@MainActor
final class CompanyStoreChatTests: XCTestCase {
    private func store(_ sender: @escaping (CompanyChatRequest) async -> String?) -> CompanyStore {
        CompanyStore(loader: { _ in .empty }, saver: { _, _ in true }, chatSender: sender)
    }

    func testSendAppendsUserThenCompanionReply() async {
        let s = store { _ in "Hello founder" }
        await s.hydrate(companyId: "u")
        await s.sendChat("hi", language: .en)
        XCTAssertEqual(s.chatMessages.map(\.role), [.me, .companion])
        XCTAssertEqual(s.chatMessages.last?.text, "Hello founder")
        XCTAssertFalse(s.isCompanionTyping)
    }
    func testFailOpenAppendsOfflineMessage() async {
        let s = store { _ in nil }
        await s.hydrate(companyId: "u")
        await s.sendChat("hi", language: .en)
        XCTAssertEqual(s.chatMessages.count, 2)
        XCTAssertEqual(s.chatMessages.last?.role, .companion)
        XCTAssertTrue(s.chatMessages.last?.text.contains("reach my brain") ?? false)
        XCTAssertFalse(s.isCompanionTyping)
    }
    func testEmptyInputIsNoOp() async {
        let s = store { _ in "x" }
        await s.hydrate(companyId: "u")
        await s.sendChat("   ", language: .en)
        XCTAssertTrue(s.chatMessages.isEmpty)
    }
    func testResetClearsChat() async {
        let s = store { _ in "x" }
        await s.hydrate(companyId: "u")
        await s.sendChat("hi", language: .en)
        s.reset()
        XCTAssertTrue(s.chatMessages.isEmpty)
        XCTAssertFalse(s.isCompanionTyping)
    }
    /// A reply arriving after sign-out/reset (companyId cleared) must not append.
    func testStaleReplyAfterResetDiscarded() async {
        var ref: CompanyStore?
        let s = CompanyStore(loader: { _ in .empty }, saver: { _, _ in true },
                             chatSender: { _ in await ref?.reset(); return "late reply" })
        ref = s
        await s.hydrate(companyId: "u")
        await s.sendChat("hi", language: .en)
        XCTAssertFalse(s.chatMessages.contains { $0.text == "late reply" })
        XCTAssertFalse(s.isCompanionTyping)   // reset cleared typing — never stuck
    }
    /// A same-user re-hydrate mid-reply (token refresh/reconnect) bumps the token but
    /// keeps companyId — the reply must still apply and typing must clear (not stick).
    func testReplyStillAppliesAfterSameUserRehydrate() async {
        var ref: CompanyStore?
        let s = CompanyStore(loader: { _ in .empty }, saver: { _, _ in true },
                             chatSender: { _ in await ref?.hydrate(companyId: "u"); return "reply" })
        ref = s
        await s.hydrate(companyId: "u")
        await s.sendChat("hi", language: .en)
        XCTAssertTrue(s.chatMessages.contains { $0.text == "reply" })
        XCTAssertFalse(s.isCompanionTyping)
    }
    /// An account switch via hydrate(differentId) mid-reply clears the outgoing chat +
    /// typing and discards the stale reply (no cross-account leak, no stuck typing).
    func testAccountSwitchViaHydrateClearsChatAndDiscardsReply() async {
        var ref: CompanyStore?
        let s = CompanyStore(loader: { _ in .empty }, saver: { _, _ in true },
                             chatSender: { _ in await ref?.hydrate(companyId: "B"); return "A reply" })
        ref = s
        await s.hydrate(companyId: "A")
        await s.sendChat("hi", language: .en)
        XCTAssertFalse(s.chatMessages.contains { $0.text == "A reply" })  // discarded
        XCTAssertTrue(s.chatMessages.isEmpty)                            // A's chat cleared on switch
        XCTAssertFalse(s.isCompanionTyping)                             // not stuck
    }
}

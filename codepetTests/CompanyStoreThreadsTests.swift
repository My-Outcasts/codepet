// codepetTests/CompanyStoreThreadsTests.swift
import XCTest
@testable import codepet

/// `CompanyStore`'s thread CRUD (`newChat`/`switchThread`/`renameThread`/
/// `deleteThread`) atop the `chatMessages`-is-the-active-thread's-working-buffer
/// model. Uses the same synthetic-DI pattern as `CompanyStoreChatTests` — no
/// network, no `Auth.auth()` dependency.
@MainActor
final class CompanyStoreThreadsTests: XCTestCase {
    private static let failingStreamer: (CompanyChatRequest) -> AsyncThrowingStream<CompanyChatStreamEvent, Error> = { _ in
        AsyncThrowingStream { $0.finish(throwing: CompanyChatStreamError.notSignedIn) }
    }

    private func store() -> CompanyStore {
        CompanyStore(loader: { _ in .empty }, saver: { _, _ in true },
                     chatSender: { _ in nil }, chatStreamer: Self.failingStreamer)
    }

    /// new → switch → delete-active falls back to the most-recently-updated
    /// remaining thread; deleting the last thread opens a fresh new chat.
    func testNewSwitchAndDeleteActiveFallsBack() async {
        let s = store()
        await s.hydrate(companyId: "u")

        await s.sendChat("first thread hello", language: .en)
        guard let firstId = s.activeThreadId else { return XCTFail("expected an active thread after first send") }
        XCTAssertEqual(s.threads.count, 1)
        XCTAssertEqual(s.threads.first?.title, "first thread hello")

        s.newChat()
        XCTAssertTrue(s.chatMessages.isEmpty)
        XCTAssertNotEqual(s.activeThreadId, firstId)   // fresh id minted immediately

        await s.sendChat("second thread hello", language: .en)
        guard let secondId = s.activeThreadId else { return XCTFail("expected an active thread after second send") }
        XCTAssertNotEqual(firstId, secondId)
        XCTAssertEqual(s.threads.count, 2)

        s.switchThread(firstId)
        XCTAssertEqual(s.activeThreadId, firstId)
        XCTAssertEqual(s.chatMessages.first?.text, "first thread hello")

        s.switchThread(secondId)
        XCTAssertEqual(s.activeThreadId, secondId)

        s.deleteThread(secondId)
        XCTAssertEqual(s.threads.count, 1)
        XCTAssertEqual(s.activeThreadId, firstId)       // fell back to the remaining thread
        XCTAssertEqual(s.chatMessages.first?.text, "first thread hello")

        s.deleteThread(firstId)
        XCTAssertTrue(s.threads.isEmpty)
        XCTAssertTrue(s.chatMessages.isEmpty)
        XCTAssertNotNil(s.activeThreadId)               // newChat() minted a fresh id
        XCTAssertNotEqual(s.activeThreadId, firstId)
    }

    /// Renaming sets a title; a blank rename clears back to nil (re-derivable).
    func testRenameThreadSetsTitleBlankClearsToNil() async {
        let s = store()
        await s.hydrate(companyId: "u")
        await s.sendChat("hello", language: .en)
        guard let id = s.activeThreadId else { return XCTFail("expected an active thread") }

        s.renameThread(id, title: "My renamed chat")
        XCTAssertEqual(s.threads.first?.title, "My renamed chat")

        s.renameThread(id, title: "   ")
        XCTAssertNil(s.threads.first?.title)
    }

    /// Deleting a thread that ISN'T active just removes it — the active buffer
    /// is untouched.
    func testDeletingNonActiveThreadLeavesActiveBufferUntouched() async {
        let s = store()
        await s.hydrate(companyId: "u")
        await s.sendChat("first", language: .en)
        guard let firstId = s.activeThreadId else { return XCTFail("expected an active thread") }
        s.newChat()
        await s.sendChat("second", language: .en)
        guard let secondId = s.activeThreadId else { return XCTFail("expected a second active thread") }

        s.deleteThread(firstId)
        XCTAssertEqual(s.threads.count, 1)
        XCTAssertEqual(s.activeThreadId, secondId)
        XCTAssertEqual(s.chatMessages.first?.text, "second")
    }

    /// An account switch (real hydrate to a different companyId) clears threads
    /// + activeThreadId alongside the existing chatMessages clear.
    func testAccountSwitchClearsThreadsAndActiveId() async {
        let s = store()
        await s.hydrate(companyId: "A")
        await s.sendChat("hello", language: .en)
        XCTAssertFalse(s.threads.isEmpty)
        XCTAssertNotNil(s.activeThreadId)

        await s.hydrate(companyId: "B")
        XCTAssertTrue(s.threads.isEmpty)
        XCTAssertNil(s.activeThreadId)
        XCTAssertTrue(s.chatMessages.isEmpty)
    }

    /// `reset()` (sign-out) clears threads + activeThreadId too.
    func testResetClearsThreadsAndActiveId() async {
        let s = store()
        await s.hydrate(companyId: "u")
        await s.sendChat("hello", language: .en)
        XCTAssertFalse(s.threads.isEmpty)

        s.reset()
        XCTAssertTrue(s.threads.isEmpty)
        XCTAssertNil(s.activeThreadId)
    }
}

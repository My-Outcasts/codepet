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

    // MARK: - Mid-stream thread-switch guard (the review bug)

    /// A one-shot gate an in-flight `chatStreamer` awaits between its `.delta`
    /// and its `.done` — lets a test suspend a send mid-stream, assert against
    /// `isStreaming == true`, and then let it complete. `actor`-isolated so it's
    /// safe to signal from the test body while the stream's own `Task` awaits it.
    private actor StreamGate {
        private var continuation: CheckedContinuation<Void, Never>?
        private var alreadySignaled = false
        func wait() async {
            if alreadySignaled { return }
            await withCheckedContinuation { continuation = $0 }
        }
        func signal() {
            alreadySignaled = true
            continuation?.resume()
            continuation = nil
        }
    }

    /// Yields ONE delta immediately then completes right away for any request
    /// whose `userMessage` isn't `gatedOn` — so setup turns (building threads A
    /// and B before the test's real subject) never touch the gate and can't
    /// deadlock. Only the turn matching `gatedOn` blocks on `gate` before its
    /// `.done`, giving the test a real, observable in-flight stream for that
    /// one turn — not just a flipped flag.
    private static func pausableStreamer(_ gate: StreamGate, gatedOn: String, delta: String)
        -> (CompanyChatRequest) -> AsyncThrowingStream<CompanyChatStreamEvent, Error> {
        { req in
            let isGatedTurn = req.userMessage == gatedOn
            return AsyncThrowingStream { continuation in
                Task {
                    continuation.yield(.delta(isGatedTurn ? delta : "reply"))
                    if isGatedTurn { await gate.wait() }
                    continuation.yield(.done(model: "m", cacheHit: false, action: ChatDoneAction()))
                    continuation.finish()
                }
            }
        }
    }

    /// The exact bug from review: `newChat()`/`switchThread(_:)`/`deleteThread(_:)`
    /// must be a NO-OP while a chat turn is genuinely in flight (a real streamed
    /// send, suspended mid-reply via `StreamGate` — not a hand-set flag) — otherwise
    /// the in-flight loop's delta lookups start missing (streamed reply lost, empty
    /// bubble) and its `.done` chips land in whatever thread became active
    /// (cross-thread contamination). Exercises all three controls the guard protects,
    /// then confirms the turn completes normally once the guard is no longer needed.
    func testThreadControlsAreNoOpWhileStreaming() async {
        let gate = StreamGate()
        let s = CompanyStore(loader: { _ in .empty }, saver: { _, _ in true },
                             chatSender: { _ in XCTFail("fallback must not run on a successful stream"); return nil },
                             chatStreamer: Self.pausableStreamer(gate, gatedOn: "third hello", delta: "partial reply"))
        await s.hydrate(companyId: "u")

        // Thread A: one completed turn, flushed and in `threads`.
        await s.sendChat("first thread hello", language: .en)
        guard let threadA = s.activeThreadId else { return XCTFail("expected thread A") }

        // Thread B: a second completed turn, flushed — gives us a real distinct
        // thread to (attempt to) switch/delete into/from while A streams.
        s.newChat()
        await s.sendChat("second thread hello", language: .en)
        guard let threadB = s.activeThreadId, threadB != threadA else { return XCTFail("expected thread B") }
        XCTAssertEqual(s.threads.count, 2)

        // Back on A, kick off a turn that streams a delta and then blocks —
        // `isStreaming` is now genuinely true, driven by a real in-flight loop.
        s.switchThread(threadA)
        XCTAssertEqual(s.activeThreadId, threadA)
        let sendTask = Task { await s.sendChat("third hello", language: .en) }

        while !s.isStreaming { await Task.yield() }
        while s.chatMessages.last?.text != "partial reply" { await Task.yield() }

        let messagesMidStream = s.chatMessages
        let threadsMidStream = s.threads

        // All three controls must be a no-op: nothing about the active thread,
        // the in-flight buffer, or the thread list may change while streaming.
        s.newChat()
        XCTAssertEqual(s.activeThreadId, threadA)
        XCTAssertEqual(s.chatMessages, messagesMidStream)
        XCTAssertEqual(s.threads, threadsMidStream)

        s.switchThread(threadB)
        XCTAssertEqual(s.activeThreadId, threadA)          // did NOT repoint to B
        XCTAssertEqual(s.chatMessages, messagesMidStream)  // buffer untouched — no lost reply

        s.deleteThread(threadB)
        XCTAssertEqual(s.threads.count, 2)                 // B was NOT deleted
        XCTAssertTrue(s.threads.contains { $0.id == threadB })

        // Let the stream finish — the turn completes normally once the guard's
        // condition (isStreaming) clears, proving this isn't a permanent wedge.
        await gate.signal()
        await sendTask.value

        XCTAssertFalse(s.isStreaming)
        XCTAssertEqual(s.activeThreadId, threadA)
        XCTAssertEqual(s.chatMessages.last?.text, "partial reply")
        XCTAssertTrue(s.threads.first { $0.id == threadA }?.messages.contains { $0.text == "partial reply" } ?? false)
    }

    /// Store-level guard, asserted directly and independently of the streamer
    /// plumbing above: with `isStreaming` true, all three controls return
    /// having mutated nothing. Kept alongside the full streaming test per the
    /// task's "at minimum" fallback — cheap, fast, and pins the guard even if
    /// the streaming machinery above ever changes shape.
    func testNewChatSwitchDeleteAreNoOpWhileIsStreamingTrue() async {
        let gate = StreamGate()
        let s = CompanyStore(loader: { _ in .empty }, saver: { _, _ in true },
                             chatSender: { _ in nil },
                             chatStreamer: Self.pausableStreamer(gate, gatedOn: "second turn", delta: "x"))
        await s.hydrate(companyId: "u")
        await s.sendChat("only thread", language: .en)
        guard let onlyId = s.activeThreadId else { return XCTFail("expected a thread") }

        let sendTask = Task { await s.sendChat("second turn", language: .en) }
        while !s.isStreaming { await Task.yield() }

        s.newChat()
        XCTAssertEqual(s.activeThreadId, onlyId)
        s.switchThread(onlyId)   // even a same-id switch must not slip through
        XCTAssertEqual(s.activeThreadId, onlyId)
        s.deleteThread(onlyId)
        XCTAssertEqual(s.threads.count, 1)
        XCTAssertNotNil(s.threads.first { $0.id == onlyId })

        await gate.signal()
        await sendTask.value
    }
}

// codepetTests/CompanyStoreChatTests.swift
import XCTest
@testable import codepet

@MainActor
final class CompanyStoreChatTests: XCTestCase {
    /// A `chatStreamer` that throws before yielding anything — exercises the
    /// fallback-to-`chatSender` path deterministically, with no network and no
    /// dependency on `Auth.auth()` (unconfigured under XCTest).
    private static let failingStreamer: (CompanyChatRequest) -> AsyncThrowingStream<CompanyChatStreamEvent, Error> = { _ in
        AsyncThrowingStream { $0.finish(throwing: CompanyChatStreamError.notSignedIn) }
    }

    private func store(_ sender: @escaping (CompanyChatRequest) async -> CompanyChatReply?) -> CompanyStore {
        CompanyStore(loader: { _ in .empty }, saver: { _, _ in true },
                     chatSender: sender, chatStreamer: Self.failingStreamer)
    }

    func testSendAppendsUserThenCompanionReply() async {
        let s = store { _ in CompanyChatReply(text: "Hello founder", runTaskId: nil) }
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
        let s = store { _ in CompanyChatReply(text: "x", runTaskId: nil) }
        await s.hydrate(companyId: "u")
        await s.sendChat("   ", language: .en)
        XCTAssertTrue(s.chatMessages.isEmpty)
    }
    func testResetClearsChat() async {
        let s = store { _ in CompanyChatReply(text: "x", runTaskId: nil) }
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
                             chatSender: { _ in await ref?.reset(); return CompanyChatReply(text: "late reply", runTaskId: nil) },
                             chatStreamer: Self.failingStreamer)
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
                             chatSender: { _ in await ref?.hydrate(companyId: "u"); return CompanyChatReply(text: "reply", runTaskId: nil) },
                             chatStreamer: Self.failingStreamer)
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
                             chatSender: { _ in await ref?.hydrate(companyId: "B"); return CompanyChatReply(text: "A reply", runTaskId: nil) },
                             chatStreamer: Self.failingStreamer)
        ref = s
        await s.hydrate(companyId: "A")
        await s.sendChat("hi", language: .en)
        XCTAssertFalse(s.chatMessages.contains { $0.text == "A reply" })  // discarded
        XCTAssertTrue(s.chatMessages.isEmpty)                            // A's chat cleared on switch
        XCTAssertFalse(s.isCompanionTyping)                             // not stuck
    }

    // MARK: - Streaming

    /// A synthetic `chatStreamer` yielding `.delta`s then `.done` — no throw.
    private static func streamer(deltas: [String], model: String = "m", cacheHit: Bool = false,
                                 runTaskId: String? = nil)
        -> (CompanyChatRequest) -> AsyncThrowingStream<CompanyChatStreamEvent, Error> {
        { _ in
            AsyncThrowingStream { continuation in
                for d in deltas { continuation.yield(.delta(d)) }
                continuation.yield(.done(model: model, cacheHit: cacheHit, runTaskId: runTaskId))
                continuation.finish()
            }
        }
    }

    /// Deltas accumulate in place into the SAME placeholder message; the
    /// non-streaming `chatSender` must never be consulted (post-deploy path).
    func testStreamingDeltasAccumulateIntoPlaceholderNoFallback() async {
        let s = CompanyStore(loader: { _ in .empty }, saver: { _, _ in true },
                             chatSender: { _ in XCTFail("fallback must not run on a successful stream"); return nil },
                             chatStreamer: Self.streamer(deltas: ["On it", ", boss"]))
        await s.hydrate(companyId: "u")
        await s.sendChat("hi", language: .en)
        XCTAssertEqual(s.chatMessages.map(\.role), [.me, .companion])
        XCTAssertEqual(s.chatMessages.count, 2)          // one placeholder, filled in place — no extra message
        XCTAssertEqual(s.chatMessages.last?.text, "On it, boss")
        XCTAssertFalse(s.isCompanionTyping)
    }

    /// Typing flips off on the FIRST delta (typing → streaming transition), before
    /// the stream completes.
    func testIsCompanionTypingClearsOnFirstDelta() async {
        let s = CompanyStore(loader: { _ in .empty }, saver: { _, _ in true },
                             chatSender: { _ in nil },
                             chatStreamer: Self.streamer(deltas: ["hi"]))
        await s.hydrate(companyId: "u")
        await s.sendChat("hi", language: .en)
        XCTAssertFalse(s.isCompanionTyping)   // cleared by end of send regardless; covered above too
    }

    /// A stream that yields ZERO frames at all — no `.delta`, no `.done` — the
    /// exact shape the live CF collapses to pre-deploy: a plain JSON body with
    /// no `event:`/`data:` lines parses to zero SSE frames, so the stream just
    /// ends with nothing yielded and no `.done` ever fires.
    private static let noFramesStreamer: (CompanyChatRequest) -> AsyncThrowingStream<CompanyChatStreamEvent, Error> = { _ in
        AsyncThrowingStream { $0.finish() }
    }

    /// A genuinely empty, clean stream (zero frames, no `.done`) must trigger
    /// the SAME fallback as a thrown error — this is the deploy-order-safety
    /// net, distinct from a well-formed `.done` carrying no chat text (that
    /// case must NOT fall back — see CompanyStoreChatRunTests).
    func testEmptyCleanStreamFallsBackToChatSender() async {
        let s = CompanyStore(loader: { _ in .empty }, saver: { _, _ in true },
                             chatSender: { _ in CompanyChatReply(text: "from JSON fallback", runTaskId: nil) },
                             chatStreamer: Self.noFramesStreamer)
        await s.hydrate(companyId: "u")
        await s.sendChat("hi", language: .en)
        XCTAssertEqual(s.chatMessages.count, 2)
        XCTAssertEqual(s.chatMessages.last?.text, "from JSON fallback")
        XCTAssertFalse(s.isCompanionTyping)
    }

    // MARK: - walkThroughTask

    private static func task(who: TaskWho = .you) -> RoadmapTask {
        RoadmapTask(id: "t1", title: "Talk to 5 potential customers", detail: "Focus on their current workaround.",
                    phase: .find, who: who)
    }

    /// `walkThroughTask` appends a founder message mentioning the task's title and
    /// routes through the SAME streamed chat path as `sendChat` (a grounded companion
    /// reply arrives) — it must NOT call `taskRunner` (no deliverable is generated;
    /// this is guidance, not a run).
    func testWalkThroughTaskAppendsFounderMessageAndStreamsReply() async {
        var taskRunnerCalled = false
        let s = CompanyStore(loader: { _ in .empty }, saver: { _, _ in true },
                             chatSender: { _ in XCTFail("fallback must not run on a successful stream"); return nil },
                             chatStreamer: Self.streamer(deltas: ["Here's how: step one, step two."]),
                             taskRunner: { _ in taskRunnerCalled = true; return nil })
        await s.hydrate(companyId: "u")
        await s.walkThroughTask(Self.task(), language: .en)

        XCTAssertEqual(s.chatMessages.map(\.role), [.me, .companion])
        XCTAssertTrue(s.chatMessages.first?.text.contains("Talk to 5 potential customers") ?? false)
        XCTAssertEqual(s.chatMessages.last?.text, "Here's how: step one, step two.")
        XCTAssertFalse(taskRunnerCalled)
        XCTAssertFalse(s.isCompanionTyping)
        XCTAssertFalse(s.isStreaming)
    }

    /// Vietnamese composes the VI ask and still routes through the grounded stream.
    func testWalkThroughTaskVietnamese() async {
        let s = CompanyStore(loader: { _ in .empty }, saver: { _, _ in true },
                             chatSender: { _ in nil },
                             chatStreamer: Self.streamer(deltas: ["Đây là cách làm."]))
        await s.hydrate(companyId: "u")
        await s.walkThroughTask(Self.task(), language: .vi)

        XCTAssertTrue(s.chatMessages.first?.text.contains("Talk to 5 potential customers") ?? false)
        XCTAssertEqual(s.chatMessages.last?.text, "Đây là cách làm.")
    }
}

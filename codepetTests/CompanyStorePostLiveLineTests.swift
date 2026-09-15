// codepetTests/CompanyStorePostLiveLineTests.swift
import XCTest
@testable import codepet

/// `postLiveLine` used to call `CompanyChatClient.send` directly, skipping
/// `ChatTransportRouter` entirely — and with it the injectable `chatSender` seam every
/// other chat path in `CompanyStore` goes through (see `sendChat`'s non-streaming retry).
/// A founder who granted her Claude plan never reached the local path here: the direct
/// call went to the (now-401, keyless) Cloud Function, `reply` came back nil, and the
/// authored fallback posted every time — the demo's "live line" was dead for exactly the
/// founders it was built for.
///
/// These pin `postLiveLine` to the same `chatSender` seam as everything else in this file
/// (defaults to `ChatTransportRouter.send`), rather than reaching `CompanyChatClient.send`
/// on its own. Following the pattern in `CompanyStoreWalkThroughTests`/`CompanyStoreChatTests`:
/// a distinguishing reply is only visible in the transcript if the call actually went
/// through the injected closure.
@MainActor
final class CompanyStorePostLiveLineTests: XCTestCase {
    private static let failingStreamer: (CompanyChatRequest) -> AsyncThrowingStream<CompanyChatStreamEvent, Error> = { _ in
        AsyncThrowingStream { $0.finish(throwing: CompanyChatStreamError.notSignedIn) }
    }

    private func store(chatSender: @escaping (CompanyChatRequest) async -> CompanyChatReply?) -> CompanyStore {
        CompanyStore(loader: { _ in
                        CompanyState(brief: CompanyBrief(), departments: [], library: [], stage: .idea,
                                     companionId: "byte", onboardedAt: Date(), tasks: [])
                     },
                     saver: { _, _ in true },
                     chatSender: chatSender,
                     chatStreamer: Self.failingStreamer)
    }

    /// A granted founder: the injected `chatSender` stands in for a routed local reply.
    /// If `postLiveLine` still called `CompanyChatClient.send` directly, this closure would
    /// never run, `wasLive` would be false, and the authored fallback would post instead —
    /// which is exactly the bug this test is written to fail on before the fix.
    func testPostLiveLineRoutesThroughChatSenderNotDirectlyToTheClient() async {
        var called = false
        let s = store(chatSender: { _ in
            called = true
            return CompanyChatReply(text: "the real live line", runTaskId: nil)
        })
        await s.hydrate(companyId: "u")

        let wasLive = await s.postLiveLine(instruction: "say something", fallback: "authored fallback",
                                           language: .en, companionId: "byte", deptName: "Engineering",
                                           deptKey: "eng")

        XCTAssertTrue(called, "postLiveLine must obtain its reply through the injected " +
                      "chatSender seam (ChatTransportRouter by default), not call " +
                      "CompanyChatClient.send directly")
        XCTAssertTrue(wasLive)
        XCTAssertEqual(s.chatMessages.last?.text, "the real live line")
        XCTAssertEqual(s.chatMessages.last?.scriptedFallback, false)
    }

    /// The soft-fallback half, unchanged by the fix: when the transport comes back with
    /// nothing (the router's `.blocked` path, or any other nil), the authored `fallback`
    /// still posts, stamped `scriptedFallback: true` — the softness this function
    /// deliberately keeps, so a demo never shows an empty bubble.
    func testPostLiveLineFallsBackToTheAuthoredLineWhenChatSenderReturnsNil() async {
        let s = store(chatSender: { _ in nil })
        await s.hydrate(companyId: "u")

        let wasLive = await s.postLiveLine(instruction: "say something", fallback: "authored fallback",
                                           language: .en, companionId: "byte", deptName: "Engineering",
                                           deptKey: "eng")

        XCTAssertFalse(wasLive)
        XCTAssertEqual(s.chatMessages.last?.text, "authored fallback")
        XCTAssertEqual(s.chatMessages.last?.scriptedFallback, true)
    }
}

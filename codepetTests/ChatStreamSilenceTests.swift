// codepetTests/ChatStreamSilenceTests.swift
import XCTest
@testable import codepet

/// A reply whose text has stopped but whose turn has not ended must show the thinking row again.
/// On the local transport `claude -p` can sit silent for 15 s after its last word, and with the
/// row cleared by the first delta the founder watched a finished-looking answer, then a card
/// appeared from nowhere.
@MainActor
final class ChatStreamSilenceTests: XCTestCase {
    private var savedSilence: UInt64 = 0
    override func setUp() { super.setUp(); savedSilence = CompanyStore.streamSilenceNanos }
    override func tearDown() { CompanyStore.streamSilenceNanos = savedSilence; super.tearDown() }

    func testThinkingRowReturnsWhenTheStreamGoesQuietAndClearsAtTheEnd() async {
        CompanyStore.streamSilenceNanos = 20_000_000   // 20 ms
        let gate = AsyncStream<Void>.makeStream()
        let s = CompanyStore(
            loader: { _ in .empty }, saver: { _, _ in true },
            chatSender: { _ in nil },
            chatStreamer: { _ in
                AsyncThrowingStream { cont in
                    Task {
                        cont.yield(.delta("On it."))
                        for await _ in gate.stream { break }   // silent until the test releases it
                        cont.yield(.done(model: "m", cacheHit: false, action: ChatDoneAction()))
                        cont.finish()
                    }
                }
            })
        await s.hydrate(companyId: "u")
        let send = Task { await s.sendChat("hi", language: .en) }

        var returned = false
        for _ in 0..<200 where !returned {        // ≤ 2 s
            try? await Task.sleep(nanoseconds: 10_000_000)
            returned = s.chatMessages.last?.text == "On it." && s.isCompanionTyping
        }
        XCTAssertTrue(returned, "the row comes back while the turn is still open")

        gate.continuation.yield()
        await send.value
        XCTAssertFalse(s.isCompanionTyping)
        XCTAssertFalse(s.isStreaming)
    }
}

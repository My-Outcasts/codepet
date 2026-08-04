// codepetTests/CompanyStoreVirtualCompanyTests.swift
import XCTest
@testable import codepet

/// Drives the Virtual Company fan-out through the injected `vcRunner`, so the
/// handoff, the escape hatch, a failed run and a late-deciding run are exercised
/// against the real `CompanyStore.sendMessage` with no network.
@MainActor
final class CompanyStoreVirtualCompanyTests: XCTestCase {

    /// Throws before yielding, so the turn resolves through the `chatSender`
    /// fallback — deterministic, and independent of `Auth.auth()`.
    private static let failingStreamer: (CompanyChatRequest) -> AsyncThrowingStream<CompanyChatStreamEvent, Error> = { _ in
        AsyncThrowingStream { $0.finish(throwing: CompanyChatStreamError.notSignedIn) }
    }

    private static func routing(_ decision: String) -> VCRouting {
        let json: [String: Any] = ["decision": decision, "agents": ["product", "finance"],
                                   "real_question": "q", "request_type": "DECISION"]
        return try! JSONDecoder().decode(
            VCRouting.self, from: try! JSONSerialization.data(withJSONObject: json))
    }

    private func store(
        vcRunner: @escaping (VirtualCompanyRequest) -> AsyncThrowingStream<VirtualCompanyEvent, Error>
    ) -> CompanyStore {
        CompanyStore(loader: { _ in .empty }, saver: { _, _ in true },
                     chatSender: { _ in
                         // A real reply takes real time, and that suspension is what
                         // lets the concurrent fan-out reach the main actor at all. An
                         // instantly-returning stub never yields, so the run would not
                         // get a slot before the turn closes and the test would be
                         // measuring the stub, not the store.
                         try? await Task.sleep(nanoseconds: 30_000_000)
                         return CompanyChatReply(text: "byte's answer", runTaskId: nil)
                     },
                     chatStreamer: Self.failingStreamer,
                     vcRunner: vcRunner)
    }

    private func send(_ s: CompanyStore) async {
        await s.hydrate(companyId: "u")
        await s.sendChat("free with ads or $9.99 once?", language: .en)
    }

    // MARK: - The room takes the turn

    func testHandoffReplacesTheAnswerAndAttachesTheRun() async {
        let s = store { _ in
            AsyncThrowingStream {
                $0.yield(.runStarted(runId: "r1"))
                $0.yield(.routing(Self.routing("multi_agent")))
                $0.yield(.done(runId: "r1", unresolved: false, skipped: nil))
                $0.finish()
            }
        }
        await send(s)
        XCTAssertEqual(s.chatMessages.last?.text,
                       "This one needs the whole room — let me bring in product and finance.")
        XCTAssertEqual(s.chatMessages.last?.vcRun?.phase, .finished)
        XCTAssertFalse(s.isStreaming)
        XCTAssertFalse(s.isCompanionTyping)
    }

    /// Important 1: a run that dies with the room already on screen must say so.
    /// Otherwise the agent columns spin forever with no error and nothing to retry.
    func testAThrowAfterTheHandoffSealsTheRunAsFailed() async {
        let s = store { _ in
            AsyncThrowingStream {
                $0.yield(.routing(Self.routing("multi_agent")))
                $0.finish(throwing: VirtualCompanyRunError.malformedResponse)
            }
        }
        await send(s)
        XCTAssertEqual(s.chatMessages.last?.vcRun?.terminalError, "stream_lost")
        XCTAssertEqual(s.chatMessages.last?.vcRun?.phase, .failed)
        XCTAssertFalse(s.isStreaming)
    }

    func testAStreamEndingWithoutDoneAfterTheHandoffAlsoSeals() async {
        let s = store { _ in
            AsyncThrowingStream {
                $0.yield(.routing(Self.routing("multi_agent")))
                $0.finish()          // clean end, no `done` frame
            }
        }
        await send(s)
        XCTAssertEqual(s.chatMessages.last?.vcRun?.terminalError, "stream_lost")
        XCTAssertEqual(s.chatMessages.last?.vcRun?.phase, .failed)
    }

    /// A terminal `error` frame keeps its own code — the seal must not overwrite it.
    func testATerminalErrorFrameKeepsItsOwnCode() async {
        let s = store { _ in
            AsyncThrowingStream {
                $0.yield(.routing(Self.routing("multi_agent")))
                $0.yield(.error("upstream_failure", "anthropic 529"))
                $0.finish()
            }
        }
        await send(s)
        XCTAssertEqual(s.chatMessages.last?.vcRun?.terminalError, "upstream_failure")
    }

    // MARK: - The chat must be untouched otherwise

    func testEscapeHatchLeavesTheChatExactlyAsItWas() async {
        let s = store { _ in
            AsyncThrowingStream {
                $0.yield(.runStarted(runId: "r1"))
                $0.yield(.routing(Self.routing("single_agent")))
                $0.finish()
            }
        }
        await send(s)
        XCTAssertEqual(s.chatMessages.map(\.role), [.me, .companion])
        XCTAssertEqual(s.chatMessages.last?.text, "byte's answer")
        XCTAssertNil(s.chatMessages.last?.vcRun)
    }

    func testAKillSwitchOrCapLeavesTheChatExactlyAsItWas() async {
        let s = store { _ in
            AsyncThrowingStream {
                $0.finish(throwing: VirtualCompanyRunError.http(status: 503, body: nil))
            }
        }
        await send(s)
        XCTAssertEqual(s.chatMessages.last?.text, "byte's answer")
        XCTAssertNil(s.chatMessages.last?.vcRun)
        XCTAssertFalse(s.isStreaming)
    }

    func testAnErrorFrameBeforeRoutingNeverTouchesTheChat() async {
        let s = store { _ in
            AsyncThrowingStream {
                $0.yield(.error("upstream_failure", nil))
                $0.finish()
            }
        }
        await send(s)
        XCTAssertEqual(s.chatMessages.last?.text, "byte's answer")
        XCTAssertNil(s.chatMessages.last?.vcRun)
    }

    /// Important 2: `virtualCompanyRun` cold-starts in 5–10s while byte's stream can
    /// finish in 4, so a routing frame can arrive after the founder has read the
    /// answer. It must not reopen a closed turn.
    func testARunDecidingAfterTheTurnClosedCannotRewriteTheAnswer() async {
        final class Box { var cont: AsyncThrowingStream<VirtualCompanyEvent, Error>.Continuation? }
        let box = Box()
        let s = store { _ in AsyncThrowingStream { box.cont = $0 } }
        await send(s)
        XCTAssertEqual(s.chatMessages.last?.text, "byte's answer")

        // The turn is closed. Land the handoff now — it must be refused.
        box.cont?.yield(.routing(Self.routing("multi_agent")))
        box.cont?.finish()
        try? await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(s.chatMessages.last?.text, "byte's answer")
        XCTAssertNil(s.chatMessages.last?.vcRun)
    }
}

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

    /// Proves the store really called the fan-out. Without it, a test that asserts
    /// "nothing about the chat changed" would pass just as happily against a runner
    /// that never ran — "the feature correctly did nothing" and "the feature never
    /// happened" have to be distinguishable. Mutated only from the `vcRunner` closure,
    /// which the store invokes on the main actor, same as this suite.
    private final class RunnerProbe {
        var invocations = 0
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
        let probe = RunnerProbe()
        let consumed = expectation(description: "the store consumed the fan-out stream")
        let s = store { _ in
            probe.invocations += 1
            return AsyncThrowingStream { cont in
                cont.onTermination = { _ in consumed.fulfill() }
                cont.yield(.runStarted(runId: "r1"))
                cont.yield(.routing(Self.routing("single_agent")))
                cont.finish()
            }
        }
        await send(s)
        await fulfillment(of: [consumed], timeout: 2)
        // The run really happened and really was read — and still changed nothing.
        XCTAssertEqual(probe.invocations, 1)
        XCTAssertEqual(s.chatMessages.map(\.role), [.me, .companion])
        XCTAssertEqual(s.chatMessages.last?.text, "byte's answer")
        XCTAssertNil(s.chatMessages.last?.vcRun)
    }

    func testAKillSwitchOrCapLeavesTheChatExactlyAsItWas() async {
        let probe = RunnerProbe()
        let consumed = expectation(description: "the store consumed the fan-out stream")
        let s = store { _ in
            probe.invocations += 1
            return AsyncThrowingStream { cont in
                cont.onTermination = { _ in consumed.fulfill() }
                cont.finish(throwing: VirtualCompanyRunError.http(status: 503, body: nil))
            }
        }
        await send(s)
        await fulfillment(of: [consumed], timeout: 2)
        XCTAssertEqual(probe.invocations, 1)
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

    /// `virtualCompanyRun` cold-starts in 5–10s while byte's stream can finish in 4, so
    /// a routing frame can arrive after the founder has read the answer. Rewriting a
    /// finished, already-read message is the defect; `closedTurns` is the guard.
    ///
    /// The ordering is a handshake, not a sleep, and it is built so `closedTurns` is
    /// the ONLY thing that can stop the write — `vcTask.cancel()` cannot take the
    /// credit. The routing frame is handed to the fan-out while it is already parked
    /// in `next()` and the turn still owns the main actor, so the value is in the
    /// task's hands BEFORE the cancel; cancellation is cooperative and cannot reach
    /// back into a delivered element. The fan-out therefore resumes after the turn has
    /// closed, applies the routing, and calls `publishRunProgress` for real — which is
    /// exactly the production window this guard exists for.
    func testARunDecidingAfterTheTurnClosedCannotRewriteTheAnswer() async {
        final class Handshake {
            var events: AsyncThrowingStream<VirtualCompanyEvent, Error>.Continuation?
            var runnerStarted = false
            var waiter: CheckedContinuation<Void, Never>?
        }
        let h = Handshake()
        let probe = RunnerProbe()

        let s = CompanyStore(
            loader: { _ in .empty }, saver: { _, _ in true },
            chatSender: { _ in
                // Park until the fan-out has built its stream. Once its builder has
                // returned, the task's very next act is `next()` with nothing buffered,
                // and a continuation resumed on the main actor cannot preempt a task
                // that is still running — so by the time this resumes, the fan-out is
                // suspended waiting for its first frame.
                if !h.runnerStarted {
                    await withCheckedContinuation { h.waiter = $0 }
                }
                // Deliver the decision to that suspended consumer while THIS turn still
                // holds the actor. It lands before the turn closes and before cancel.
                h.events?.yield(.routing(Self.routing("multi_agent")))
                h.events?.finish()
                return CompanyChatReply(text: "byte's answer", runTaskId: nil)
            },
            chatStreamer: Self.failingStreamer,
            vcRunner: { _ in
                probe.invocations += 1
                return AsyncThrowingStream { cont in
                    h.events = cont
                    h.runnerStarted = true
                    if let waiter = h.waiter { h.waiter = nil; waiter.resume() }
                }
            })

        await send(s)
        // Let the fan-out resume and make its (refused) write attempt.
        try? await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(probe.invocations, 1)
        XCTAssertEqual(s.chatMessages.last?.text, "byte's answer")
        XCTAssertNil(s.chatMessages.last?.vcRun)
    }
}

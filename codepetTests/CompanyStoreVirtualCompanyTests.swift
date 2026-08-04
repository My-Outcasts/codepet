// codepetTests/CompanyStoreVirtualCompanyTests.swift
import XCTest
import Combine
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

    /// The room APPENDS. It is the whole point of the shape: the transcript scrolls on
    /// `chatMessages.count`, byte's own turn keeps its side effects and its typing dots,
    /// and byte's answer survives instead of being overwritten by the handoff line.
    func testTheRoomArrivesAsItsOwnMessageAndLeavesBytesAnswerAlone() async {
        let s = store { _ in
            AsyncThrowingStream {
                $0.yield(.runStarted(runId: "r1"))
                $0.yield(.routing(Self.routing("multi_agent")))
                $0.yield(.done(runId: "r1", unresolved: false, skipped: nil))
                $0.finish()
            }
        }
        await send(s)
        XCTAssertEqual(s.chatMessages.map(\.role), [.me, .companion, .companion])
        XCTAssertEqual(s.chatMessages[1].text, "byte's answer")
        XCTAssertNil(s.chatMessages[1].vcRun)
        XCTAssertEqual(s.chatMessages.last?.text,
                       "Actually — this one needs the whole room. Let me bring in product and finance.")
        XCTAssertEqual(s.chatMessages.last?.vcRun?.phase, .finished)
        XCTAssertFalse(s.isStreaming)
        XCTAssertFalse(s.isCompanionTyping)
    }

    /// Every later frame updates the SAME appended message — a run must not stack one
    /// message per frame down the transcript.
    func testEveryFrameOfOneRunLandsInOneMessage() async {
        let s = store { _ in
            AsyncThrowingStream {
                $0.yield(.routing(Self.routing("multi_agent")))
                $0.yield(.agentStart(VCAgentMeta(agentId: "product", departmentKey: "product")))
                $0.yield(.agentStart(VCAgentMeta(agentId: "finance", departmentKey: "fin")))
                $0.yield(.conflicts([VCConflict(a: "product", b: "finance",
                                                kind: "TENSION", reason: "r")]))
                $0.yield(.done(runId: "r1", unresolved: false, skipped: nil))
                $0.finish()
            }
        }
        await send(s)
        XCTAssertEqual(s.chatMessages.filter { $0.vcRun != nil }.count, 1)
        XCTAssertEqual(s.chatMessages.last?.vcRun?.agents.count, 2)
        XCTAssertEqual(s.chatMessages.last?.vcRun?.conflicts.count, 1)
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
    /// on the first decision of a session the routing frame usually arrives AFTER the
    /// turn has closed and the founder has read byte's answer. That used to be a defect
    /// — it rewrote a finished message — and needed a `closedTurns` guard that also
    /// stopped the room from ever convening on a cold start. Appending makes the same
    /// ordering correct: byte's answer stays, the room arrives underneath it, and the
    /// count change scrolls the founder to it.
    ///
    /// The ordering is a handshake, not a sleep: the routing frame is handed to the
    /// fan-out while it is already parked in `next()` and the turn still owns the main
    /// actor, so the frame is in the task's hands before the turn closes and the room
    /// necessarily publishes afterwards.
    func testARunDecidingAfterTheTurnClosedStillConvenesTheRoom() async {
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
        // Let the fan-out resume and append the room.
        try? await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(probe.invocations, 1)
        XCTAssertFalse(s.isStreaming, "the run must not hold the turn open")
        XCTAssertEqual(s.chatMessages.count, 3)
        XCTAssertEqual(s.chatMessages[1].text, "byte's answer", "byte's answer must survive")
        XCTAssertNotNil(s.chatMessages.last?.vcRun, "the room convenes even on a cold start")
    }

    /// The room belongs to the conversation its question was asked in. Nothing holds
    /// the turn open any more, so the founder can start a new chat while a run is still
    /// going — and the room must not land in it. The anchor check in
    /// `publishRunProgress` is the only thing standing here.
    func testARunDecidingAfterANewChatDoesNotLandInIt() async {
        final class Handshake {
            var events: AsyncThrowingStream<VirtualCompanyEvent, Error>.Continuation?
            var runnerStarted = false
            var waiter: CheckedContinuation<Void, Never>?
        }
        let h = Handshake()

        let s = CompanyStore(
            loader: { _ in .empty }, saver: { _, _ in true },
            chatSender: { _ in
                if !h.runnerStarted { await withCheckedContinuation { h.waiter = $0 } }
                return CompanyChatReply(text: "byte's answer", runTaskId: nil)
            },
            chatStreamer: Self.failingStreamer,
            vcRunner: { _ in
                AsyncThrowingStream { cont in
                    h.events = cont
                    h.runnerStarted = true
                    if let waiter = h.waiter { h.waiter = nil; waiter.resume() }
                }
            })

        await send(s)
        s.newChat()                       // the founder moves on, mid-run
        XCTAssertTrue(s.chatMessages.isEmpty)
        h.events?.yield(.routing(Self.routing("multi_agent")))
        h.events?.finish()
        try? await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertTrue(s.chatMessages.isEmpty, "the room must not land in a conversation it was not asked in")
    }

    // MARK: - Only a founder-typed chat turn convenes the room

    /// "Walk me through it" on a task card composes a founder-shaped ask and sends it
    /// through the same core as a typed message. It must NOT fan out: the founder asked
    /// for step-by-step guidance, and having it replaced by a meeting is a worse answer
    /// than the one they asked for.
    func testWalkThroughTaskNeverConvenesTheRoom() async {
        let probe = RunnerProbe()
        let s = store { _ in
            probe.invocations += 1
            return AsyncThrowingStream {
                $0.yield(.routing(Self.routing("multi_agent")))
                $0.finish()
            }
        }
        await s.hydrate(companyId: "u")
        let task = RoadmapTask(id: "t1", title: "Write the pricing page", detail: "one tier",
                               phase: .ship, who: .you, dept: "mkt")
        await s.walkThroughTask(task, language: .en)
        XCTAssertEqual(probe.invocations, 0, "a synthesised ask must not convene the company")
        XCTAssertNil(s.chatMessages.last?.vcRun)
    }

    /// `ChatMode.plan` prepends its framing before the send, which byte should see (the
    /// founder chose it) and the router should not: it decides `request_type` and
    /// rewrites the question into `real_question`.
    func testTheRouterSeesTheFoundersOwnWordsNotTheModesFraming() async {
        final class Asked { var requests: [String] = [] }
        let asked = Asked()
        let s = CompanyStore(loader: { _ in .empty }, saver: { _, _ in true },
                             chatSender: { _ in CompanyChatReply(text: "byte's answer", runTaskId: nil) },
                             chatStreamer: Self.failingStreamer,
                             vcRunner: { req in
                                 asked.requests.append(req.request)
                                 return AsyncThrowingStream { $0.finish() }
                             })
        await s.hydrate(companyId: "u")
        let raw = "team seats or single player first?"
        await s.sendChat(ChatMode.plan.shape(raw, language: .en), language: .en, founderAsk: raw)
        XCTAssertEqual(asked.requests, [raw])
    }

    // MARK: - Locking the brief in

    private static func aBrief(_ recommendation: String) -> VCBrief {
        VCBrief(recommendation: recommendation, confidence: 4, confidenceReason: "c",
                theRealDisagreement: "d", tradeoffFounderMustOwn: "t", killCriteria: ["k"],
                nextAction: VCNextAction(action: "a", owner: "Founder"),
                whatWeDontKnow: "u", unresolved: false)
    }

    /// Waits for the room to land, driven by the store's own `@Published` buffer rather
    /// than by a bounded sleep loop. A poll that expires and then force-unwraps traps,
    /// which aborts the XCTest HOST mid-suite with no failing assertion — worse than a
    /// missing test, because it discredits every other result in the run. A timeout here
    /// fails this test and nothing else.
    private func awaitRoom(in store: CompanyStore) async throws -> CopilotMessage {
        if let room = store.chatMessages.last(where: { $0.vcRun != nil }) { return room }
        let landed = expectation(description: "the room's message landed")
        landed.assertForOverFulfill = false
        let bag = store.$chatMessages.sink { messages in
            if messages.contains(where: { $0.vcRun != nil }) { landed.fulfill() }
        }
        defer { bag.cancel() }
        await fulfillment(of: [landed], timeout: 5)
        return try XCTUnwrap(store.chatMessages.last(where: { $0.vcRun != nil }),
                             "the room never landed")
    }

    /// Runs a real fan-out that delivers a brief, then hands back the room's own message
    /// — the same object the card's button is wired to.
    private func roomWithABrief(_ recommendation: String,
                                decisionsSaver: @escaping (String, [DecisionEntry]) async -> Bool = { _, _ in true })
    async throws -> (store: CompanyStore, messageId: String, run: VirtualCompanyRunState) {
        let s = CompanyStore(loader: { _ in .empty }, saver: { _, _ in true },
                             chatSender: { _ in CompanyChatReply(text: "byte's answer", runTaskId: nil) },
                             chatStreamer: Self.failingStreamer,
                             vcRunner: { _ in
                                 AsyncThrowingStream {
                                     $0.yield(.runStarted(runId: "r1"))
                                     $0.yield(.routing(Self.routing("multi_agent")))
                                     $0.yield(.brief(Self.aBrief(recommendation)))
                                     $0.yield(.done(runId: "r1", unresolved: false, skipped: nil))
                                     $0.finish()
                                 }
                             },
                             decisionsSaver: decisionsSaver)
        await send(s)
        // The run outlives the turn by design, so wait for the room rather than assuming
        // it has landed by the time `sendChat` returns.
        let room = try await awaitRoom(in: s)
        return (s, room.id, try XCTUnwrap(room.vcRun))
    }

    /// The feature's only call to action used to persist in silence. It must confirm in
    /// chat, mark itself consumed, and be idempotent.
    func testLockingInRecordsTheDecisionAndSaysSoOnce() async throws {
        final class SaveProbe { var saves = 0 }
        let probe = SaveProbe()
        let (s, roomId, run) = try await roomWithABrief("Price the single-player product first.",
                                                       decisionsSaver: { _, _ in probe.saves += 1; return true })
        XCTAssertTrue(run.canLockIn)
        let before = s.chatMessages.count

        await s.lockInVirtualCompanyDecision(run, messageId: roomId)
        XCTAssertEqual(s.company.decisions.map(\.statement), ["Price the single-player product first."])
        XCTAssertEqual(s.company.decisions.first?.source, "virtual-company/r1")
        XCTAssertEqual(s.chatMessages.first { $0.id == roomId }?.actionConsumed, true,
                       "the card must not offer the button again")
        XCTAssertEqual(s.chatMessages.count, before + 1)
        XCTAssertEqual(s.chatMessages.last?.noted?.first?.statement, "Price the single-player product first.")
        XCTAssertEqual(probe.saves, 1)

        // A second tap (or a double click) is a no-op, not a second chip.
        await s.lockInVirtualCompanyDecision(run, messageId: roomId)
        XCTAssertEqual(s.chatMessages.count, before + 1)
        XCTAssertEqual(s.company.decisions.count, 1)
        XCTAssertEqual(probe.saves, 1)
    }

    /// A blank recommendation used to make the button a silent no-op. Now the card does
    /// not offer it at all (`canLockIn`), and the store refuses it too.
    func testLockingInABlankRecommendationRecordsAndSaysNothing() async throws {
        let (s, roomId, run) = try await roomWithABrief("   ")
        XCTAssertFalse(run.canLockIn)
        let before = s.chatMessages.count
        await s.lockInVirtualCompanyDecision(run, messageId: roomId)
        XCTAssertTrue(s.company.decisions.isEmpty)
        XCTAssertEqual(s.chatMessages.count, before, "no chip")
        XCTAssertEqual(s.chatMessages.first { $0.id == roomId }?.actionConsumed, false)
    }

    // MARK: - The room sits under its own question

    /// NEW-1. Nothing holds the composer while a run is going, so the founder can finish
    /// another turn or two before the room lands. Appended, "Actually — this one needs the
    /// whole room" would drop under an unrelated answer and read as a reply to THAT. The
    /// anchor check guards which conversation the room belongs to; this guards where.
    func testTheRoomLandsUnderItsOwnQuestionNotAtTheBottom() async throws {
        final class Runs { var continuations: [AsyncThrowingStream<VirtualCompanyEvent, Error>.Continuation] = [] }
        let runs = Runs()
        let s = CompanyStore(
            loader: { _ in .empty }, saver: { _, _ in true },
            chatSender: { req in CompanyChatReply(text: "answer to: \(req.userMessage)", runTaskId: nil) },
            chatStreamer: Self.failingStreamer,
            vcRunner: { _ in
                AsyncThrowingStream { cont in
                    runs.continuations.append(cont)
                    // Decides nothing yet — the founder gets to move on first.
                }
            })
        await s.hydrate(companyId: "u")
        await s.sendChat("free with ads or $9.99 once?", language: .en)
        let anchorId = try XCTUnwrap(s.chatMessages.last?.id)

        // A second, unrelated turn completes while the first run is still thinking.
        await s.sendChat("how's my runway looking?", language: .en)
        XCTAssertEqual(s.chatMessages.count, 4)

        // Now the first run decides.
        runs.continuations.first?.yield(.routing(Self.routing("multi_agent")))
        runs.continuations.first?.finish()
        let room = try await awaitRoom(in: s)

        let anchorIdx = try XCTUnwrap(s.chatMessages.firstIndex { $0.id == anchorId })
        let roomIdx = try XCTUnwrap(s.chatMessages.firstIndex { $0.id == room.id })
        XCTAssertEqual(roomIdx, anchorIdx + 1,
                       "the room must sit directly under the question it answers")
        XCTAssertEqual(s.chatMessages.last?.text, "answer to: how's my runway looking?",
                       "the later turn must stay last — the room is not an answer to it")
    }
}

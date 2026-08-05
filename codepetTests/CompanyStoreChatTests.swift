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
                                 runTaskId: String? = nil, nav: NavAction? = nil,
                                 setup: SetupAction? = nil, remember: [RememberedFact] = [])
        -> (CompanyChatRequest) -> AsyncThrowingStream<CompanyChatStreamEvent, Error> {
        { _ in
            AsyncThrowingStream { continuation in
                for d in deltas { continuation.yield(.delta(d)) }
                let action = ChatDoneAction(runTaskId: runTaskId, nav: nav, setup: setup, remember: remember)
                continuation.yield(.done(model: model, cacheHit: cacheHit, action: action))
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

    // MARK: - navigate / setup / remember (chat tools)

    /// A `.done` carrying `nav` appends a nav-chip message (not an auto-navigate);
    /// tapping it (`activateNav`) then selects the resolved `AppView`.
    /// A `.done` carrying `nav` attaches the chip to the reply it belongs to rather
    /// than appending a second message. The chip used to arrive as its own `text: ""`
    /// message, which drew it outside the reply's bubble and outside the avatar
    /// column; riding on the reply lets the view draw it inside that card.
    func testDoneWithNavAttachesChipToReplyAndActivateNavSelects() async {
        let nav = NavAction(destination: "tasks", target: nil)
        let s = CompanyStore(loader: { _ in .empty }, saver: { _, _ in true },
                             chatSender: { _ in XCTFail("fallback must not run on a successful stream"); return nil },
                             chatStreamer: Self.streamer(deltas: ["Here"], nav: nav))
        await s.hydrate(companyId: "u")
        await s.sendChat("where should I look?", language: .en)
        XCTAssertEqual(s.chatMessages.map(\.role), [.me, .companion])
        XCTAssertEqual(s.chatMessages.last?.navChip, nav)
        XCTAssertEqual(s.chatMessages.last?.text, "Here")   // the reply kept its text
        XCTAssertEqual(s.view, .roadmap)   // still the default landing; unchanged until the chip is tapped
        s.activateNav(nav)
        XCTAssertEqual(s.view, .tasks)
    }

    /// A `nav` on a reply that carried ZERO chat text still rides the reply — the
    /// lead-in the tail writes IS that reply, so the chip belongs inside its bubble.
    ///
    /// This is the shape the live CF actually sends when it calls `navigate` and says
    /// nothing alongside it, and it used to draw the chip as a second, standalone row
    /// under the lead-in: the action was dispatched from inside the stream loop, so
    /// `inlineActionTarget` saw a placeholder that was still empty (its own non-empty
    /// -text guard rejected it) and took the append fallback. Observed in the app,
    /// Aug 5 — "On it — putting that together now." with a detached "Go to Company"
    /// chip below it, twice in a row. The order the fallback path always used (write
    /// the reply's text, THEN dispatch its actions) is now the order both paths use.
    func testNavOnATextlessReplyRidesTheLeadInBubble() async {
        let nav = NavAction(destination: "tasks", target: nil)
        let s = CompanyStore(loader: { _ in .empty }, saver: { _, _ in true },
                             chatSender: { _ in XCTFail("fallback must not run on a successful stream"); return nil },
                             chatStreamer: Self.streamer(deltas: [], nav: nav))
        await s.hydrate(companyId: "u")
        await s.sendChat("where should I look?", language: .en)
        XCTAssertEqual(s.chatMessages.map(\.role), [.me, .companion])   // no detached chip row
        XCTAssertEqual(s.chatMessages.count, 2)
        XCTAssertEqual(s.chatMessages.last?.navChip, nav)
        XCTAssertTrue(s.chatMessages.last?.text.contains("On it") ?? false)
    }

    /// `nav(department)` resolves `target` to a `DepartmentCatalog` key and opens
    /// that department's detail view (`selectedDeptKey`), not just the roster.
    func testActivateNavDepartmentSetsSelectedDeptKey() async {
        let nav = NavAction(destination: "department", target: "Engineering")
        let s = CompanyStore(loader: { _ in .empty }, saver: { _, _ in true },
                             chatSender: { _ in nil }, chatStreamer: Self.failingStreamer)
        await s.hydrate(companyId: "u")
        s.activateNav(nav)
        XCTAssertEqual(s.view, .company)
        XCTAssertEqual(s.selectedDeptKey, "eng")
    }

    /// A `.done` carrying `setup` appends a setup-suggestion message; the enable
    /// action is GUARDED — an already-enabled tool is never toggled off.
    func testDoneWithSetupAppendsSuggestionAndActivateSetupIsGuarded() async {
        let setup = SetupAction(category: "connectors", name: "GitHub")   // defaultOn: true — already enabled
        let s = CompanyStore(loader: { _ in .empty }, saver: { _, _ in true },
                             chatSender: { _ in XCTFail("fallback must not run on a successful stream"); return nil },
                             chatStreamer: Self.streamer(deltas: ["Here"], setup: setup))
        await s.hydrate(companyId: "u")
        await s.sendChat("what should I turn on?", language: .en)
        XCTAssertEqual(s.chatMessages.last?.setupSuggestion, setup)
        XCTAssertTrue(s.company.enabledTools.contains("github"))
        await s.activateSetup(setup)
        XCTAssertTrue(s.company.enabledTools.contains("github"))   // still on — not flipped off
    }

    /// Enabling an OFF tool via `activateSetup` resolves {category,name} → the
    /// `Toolkit` item id and turns it on (persisting via `toolsSaver`).
    func testActivateSetupEnablesOffTool() async {
        var savedIds: [String] = []
        let s = CompanyStore(loader: { _ in .empty }, saver: { _, _ in true },
                             chatSender: { _ in nil }, chatStreamer: Self.failingStreamer,
                             toolsSaver: { _, ids in savedIds = ids; return true })
        await s.hydrate(companyId: "u")
        XCTAssertFalse(s.company.enabledTools.contains("notion"))
        await s.activateSetup(SetupAction(category: "connectors", name: "Notion"))
        XCTAssertTrue(s.company.enabledTools.contains("notion"))
        XCTAssertTrue(savedIds.contains("notion"))
    }

    /// A `.done` carrying `remember` facts auto-merges into `company.decisions`,
    /// persists via `decisionsSaver`, and appends one transient "Noted" chip per fact.
    func testDoneWithRememberMergesDecisionsAndAppendsNotedChip() async {
        var savedDecisions: [DecisionEntry] = []
        let fact = RememberedFact(topic: "pricing", statement: "$10/mo")
        let s = CompanyStore(loader: { _ in .empty }, saver: { _, _ in true },
                             chatSender: { _ in XCTFail("fallback must not run on a successful stream"); return nil },
                             chatStreamer: Self.streamer(deltas: ["Got it"], remember: [fact]),
                             decisionsSaver: { _, decisions in savedDecisions = decisions; return true })
        await s.hydrate(companyId: "u")
        await s.sendChat("we're pricing at $10/mo", language: .en)
        XCTAssertTrue(s.company.decisions.contains { $0.topic == "pricing" && $0.statement == "$10/mo" })
        XCTAssertTrue(savedDecisions.contains { $0.topic == "pricing" })
        XCTAssertTrue(s.chatMessages.contains { $0.noted?.first?.topic == "pricing" })
    }

    /// `sendChat` populates `env_setup` from the company's currently-OFF toolkit
    /// items (mirrors the web's off-toolkit filter).
    func testSendChatPopulatesEnvSetupFromOffTools() async {
        var capturedEnvSetup: [SetupItemDTO]?
        let streamer: (CompanyChatRequest) -> AsyncThrowingStream<CompanyChatStreamEvent, Error> = { req in
            capturedEnvSetup = req.envSetup
            return AsyncThrowingStream { continuation in
                continuation.yield(.delta("hi"))
                continuation.yield(.done(model: "m", cacheHit: false, action: ChatDoneAction()))
                continuation.finish()
            }
        }
        let s = CompanyStore(loader: { _ in .empty }, saver: { _, _ in true },
                             chatSender: { _ in nil }, chatStreamer: streamer)
        await s.hydrate(companyId: "u")
        await s.sendChat("hi", language: .en)
        let names = Set((capturedEnvSetup ?? []).map(\.name))
        XCTAssertTrue(names.contains("Notion"))    // OFF by default
        XCTAssertFalse(names.contains("GitHub"))   // ON by default — must not be offered
    }

    // MARK: - department focus + specialist handoff

    /// A dept-chip send whose department maps to a NON-host specialist attributes
    /// the companion placeholder to that specialist (companionId + deptName) —
    /// the "Name · Dept" header conveys the handoff, no separate "Bringing in X" line.
    func testDeptChipSendAttributesPlaceholderToSpecialist() async {
        let dept = DepartmentCatalog.find("design")!
        let s = CompanyStore(loader: { _ in .empty }, saver: { _, _ in true },
                             chatSender: { _ in nil },
                             chatStreamer: Self.streamer(deltas: ["Here"]))
        await s.hydrate(companyId: "u")
        await s.sendChat("help me with the landing page", language: .en, department: dept)
        XCTAssertEqual(s.chatMessages.last?.companionId, DepartmentCompanions.companionId(for: "design"))
        XCTAssertEqual(s.chatMessages.last?.deptName, dept.name)
    }

    /// A plain send (no department chip, no department mention) stays on the
    /// host — the placeholder's `companionId` is nil.
    func testPlainSendStaysOnHostCompanion() async {
        let s = CompanyStore(loader: { _ in .empty }, saver: { _, _ in true },
                             chatSender: { _ in nil },
                             chatStreamer: Self.streamer(deltas: ["Hello"]))
        await s.hydrate(companyId: "u")
        await s.sendChat("hi there", language: .en)
        XCTAssertNil(s.chatMessages.last?.companionId)
        XCTAssertNil(s.chatMessages.last?.deptName)
    }

    /// `sendChat(_, language:, department:)` with the Engineering department AND a
    /// linked project routes to the local coding agent (`startCodeRun`) — the founder's
    /// ask is echoed as a plain `.me` message and a run is staged, but NO companion
    /// streaming turn is appended (neither `chatSender` nor `chatStreamer` is consulted).
    func testSendChatWithEngDeptAndLinkedProjectRoutesToCodingAgent() async throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("store-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let s = CompanyStore(
            loader: { _ in .empty }, saver: { _, _ in true },
            chatSender: { _ in XCTFail("must not call chat client when routed to coding agent"); return nil },
            chatStreamer: { _ in
                XCTFail("must not call chat streamer when routed to coding agent")
                return AsyncThrowingStream { $0.finish() }
            })
        await s.hydrate(companyId: "u")
        s.linkProject(path: dir.path, bootstrapClaudeMd: false)
        let eng = DepartmentCatalog.find("eng")!
        await s.sendChat("add a health check endpoint", language: .en, department: eng)
        XCTAssertNotNil(s.codingRun.run)                        // a run was staged
        XCTAssertEqual(s.chatMessages.map(\.role), [.me])       // no companion streaming turn
    }

    /// Without a linked project, the same Engineering-department ask does NOT route
    /// to the coding agent (mirrors `EditCodeRouting.shouldRoute`'s `projectLinked`
    /// gate) — it falls through to the ordinary grounded chat send.
    func testEngDeptWithoutLinkedProjectDoesNotRouteToCodingAgent() async {
        let s = CompanyStore(loader: { _ in .empty }, saver: { _, _ in true },
                             chatSender: { _ in nil },
                             chatStreamer: Self.streamer(deltas: ["On it"]))
        await s.hydrate(companyId: "u")
        let eng = DepartmentCatalog.find("eng")!
        await s.sendChat("add a health check endpoint", language: .en, department: eng)
        XCTAssertNil(s.codingRun.run)
        XCTAssertEqual(s.chatMessages.map(\.role), [.me, .companion])
    }

    // MARK: - composer .build-mode routing (view onSend is a thin switch)

    /// The composer's `.build` mode routes through `startCodeRun(ask:)` — NOT a
    /// chat turn: the founder's ask is echoed as a `.me` message and a run is
    /// staged (`codingRun.run != nil`), with neither `chatSender` nor
    /// `chatStreamer` consulted. `CopilotChatView.send()` is a thin `switch mode`
    /// over this store call for `.build`, so this asserts the store behavior the
    /// view delegates to (the view's onSend isn't independently unit-testable).
    func testBuildModeAskStagesCodeRunAndEchoesMessage() async {
        let s = CompanyStore(loader: { _ in .empty }, saver: { _, _ in true },
                             chatSender: { _ in XCTFail("build mode must not call chat client"); return nil },
                             chatStreamer: { _ in
                                 XCTFail("build mode must not call chat streamer")
                                 return AsyncThrowingStream { $0.finish() }
                             })
        await s.hydrate(companyId: "u")
        s.startCodeRun(ask: "add a health check endpoint")
        XCTAssertNotNil(s.codingRun.run)                   // a run was staged (.build → startCodeRun)
        XCTAssertEqual(s.chatMessages.map(\.role), [.me])  // echoed ask, no companion turn
        XCTAssertEqual(s.chatMessages.last?.text, "add a health check endpoint")
    }

    /// The `.ask`/`.plan` branch routes through the ordinary grounded chat path
    /// (streamed companion reply) — no run is staged. Mirrors `send()`'s `.ask`
    /// case, which calls `sendChat(_, language:, department:)`.
    func testAskModeRoutesToChatNotCodeRun() async {
        let s = CompanyStore(loader: { _ in .empty }, saver: { _, _ in true },
                             chatSender: { _ in nil },
                             chatStreamer: Self.streamer(deltas: ["On it"]))
        await s.hydrate(companyId: "u")
        await s.sendChat("what should I focus on?", language: .en, department: nil)
        XCTAssertNil(s.codingRun.run)                            // no run staged
        XCTAssertEqual(s.chatMessages.map(\.role), [.me, .companion])
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

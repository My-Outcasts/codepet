// codepetTests/CompanyStoreChatRunTests.swift
import XCTest
@testable import codepet

@MainActor
final class CompanyStoreChatRunTests: XCTestCase {
    private func seeded() -> CompanyState {
        CompanyState(brief: CompanyBrief(), departments: [], library: [], stage: .idea,
                     companionId: "byte", onboardedAt: Date(),
                     tasks: [RoadmapTask(id: "t1", title: "Survey users", detail: "wtp", phase: .find, who: .does)])
    }
    /// A `chatStreamer` that throws before yielding anything — forces the
    /// fallback-to-`chatSender` path deterministically, with no network and no
    /// dependency on `Auth.auth()` (unconfigured under XCTest).
    private static let failingStreamer: (CompanyChatRequest) -> AsyncThrowingStream<CompanyChatStreamEvent, Error> = { _ in
        AsyncThrowingStream { $0.finish(throwing: CompanyChatStreamError.notSignedIn) }
    }

    private func store(reply: CompanyChatReply?,
                       runner: @escaping (RunTaskRequest) async -> RunTaskResponse?,
                       saver: @escaping (String, [Deliverable]) async -> Bool = { _, _ in true })
        -> CompanyStore {
        // decisionExtractor stubbed: approveDraft now fires a fire-and-forget
        // rememberFromApproval, and its default hits DecisionsClient.extract (live
        // Firebase Auth) — would crash with an unconfigured FirebaseApp in the test bundle.
        // tasksSaver stubbed too: produceDraftInline now reflects a successful run onto
        // company.tasks (draft/drafted) and persists via tasksSaver — its default hits
        // the live Firestore.firestore(), which crashes with an unconfigured FirebaseApp.
        CompanyStore(loader: { _ in self.seeded() }, saver: { _, _ in true },
                     tasksSaver: { _, _ in true },
                     chatSender: { _ in reply }, chatStreamer: Self.failingStreamer,
                     taskRunner: runner, librarySaver: saver,
                     decisionExtractor: { _, _ in [] })
    }

    func testRunnableReplyProducesDraftNotInLibrary() async {
        let s = store(reply: CompanyChatReply(text: "On it", runTaskId: "t1"),
                      runner: { _ in RunTaskResponse(kind: "doc", title: "WTP", body: "# Q1") })
        await s.hydrate(companyId: "u")
        await s.sendChat("run the survey", language: .en)
        XCTAssertEqual(s.chatMessages.map(\.role), [.me, .companion, .companion])
        XCTAssertEqual(s.chatMessages[1].text, "On it")           // lead-in
        let draftMsg = s.chatMessages[2]
        XCTAssertEqual(draftMsg.draft?.sourceTaskId, "t1")
        XCTAssertFalse(draftMsg.draft?.id.isEmpty ?? true)
        XCTAssertTrue(draftMsg.draft?.createdAt?.hasSuffix("Z") ?? false)
        XCTAssertTrue(s.company.library.isEmpty)                  // draft NOT in library
        XCTAssertFalse(s.isCompanionTyping)
    }
    func testUnknownRunTaskIdNoDraft() async {
        let s = store(reply: CompanyChatReply(text: "hm", runTaskId: "nope"),
                      runner: { _ in RunTaskResponse(kind: "doc", title: "x", body: "# y") })
        await s.hydrate(companyId: "u")
        await s.sendChat("hi", language: .en)
        XCTAssertNil(s.chatMessages.last?.draft)
        // byte had already promised in the lead-in, so silence left the founder
        // watching a promise nobody kept. It now says why instead.
        XCTAssertEqual(s.chatMessages.count, 3)                   // me + lead-in + why
        XCTAssertTrue(s.chatMessages.last?.text.contains("can't find that task") == true)
    }

    func testARefusalNamesTheTaskAndTheReason() async {
        // Each refusal reason is a different founder action, so each has to be
        // distinguishable — "couldn't run it" would be useless for all four.
        let cases: [(RoadmapTask, String)] = [
            (RoadmapTask(id: "t1", title: "Survey users", detail: "", phase: .find,
                         who: .does, drafted: true), "waiting for your approval"),
            (RoadmapTask(id: "t1", title: "Survey users", detail: "", phase: .find,
                         who: .does, done: true), "already done"),
            (RoadmapTask(id: "t1", title: "Survey users", detail: "", phase: .find,
                         who: .you), "yours to do")
        ]
        for (task, expected) in cases {
            let s = CompanyStore(loader: { _ in
                CompanyState(brief: CompanyBrief(), departments: [], library: [], stage: .idea,
                             companionId: "byte", onboardedAt: Date(), tasks: [task])
            }, saver: { _, _ in true }, tasksSaver: { _, _ in true },
               chatSender: { _ in CompanyChatReply(text: "hm", runTaskId: "t1") },
               chatStreamer: Self.failingStreamer,
               taskRunner: { _ in XCTFail("an unrunnable task must not reach the runner"); return nil },
               decisionExtractor: { _, _ in [] })
            await s.hydrate(companyId: "u")
            await s.sendChat("hi", language: .en)

            XCTAssertNil(s.chatMessages.last?.draft)
            let text = s.chatMessages.last?.text ?? ""
            XCTAssertTrue(text.contains(expected), "expected \(expected) — got: \(text)")
            XCTAssertTrue(text.contains("Survey users"),
                          "the founder did not pick this task, byte did — naming it is what makes the refusal actionable")
        }
    }

    func testChatRunFailureHonestBubble() async {
        let s = store(reply: CompanyChatReply(text: "On it", runTaskId: "t1"),
                      runner: { _ in nil })
        await s.hydrate(companyId: "u")
        await s.sendChat("run it", language: .en)
        XCTAssertEqual(s.chatMessages.count, 3)
        XCTAssertNil(s.chatMessages[2].draft)                     // failure bubble, no draft
        XCTAssertFalse(s.chatMessages[2].text.isEmpty)
    }
    func testApproveDraftMovesToLibraryAndPersists() async {
        var saved: [Deliverable] = []
        let s = store(reply: CompanyChatReply(text: "On it", runTaskId: "t1"),
                      runner: { _ in RunTaskResponse(kind: "doc", title: "WTP", body: "# Q1") },
                      saver: { _, lib in saved = lib; return true })
        await s.hydrate(companyId: "u")
        await s.sendChat("run", language: .en)
        let mid = s.chatMessages[2].id
        await s.approveDraft(messageId: mid)
        XCTAssertEqual(s.company.library.count, 1)
        XCTAssertEqual(saved.count, 1)
        XCTAssertTrue(s.chatMessages[2].draftApproved)
        // second approve is a no-op
        await s.approveDraft(messageId: mid)
        XCTAssertEqual(s.company.library.count, 1)
    }
    /// If an Approve races an in-flight Redo, Approve wins: the redo must not overwrite
    /// the just-approved draft (card body would mismatch the persisted library entry).
    func testRedoDiscardsWhenApprovedMidRun() async {
        var ref: CompanyStore?
        var mid = ""
        var n = 0
        let s = CompanyStore(loader: { _ in self.seeded() }, saver: { _, _ in true },
                             tasksSaver: { _, _ in true },
                             chatSender: { _ in CompanyChatReply(text: "On it", runTaskId: "t1") },
                             chatStreamer: Self.failingStreamer,
                             taskRunner: { _ in
                                 n += 1
                                 if n == 2 { await ref?.approveDraft(messageId: mid) }
                                 return RunTaskResponse(kind: "doc", title: "WTP", body: n == 1 ? "# first" : "# second")
                             },
                             librarySaver: { _, _ in true },
                             decisionExtractor: { _, _ in [] })
        ref = s
        await s.hydrate(companyId: "u")
        await s.sendChat("run", language: .en)          // n=1 → draft "# first"
        mid = s.chatMessages[2].id
        await s.redoDraft(messageId: mid, language: .en) // n=2 → approve mid-run → redo discards "# second"
        XCTAssertTrue(s.chatMessages[2].draftApproved)
        XCTAssertEqual(s.chatMessages[2].draft?.body, "# first")   // not overwritten
        XCTAssertEqual(s.company.library.first?.body, "# first")   // card matches library
    }
    func testRedoReplacesDraft() async {
        var body = "# first"
        let s = store(reply: CompanyChatReply(text: "On it", runTaskId: "t1"),
                      runner: { _ in RunTaskResponse(kind: "doc", title: "WTP", body: body) })
        await s.hydrate(companyId: "u")
        await s.sendChat("run", language: .en)
        let mid = s.chatMessages[2].id
        let firstId = s.chatMessages[2].draft?.id
        body = "# second"
        await s.redoDraft(messageId: mid, language: .en)
        XCTAssertEqual(s.chatMessages[2].draft?.body, "# second")
        XCTAssertNotEqual(s.chatMessages[2].draft?.id, firstId)   // fresh deliverable
    }

    /// A revise chip tap (`redoDraft(...reviseNote:)`) must thread BOTH the note
    /// and the draft's CURRENT body into the RunTaskRequest, and still replace the
    /// draft on the same message — the wire contract + replace-in-place semantics
    /// the revise chips depend on.
    func testRedoWithReviseNoteSendsNoteAndCurrentBody() async {
        var captured: RunTaskRequest?
        let s = store(reply: CompanyChatReply(text: "On it", runTaskId: "t1"),
                      runner: { req in
                          captured = req
                          return RunTaskResponse(kind: "doc", title: "WTP", body: "# shorter")
                      })
        await s.hydrate(companyId: "u")
        await s.sendChat("run", language: .en)   // n=1 (no capture assertions here) → draft "# Q1"
        let mid = s.chatMessages[2].id
        let firstId = s.chatMessages[2].draft?.id
        let originalBody = s.chatMessages[2].draft?.body
        await s.redoDraft(messageId: mid, language: .en, reviseNote: "Make it shorter")
        XCTAssertEqual(captured?.reviseNote, "Make it shorter")
        XCTAssertEqual(captured?.current, originalBody)   // the draft's body BEFORE this redo
        XCTAssertEqual(s.chatMessages[2].draft?.body, "# shorter")   // draft replaced
        XCTAssertNotEqual(s.chatMessages[2].draft?.id, firstId)      // fresh deliverable, same message
    }

    /// A blind redo (no reviseNote, e.g. the existing Redo button) must send neither
    /// field — the wire shape stays unchanged for the pre-existing call path.
    func testRedoWithoutReviseNoteSendsNeitherField() async {
        var captured: RunTaskRequest?
        let s = store(reply: CompanyChatReply(text: "On it", runTaskId: "t1"),
                      runner: { req in
                          captured = req
                          return RunTaskResponse(kind: "doc", title: "WTP", body: "# again")
                      })
        await s.hydrate(companyId: "u")
        await s.sendChat("run", language: .en)
        let mid = s.chatMessages[2].id
        await s.redoDraft(messageId: mid, language: .en)
        XCTAssertNil(captured?.reviseNote)
        XCTAssertNil(captured?.current)
    }

    // MARK: - Streaming run_task_id (the streaming success path is now the
    // common one; run-task handling must fire from the streamed `.done` frame
    // too, not just the non-streaming fallback below).

    /// A synthetic streaming `chatStreamer` yielding one lead-in delta then
    /// `.done` carrying `runTaskId` — never throws, so `chatSender` (the
    /// fallback) must never be consulted.
    private static func runTaskStreamer(leadIn: String, runTaskId: String?)
        -> (CompanyChatRequest) -> AsyncThrowingStream<CompanyChatStreamEvent, Error> {
        { _ in
            AsyncThrowingStream { continuation in
                continuation.yield(.delta(leadIn))
                continuation.yield(.done(model: "m", cacheHit: false, action: ChatDoneAction(runTaskId: runTaskId)))
                continuation.finish()
            }
        }
    }

    func testStreamingDoneWithRunTaskIdProducesDraftNoFallback() async {
        let s = CompanyStore(loader: { _ in self.seeded() }, saver: { _, _ in true },
                             tasksSaver: { _, _ in true },
                             chatSender: { _ in XCTFail("fallback must not run on a successful stream"); return nil },
                             chatStreamer: Self.runTaskStreamer(leadIn: "On it", runTaskId: "t1"),
                             taskRunner: { _ in RunTaskResponse(kind: "doc", title: "WTP", body: "# Q1") },
                             decisionExtractor: { _, _ in [] })
        await s.hydrate(companyId: "u")
        await s.sendChat("run the survey", language: .en)
        XCTAssertEqual(s.chatMessages.map(\.role), [.me, .companion, .companion])
        XCTAssertEqual(s.chatMessages[1].text, "On it")           // lead-in, filled via deltas
        let draftMsg = s.chatMessages[2]
        XCTAssertEqual(draftMsg.draft?.sourceTaskId, "t1")
        XCTAssertFalse(draftMsg.draft?.id.isEmpty ?? true)
        XCTAssertTrue(s.company.library.isEmpty)                  // draft NOT in library
        XCTAssertFalse(s.isCompanionTyping)
        XCTAssertFalse(s.isStreaming)
    }

    func testStreamingDoneWithUnknownRunTaskIdNoDraft() async {
        let s = CompanyStore(loader: { _ in self.seeded() }, saver: { _, _ in true },
                             tasksSaver: { _, _ in true },
                             chatSender: { _ in XCTFail("fallback must not run on a successful stream"); return nil },
                             chatStreamer: Self.runTaskStreamer(leadIn: "hm", runTaskId: "nope"),
                             taskRunner: { _ in RunTaskResponse(kind: "doc", title: "x", body: "# y") },
                             decisionExtractor: { _, _ in [] })
        await s.hydrate(companyId: "u")
        await s.sendChat("hi", language: .en)
        XCTAssertNil(s.chatMessages.last?.draft)
        XCTAssertEqual(s.chatMessages.count, 3)                   // me + lead-in + why
        XCTAssertTrue(s.chatMessages.last?.text.contains("can't find that task") == true)
    }

    func testStreamingDoneWithNilRunTaskIdIsNoOp() async {
        let s = CompanyStore(loader: { _ in self.seeded() }, saver: { _, _ in true },
                             tasksSaver: { _, _ in true },
                             chatSender: { _ in XCTFail("fallback must not run on a successful stream"); return nil },
                             chatStreamer: Self.runTaskStreamer(leadIn: "hi", runTaskId: nil),
                             taskRunner: { _ in XCTFail("taskRunner must not run without a runTaskId"); return nil },
                             decisionExtractor: { _, _ in [] })
        await s.hydrate(companyId: "u")
        await s.sendChat("hi", language: .en)
        XCTAssertEqual(s.chatMessages.count, 2)
        XCTAssertNil(s.chatMessages.last?.draft)
    }

    /// The exact double-fire bug: byte replies with ONLY a run-task decision
    /// and NO chat text — the stream yields ZERO deltas then
    /// `.done(runTaskId:)`. Gating the fallback on empty text (instead of "no
    /// `.done` received") used to trip the fallback here too, firing a SECOND
    /// `chatSender` call and running `handleRunTaskId` again for the same
    /// task — a duplicate CF call and a duplicate draft card. Must now: never
    /// call `chatSender`, run the task exactly once, append exactly one
    /// draft, and fill the placeholder with the canned lead-in instead of
    /// leaving it blank.
    func testStreamingDoneRunTaskOnlyNoDeltasNoFallbackNoDoubleDraft() async {
        var runnerCalls = 0
        let streamer: (CompanyChatRequest) -> AsyncThrowingStream<CompanyChatStreamEvent, Error> = { _ in
            AsyncThrowingStream { continuation in
                continuation.yield(.done(model: "m", cacheHit: false, action: ChatDoneAction(runTaskId: "t1")))
                continuation.finish()
            }
        }
        let s = CompanyStore(loader: { _ in self.seeded() }, saver: { _, _ in true },
                             tasksSaver: { _, _ in true },
                             chatSender: { _ in XCTFail("fallback must not run on a run-task-only .done"); return nil },
                             chatStreamer: streamer,
                             taskRunner: { _ in
                                 runnerCalls += 1
                                 return RunTaskResponse(kind: "doc", title: "WTP", body: "# Q1")
                             },
                             decisionExtractor: { _, _ in [] })
        await s.hydrate(companyId: "u")
        await s.sendChat("run the survey", language: .en)
        XCTAssertEqual(s.chatMessages.map(\.role), [.me, .companion, .companion])
        XCTAssertEqual(runnerCalls, 1)                              // handleRunTaskId fired exactly once
        let placeholder = s.chatMessages[1]
        XCTAssertFalse(placeholder.text.isEmpty)                    // canned lead-in, not left blank
        XCTAssertNil(placeholder.draft)
        let draftMessages = s.chatMessages.filter { $0.draft?.sourceTaskId == "t1" }
        XCTAssertEqual(draftMessages.count, 1)                      // exactly ONE draft, not two
        XCTAssertFalse(s.isStreaming)
        XCTAssertFalse(s.isCompanionTyping)
    }

    /// The unrecoverable done+drafted race (final-review Important 1, chat path): `handleRunTaskId`'s
    /// `status == .codepetCanDo` guard runs BEFORE the `taskRunner` await inside
    /// `produceDraftInline`, so a mark-done that lands while the chat run is in flight must not be
    /// clobbered by the `drafted = true` write that follows. Simulates that landing by toggling
    /// `done` from inside the stubbed `taskRunner` itself — the chat card still carries the draft
    /// (its own Approve doesn't check `done`), but the task record must not be stranded.
    func testChatRunSkipsTaskDraftWriteWhenMarkedDoneMidRun() async {
        var ref: CompanyStore?
        let s = CompanyStore(loader: { _ in self.seeded() }, saver: { _, _ in true },
                             tasksSaver: { _, _ in true },
                             chatSender: { _ in CompanyChatReply(text: "On it", runTaskId: "t1") },
                             chatStreamer: Self.failingStreamer,
                             taskRunner: { _ in
                                 // Mark-done lands mid-await, exactly like the race in the wild.
                                 await ref?.toggleTaskDone(id: "t1")
                                 return RunTaskResponse(kind: "doc", title: "WTP", body: "# Q1")
                             },
                             decisionExtractor: { _, _ in [] })
        ref = s
        await s.hydrate(companyId: "u")
        await s.sendChat("run the survey", language: .en)
        XCTAssertTrue(s.company.tasks[0].done)            // mark-done won the race
        XCTAssertFalse(s.company.tasks[0].drafted)        // task-side draft write skipped
        XCTAssertNil(s.company.tasks[0].draft)            // never stranded on the task
        // The chat card is still the founder's escape hatch to reach the generated work.
        let draftMsg = s.chatMessages.last
        XCTAssertEqual(draftMsg?.draft?.sourceTaskId, "t1")
    }

    /// `sendChat` must populate the request's `runnable` from the company's
    /// current codepetCanDo tasks (mirrors the web's openTasks filter).
    func testSendChatPopulatesRunnableFromCodepetCanDoTasks() async {
        var capturedRunnable: [RunnableRef]?
        let streamer: (CompanyChatRequest) -> AsyncThrowingStream<CompanyChatStreamEvent, Error> = { req in
            capturedRunnable = req.runnable
            return AsyncThrowingStream { continuation in
                continuation.yield(.delta("hi"))
                continuation.yield(.done(model: "m", cacheHit: false, action: ChatDoneAction()))
                continuation.finish()
            }
        }
        let s = CompanyStore(loader: { _ in self.seeded() }, saver: { _, _ in true },
                             tasksSaver: { _, _ in true },
                             chatSender: { _ in nil }, chatStreamer: streamer,
                             taskRunner: { _ in nil }, decisionExtractor: { _, _ in [] })
        await s.hydrate(companyId: "u")
        await s.sendChat("hi", language: .en)
        XCTAssertEqual(capturedRunnable, [RunnableRef(id: "t1", title: "Survey users")])
    }
}

// codepetTests/CompanyStoreRunTaskTests.swift
import XCTest
@testable import codepet

@MainActor
final class CompanyStoreRunTaskTests: XCTestCase {
    private func task(_ id: String = "t1") -> RoadmapTask {
        RoadmapTask(id: id, title: "Survey users", detail: "wtp", phase: .find, who: .does)
    }
    private func store(_ runner: @escaping (RunTaskRequest) async -> RunTaskResponse?,
                       saver: @escaping (String, [Deliverable]) async -> Bool = { _, _ in true })
        -> CompanyStore {
        CompanyStore(loader: { _ in .empty }, saver: { _, _ in true },
                     taskRunner: runner, librarySaver: saver)
    }

    /// Updated for the run→approve rework: a run now stashes the deliverable as the
    /// task's `draft` (+ `drafted=true`) and persists via `tasksSaver` — it no longer
    /// writes `company.library` directly (that only happens on `approveTask`).
    func testRunProducesDeliverableAndPersists() async {
        var savedTasks: [RoadmapTask] = []
        let seed = CompanyState(brief: .init(), departments: [], library: [], stage: .building,
                                companionId: "byte", onboardedAt: Date(), tasks: [task()])
        let s = CompanyStore(loader: { _ in seed },
                             tasksSaver: { _, tasks in savedTasks = tasks; return true },
                             taskRunner: { _ in RunTaskResponse(kind: "doc", title: "WTP Survey", body: "# Q1") })
        await s.hydrate(companyId: "u")
        await s.runTask(s.company.tasks[0], language: .en)
        XCTAssertTrue(s.company.library.isEmpty)         // NOT written to library on run
        let d = s.company.tasks[0].draft
        XCTAssertEqual(d?.kind, .doc)
        XCTAssertEqual(d?.title, "WTP Survey")
        XCTAssertEqual(d?.sourceTaskId, "t1")
        XCTAssertFalse(d?.id.isEmpty ?? true)                    // unique id
        XCTAssertTrue(d?.createdAt?.hasSuffix("Z") ?? false)  // canonical UTC
        XCTAssertEqual(savedTasks.count, 1)              // tasks persisted
        XCTAssertNil(s.runError)
        XCTAssertTrue(s.runningTaskIds.isEmpty)
        XCTAssertTrue(s.company.tasks[0].drafted)        // → Awaiting approval
        XCTAssertFalse(s.company.tasks[0].done)          // not done until approved
    }
    func testEmptyBodyFailsOpenNoDeliverable() async {
        let s = store({ _ in RunTaskResponse(kind: "doc", title: "x", body: "   ") })
        await s.hydrate(companyId: "u")
        await s.runTask(task(), language: .en)
        XCTAssertTrue(s.company.library.isEmpty)
        XCTAssertNotNil(s.runError)
        XCTAssertTrue(s.runningTaskIds.isEmpty)
    }
    func testNilResultFailsOpen() async {
        let s = store({ _ in nil })
        await s.hydrate(companyId: "u")
        await s.runTask(task(), language: .en)
        XCTAssertTrue(s.company.library.isEmpty)
        XCTAssertNotNil(s.runError)
    }
    func testTitleFallsBackToTaskTitle() async {
        let seed = CompanyState(brief: .init(), departments: [], library: [], stage: .building,
                                companionId: "byte", onboardedAt: Date(), tasks: [task()])
        let s = CompanyStore(loader: { _ in seed },
                             tasksSaver: { _, _ in true },
                             taskRunner: { _ in RunTaskResponse(kind: "doc", title: "  ", body: "# body") })
        await s.hydrate(companyId: "u")
        await s.runTask(s.company.tasks[0], language: .en)
        XCTAssertEqual(s.company.tasks[0].draft?.title, "Survey users")
    }
    func testAccountSwitchMidRunDiscards() async {
        var ref: CompanyStore?
        let s = CompanyStore(loader: { _ in .empty }, saver: { _, _ in true },
                             taskRunner: { _ in await ref?.hydrate(companyId: "B"); return RunTaskResponse(kind: "doc", title: "x", body: "# y") },
                             librarySaver: { _, _ in true })
        ref = s
        await s.hydrate(companyId: "A")
        await s.runTask(task(), language: .en)
        XCTAssertTrue(s.company.library.isEmpty)   // discarded on switch
        XCTAssertTrue(s.runningTaskIds.isEmpty)
    }
    func testResetClearsRunState() async {
        let s = store({ _ in nil })
        await s.hydrate(companyId: "u")
        await s.runTask(task(), language: .en)
        s.reset()
        XCTAssertNil(s.runError)
        XCTAssertTrue(s.runningTaskIds.isEmpty)
    }
    /// An account switch via hydrate(differentId) must clear stale run state so account
    /// A's error/spinner doesn't bleed into account B (mirrors the chat-state clearing).
    func testAccountSwitchViaHydrateClearsRunState() async {
        let s = store({ _ in nil })   // nil → sets runError on account A
        await s.hydrate(companyId: "A")
        await s.runTask(task(), language: .en)
        XCTAssertNotNil(s.runError)
        await s.hydrate(companyId: "B")
        XCTAssertNil(s.runError)
        XCTAssertTrue(s.runningTaskIds.isEmpty)
    }

    func testRunTaskStashesDraftAndMarksDraftedWithoutTouchingLibrary() async {
        var tasksSaved = false, librarySaved = false
        let seed = CompanyState(brief: .init(), departments: [], library: [], stage: .building,
                                companionId: "byte", onboardedAt: Date(),
                                tasks: [RoadmapTask(id: "t1", title: "T", detail: "", phase: .find, who: .does)])
        let s = CompanyStore(
            loader: { _ in seed },
            tasksSaver: { _, _ in tasksSaved = true; return true },
            taskRunner: { _ in RunTaskResponse(kind: "doc", title: "Out", body: "the body") },
            librarySaver: { _, _ in librarySaved = true; return true })
        await s.hydrate(companyId: "u")
        await s.runTask(s.company.tasks[0], language: .en)
        XCTAssertNotNil(s.company.tasks[0].draft)        // draft stashed on task
        XCTAssertTrue(s.company.tasks[0].drafted)        // → Awaiting approval
        XCTAssertFalse(s.company.tasks[0].done)
        XCTAssertTrue(s.company.library.isEmpty)         // NOT added to library on run
        XCTAssertTrue(tasksSaved)                        // tasks persisted
        XCTAssertFalse(librarySaved)                     // library not persisted on run
    }

    func testRunTaskDedupesWhenAlreadyDrafted() async {
        var runs = 0
        let drafted = RoadmapTask(id: "t1", title: "T", detail: "", phase: .find, who: .does,
                                  drafted: true, draft: Deliverable(kind: .doc, title: "D", body: "b", sourceTaskId: "t1"))
        let seed = CompanyState(brief: .init(), departments: [], library: [], stage: .building,
                                companionId: "byte", onboardedAt: Date(), tasks: [drafted])
        let s = CompanyStore(loader: { _ in seed },
                             taskRunner: { _ in runs += 1; return RunTaskResponse(kind: "doc", title: "X", body: "y") })
        await s.hydrate(companyId: "u")
        await s.runTask(s.company.tasks[0], language: .en)
        XCTAssertEqual(runs, 0)                           // already drafted → not re-run
        XCTAssertEqual(s.company.library.count, 0)
    }

    func testApproveTaskMovesDraftToLibraryOnceAndMarksDone() async {
        let drafted = RoadmapTask(id: "t1", title: "T", detail: "", phase: .find, who: .does,
                                  drafted: true, draft: Deliverable(kind: .doc, title: "D", body: "b", sourceTaskId: "t1"))
        let seed = CompanyState(brief: .init(), departments: [], library: [], stage: .building,
                                companionId: "byte", onboardedAt: Date(), tasks: [drafted])
        // Stub both savers — approveTask's persistence path would otherwise hit real
        // CompanyData.saveLibrary/saveTasks (Firestore) with an unconfigured FirebaseApp
        // in the test bundle and crash (SIGABRT), not the Xcode 26.2 teardown bug.
        // decisionExtractor is stubbed too: approveTask now fires a fire-and-forget
        // rememberFromApproval, and its default hits DecisionsClient.extract (live
        // Firebase Auth) — same unconfigured-FirebaseApp crash risk.
        let s = CompanyStore(loader: { _ in seed },
                             tasksSaver: { _, _ in true },
                             librarySaver: { _, _ in true },
                             firstApprovalSaver: { _, _ in true },
                             decisionExtractor: { _, _ in [] })
        await s.hydrate(companyId: "u")
        await s.approveTask(id: "t1")
        XCTAssertEqual(s.company.library.count, 1)        // moved to library once
        XCTAssertEqual(s.company.library[0].title, "D")
        XCTAssertTrue(s.company.tasks[0].done)
        XCTAssertFalse(s.company.tasks[0].drafted)
        XCTAssertNil(s.company.tasks[0].draft)            // consumed
        await s.approveTask(id: "t1")                     // idempotent
        XCTAssertEqual(s.company.library.count, 1)        // no duplicate
    }

    func testApproveTaskNoOpWithoutDraft() async {
        let seed = CompanyState(brief: .init(), departments: [], library: [], stage: .building,
                                companionId: "byte", onboardedAt: Date(),
                                tasks: [RoadmapTask(id: "t1", title: "T", detail: "", phase: .find, who: .does)])
        let s = CompanyStore(loader: { _ in seed })
        await s.hydrate(companyId: "u")
        await s.approveTask(id: "t1")
        XCTAssertTrue(s.company.library.isEmpty)
        XCTAssertFalse(s.company.tasks[0].done)
    }

    func testRunTaskCarriesStructuredPayloadOntoDraft() async {
        let drafted = RoadmapTask(id: "t1", title: "T", detail: "", phase: .find, who: .does)
        let seed = CompanyState(brief: .init(), departments: [], library: [], stage: .building,
                                companionId: "byte", onboardedAt: Date(), tasks: [drafted])
        let s = CompanyStore(loader: { _ in seed },
                             tasksSaver: { _, _ in true },
            taskRunner: { _ in RunTaskResponse(kind: "checklist", title: "C", body: "md",
                payload: DeliverablePayload(items: [ChecklistItem(t: "Step", done: false)])) })
        await s.hydrate(companyId: "u")
        await s.runTask(s.company.tasks[0], language: .en)
        XCTAssertEqual(s.company.tasks[0].draft?.payload?.items?.first?.t, "Step")
    }
    func testApproveExtractsMergesAndPersistsDecisions() async {
        var savedDecisions: [DecisionEntry]?
        let drafted = RoadmapTask(id: "t1", title: "T", detail: "", phase: .find, who: .does,
                                  drafted: true, draft: Deliverable(kind: .doc, title: "Pricing", body: "Plus $4/mo", sourceTaskId: "t1"))
        let seed = CompanyState(brief: .init(), departments: [], library: [], stage: .building,
                                companionId: "byte", onboardedAt: Date(), tasks: [drafted])
        let s = CompanyStore(loader: { _ in seed },
                             tasksSaver: { _, _ in true },
                             librarySaver: { _, _ in true },
                             firstApprovalSaver: { _, _ in true },
                             decisionsSaver: { _, d in savedDecisions = d; return true },
                             decisionExtractor: { _, _ in [ExtractedDecision(topic: "pricing", statement: "Plus $4/mo", source: "Pricing")] })
        await s.hydrate(companyId: "u")
        await s.approveTask(id: "t1")
        // fire-and-forget Task — allow it to run
        await Task.yield(); try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(s.company.decisions.first?.topic, "pricing")
        XCTAssertEqual(savedDecisions?.first?.statement, "Plus $4/mo")
    }
    func testReviseTaskDraftReplacesDraftInPlaceAndPersists() async {
        var savedTasks: [RoadmapTask] = []
        var sentReq: RunTaskRequest?
        let drafted = RoadmapTask(id: "t1", title: "T", detail: "", phase: .find, who: .does,
                                  drafted: true, draft: Deliverable(kind: .doc, title: "D", body: "long body", sourceTaskId: "t1"))
        let seed = CompanyState(brief: .init(), departments: [], library: [], stage: .building,
                                companionId: "byte", onboardedAt: Date(), tasks: [drafted])
        let s = CompanyStore(loader: { _ in seed },
                             tasksSaver: { _, tasks in savedTasks = tasks; return true },
                             taskRunner: { req in sentReq = req; return RunTaskResponse(kind: "doc", title: "D2", body: "short") })
        await s.hydrate(companyId: "u")
        await s.reviseTaskDraft(taskId: "t1", reviseNote: "Make it shorter", language: .en)
        XCTAssertEqual(sentReq?.reviseNote, "Make it shorter")   // note threaded through
        XCTAssertEqual(sentReq?.current, "long body")            // current body threaded through
        XCTAssertEqual(s.company.tasks[0].draft?.body, "short")  // draft replaced in place
        XCTAssertEqual(s.company.tasks[0].draft?.title, "D2")
        XCTAssertTrue(s.company.tasks[0].drafted)                // still awaiting approval
        XCTAssertFalse(s.company.tasks[0].done)                  // not approved
        XCTAssertTrue(s.company.library.isEmpty)                 // never touches library
        XCTAssertEqual(savedTasks.count, 1)                      // persisted via tasksSaver
    }

    func testReviseTaskDraftNoOpWhenNoDraft() async {
        var runs = 0
        let seed = CompanyState(brief: .init(), departments: [], library: [], stage: .building,
                                companionId: "byte", onboardedAt: Date(),
                                tasks: [RoadmapTask(id: "t1", title: "T", detail: "", phase: .find, who: .does)])
        let s = CompanyStore(loader: { _ in seed },
                             taskRunner: { _ in runs += 1; return RunTaskResponse(kind: "doc", title: "X", body: "y") })
        await s.hydrate(companyId: "u")
        await s.reviseTaskDraft(taskId: "t1", reviseNote: "Make it shorter", language: .en)
        XCTAssertEqual(runs, 0)   // no draft → never runs
    }

    /// The unrecoverable done+drafted race (final-review Important 1, board path): `runTask`'s
    /// `!done` guard runs BEFORE the `taskRunner` await, so a mark-done that lands while the run
    /// is in flight must not be clobbered by the write that follows the await. Simulates that
    /// landing by toggling `done` from inside the stubbed `taskRunner` itself.
    func testRunTaskSkipsDraftWriteWhenMarkedDoneMidRun() async {
        var tasksSaverCalls = 0
        let seed = CompanyState(brief: .init(), departments: [], library: [], stage: .building,
                                companionId: "byte", onboardedAt: Date(), tasks: [task()])
        var ref: CompanyStore?
        let s = CompanyStore(loader: { _ in seed },
                             tasksSaver: { _, _ in tasksSaverCalls += 1; return true },
                             taskRunner: { _ in
                                 // Mark-done (the panel's "I already did this") lands here,
                                 // mid-await, exactly like the chat/board race in the wild.
                                 await ref?.toggleTaskDone(id: "t1")
                                 return RunTaskResponse(kind: "doc", title: "Out", body: "the body")
                             })
        ref = s
        await s.hydrate(companyId: "u")
        await s.runTask(s.company.tasks[0], language: .en)
        XCTAssertTrue(s.company.tasks[0].done)            // mark-done won the race
        XCTAssertFalse(s.company.tasks[0].drafted)        // draft write skipped — not stranded
        XCTAssertNil(s.company.tasks[0].draft)
        XCTAssertEqual(tasksSaverCalls, 1)                // only toggleTaskDone's own save fired
    }

    // MARK: - Provenance wiring (review Finding 1 + Finding 2)

    /// FINDING 1: every test above omits `claudeAuthorisation:`, so `currentProvider(for:)`
    /// falls back to a real, ungranted `UserDefaults` read and `producedBy` is nil on every
    /// draft they produce — including the five `buildDeliverable` call sites this file
    /// otherwise exercises directly (`runTask` → `produceDraftInline`). None of them would
    /// notice `producedBy: currentProvider(for: cid)` being deleted and replaced with `nil`.
    ///
    /// This test drives the real call site — `runTask`, not `buildDeliverable` in isolation —
    /// with an INJECTED, granted `ProviderAuthorisation` so it never touches the founder's
    /// real defaults domain.
    func testRunTaskStampsDraftWithTheGrantedProvider_claudeCode() async {
        let seed = CompanyState(brief: .init(), departments: [], library: [], stage: .building,
                                companionId: "byte", onboardedAt: Date(), tasks: [task()])
        let auth = ProviderAuthorisation(isAuthorised: { provider, _ in provider == .claudeCode })
        let s = CompanyStore(loader: { _ in seed },
                             tasksSaver: { _, _ in true },
                             taskRunner: { _ in RunTaskResponse(kind: "doc", title: "T", body: "body") },
                             claudeAuthorisation: auth)
        await s.hydrate(companyId: "u")
        await s.runTask(s.company.tasks[0], language: .en)
        XCTAssertEqual(s.company.tasks[0].draft?.producedBy, .claudeCode)
    }

    /// The one that proves the feature is genuinely PER-PROVIDER rather than a constant:
    /// only Codex is granted here (Claude is not), and the stamp must follow the grant, not
    /// default to the incumbent.
    func testRunTaskStampsDraftWithTheGrantedProvider_codexOnly() async {
        let seed = CompanyState(brief: .init(), departments: [], library: [], stage: .building,
                                companionId: "byte", onboardedAt: Date(), tasks: [task()])
        let auth = ProviderAuthorisation(isAuthorised: { provider, _ in provider == .codex })
        let s = CompanyStore(loader: { _ in seed },
                             tasksSaver: { _, _ in true },
                             taskRunner: { _ in RunTaskResponse(kind: "doc", title: "T", body: "body") },
                             claudeAuthorisation: auth)
        await s.hydrate(companyId: "u")
        await s.runTask(s.company.tasks[0], language: .en)
        XCTAssertEqual(s.company.tasks[0].draft?.producedBy, .codex)
    }

    /// FINDING 2 (the provable half): the stamp's INPUT is this store's own authorisation,
    /// not a hardcoded value — flipping the grant on an otherwise-identical store flips the
    /// stamped provider. This does NOT prove the stamp matches what `RunTaskClient.run` would
    /// actually spend in production — see the invariant documented on `currentProvider` for
    /// what remains unproven and why.
    func testStampFollowsAuthorisationChange_notAConstant() async {
        func makeStore(granting provider: AIProvider) -> CompanyStore {
            let seed = CompanyState(brief: .init(), departments: [], library: [], stage: .building,
                                    companionId: "byte", onboardedAt: Date(), tasks: [task()])
            let auth = ProviderAuthorisation(isAuthorised: { p, _ in p == provider })
            return CompanyStore(loader: { _ in seed },
                                tasksSaver: { _, _ in true },
                                taskRunner: { _ in RunTaskResponse(kind: "doc", title: "T", body: "b") },
                                claudeAuthorisation: auth)
        }
        let claudeStore = makeStore(granting: .claudeCode)
        await claudeStore.hydrate(companyId: "u")
        await claudeStore.runTask(claudeStore.company.tasks[0], language: .en)

        let codexStore = makeStore(granting: .codex)
        await codexStore.hydrate(companyId: "u")
        await codexStore.runTask(codexStore.company.tasks[0], language: .en)

        XCTAssertEqual(claudeStore.company.tasks[0].draft?.producedBy, .claudeCode)
        XCTAssertEqual(codexStore.company.tasks[0].draft?.producedBy, .codex)
        XCTAssertNotEqual(claudeStore.company.tasks[0].draft?.producedBy,
                          codexStore.company.tasks[0].draft?.producedBy)
    }

    // MARK: - reRunDeliverable end-to-end (Critical 3, final-review pass)

    /// A filed library deliverable behind a `done` task — the shape `reRunDeliverable`
    /// re-runs. `producedBy: .claudeCode` is the ORIGINAL run's stamp; the re-run below taps
    /// a different provider deliberately, so a passing test cannot be explained by the stamp
    /// just being copied forward.
    private func filedDeliverable() -> (task: RoadmapTask, seed: CompanyState) {
        let filedTask = RoadmapTask(id: "t1", title: "Survey users", detail: "wtp",
                                    phase: .find, who: .does, done: true)
        let filed = Deliverable(kind: .doc, title: "D", body: "original body",
                                sourceTaskId: "t1", producedBy: .claudeCode)
        let seed = CompanyState(brief: .init(), departments: [], library: [filed], stage: .building,
                                companionId: "byte", onboardedAt: Date(), tasks: [filedTask])
        return (filedTask, seed)
    }

    /// The headline claim under test: the provider that ACTUALLY RUNS is the one the founder
    /// tapped, not `chooseProvider`'s precedence winner. Both providers are granted here —
    /// under plain precedence Claude would win — and the founder taps Codex anyway. A revert
    /// of `preferredTaskRunner(…, resolved)` back to `taskRunner(…)` (the unpreferred runner)
    /// would still pass every OTHER test in this file, which is exactly the gap review found:
    /// "Re-run on Codex" did not actually run on Codex, caught only by reading code.
    func testReRunDeliverableRunsOnTheTappedProviderNotThePrecedenceWinner() async {
        let (_, seed) = filedDeliverable()
        var receivedProvider: AIProvider?
        let auth = ProviderAuthorisation(isAuthorised: { _, _ in true })  // both granted
        let s = CompanyStore(
            loader: { _ in seed },
            preferredTaskRunner: { _, provider in
                receivedProvider = provider
                return RunTaskResponse(kind: "doc", title: "D2", body: "codex body")
            },
            librarySaver: { _, _ in true },
            // `fileApproval` (what `reRunDeliverable` ends on) also fires `firstApprovalSaver`
            // and a fire-and-forget `decisionExtractor` — both default to real Firestore/Auth
            // calls that TRAP under an unconfigured `FirebaseApp` in the test host (landmine 3
            // in CLAUDE.md). Stubbed here for the same reason
            // `testApproveTaskMovesDraftToLibraryOnceAndMarksDone` above stubs them.
            firstApprovalSaver: { _, _ in true },
            decisionExtractor: { _, _ in [] },
            claudeAuthorisation: auth)
        await s.hydrate(companyId: "u")
        let deliverable = s.company.library[0]
        await s.reRunDeliverable(deliverable, preferring: .codex, language: .en)

        // 1. The provider HANDED TO THE RUNNER is the tapped one, not the precedence winner.
        XCTAssertEqual(receivedProvider, .codex)
        // 2. The resulting deliverable's stamp equals that same provider.
        XCTAssertEqual(s.company.library.count, 2, "the re-run files a NEW entry; the original stays")
        XCTAssertEqual(s.company.library.last?.producedBy, .codex)
        XCTAssertEqual(s.company.library.last?.body, "codex body")
        // The original stays untouched.
        XCTAssertEqual(s.company.library.first?.producedBy, .claudeCode)
    }

    /// A preference is not consent: tapping a provider the founder never granted must not
    /// run at all — not on the tapped provider, and not by silently falling back to the one
    /// that IS granted.
    func testReRunDeliverableDoesNotRunAnUngrantedProvider() async {
        let (_, seed) = filedDeliverable()
        var runnerCalls = 0
        let auth = ProviderAuthorisation(isAuthorised: { provider, _ in provider == .claudeCode })
        let s = CompanyStore(
            loader: { _ in seed },
            preferredTaskRunner: { _, provider in
                runnerCalls += 1
                return RunTaskResponse(kind: "doc", title: "D2", body: "should not happen")
            },
            librarySaver: { _, _ in true },
            claudeAuthorisation: auth)
        await s.hydrate(companyId: "u")
        let deliverable = s.company.library[0]
        await s.reRunDeliverable(deliverable, preferring: .codex, language: .en)

        XCTAssertEqual(runnerCalls, 0, "an ungranted preference must not run at all")
        XCTAssertEqual(s.company.library.count, 1, "nothing new was filed")
    }

    func testApproveFailOpenWhenExtractorReturnsEmpty() async {
        let drafted = RoadmapTask(id: "t1", title: "T", detail: "", phase: .find, who: .does,
                                  drafted: true, draft: Deliverable(kind: .doc, title: "X", body: "y", sourceTaskId: "t1"))
        let seed = CompanyState(brief: .init(), departments: [], library: [], stage: .building,
                                companionId: "byte", onboardedAt: Date(), tasks: [drafted])
        let s = CompanyStore(loader: { _ in seed },
                             tasksSaver: { _, _ in true },
                             librarySaver: { _, _ in true },
                             firstApprovalSaver: { _, _ in true },
                             decisionExtractor: { _, _ in [] })
        await s.hydrate(companyId: "u")
        await s.approveTask(id: "t1")
        await Task.yield(); try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertTrue(s.company.decisions.isEmpty)   // nothing extracted → unchanged
        XCTAssertTrue(s.company.tasks[0].done)        // approval still completed
    }
}

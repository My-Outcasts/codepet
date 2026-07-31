import XCTest
@testable import codepet

@MainActor
final class CompanyStoreVerbDispatchTests: XCTestCase {

    /// Seed + injected fakes, mirroring CompanyStoreFanOutTests: no live Firestore.
    private func store(tasks: [RoadmapTask],
                       streamer: @escaping (CompanyChatRequest) -> AsyncThrowingStream<CompanyChatStreamEvent, Error>,
                       roadmapFetcher: @escaping (CompanyBrief, AppLanguage) async -> [RoadmapTask] = { _, _ in [] }
    ) -> CompanyStore {
        let seed = CompanyState(brief: .init(), departments: [], library: [], stage: .building,
                                companionId: "byte", onboardedAt: Date(), tasks: tasks)
        return CompanyStore(loader: { _ in seed },
                            roadmapFetcher: roadmapFetcher,
                            tasksSaver: { _, _ in true },
                            chatSender: { _ in nil },   // never hit the real Firebase-backed client
                            chatStreamer: streamer,
                            librarySaver: { _, _ in true },
                            threadSaver: { _, _ in true },
                            threadsLoader: { _ in [] })
    }

    /// A stream that yields exactly one `.done` with the given action, then finishes.
    private func doneStream(_ action: ChatDoneAction) -> AsyncThrowingStream<CompanyChatStreamEvent, Error> {
        AsyncThrowingStream { c in
            c.yield(.delta("ok"))
            c.yield(.done(model: "m", cacheHit: false, action: action))
            c.finish()
        }
    }

    func testRePlanRegeneratesRoadmap() async {
        let fresh = [RoadmapTask(id: "n1", title: "New plan task", detail: "", phase: .build, who: .you)]
        let s = store(tasks: [RoadmapTask(id: "old", title: "Old", detail: "", phase: .find, who: .you)],
                      streamer: { _ in self.doneStream(ChatDoneAction(rePlan: true)) },
                      roadmapFetcher: { _, _ in fresh })
        await s.hydrate(companyId: "u")
        await s.sendChat("please re-plan", language: .en)
        XCTAssertEqual(s.company.tasks.map(\.id), ["n1"], "re_plan should replace tasks via roadmapFetcher")
    }

    func testWalkthroughUnknownIdIsNoOp() async {
        let s = store(tasks: [RoadmapTask(id: "t2", title: "Pick a name", detail: "", phase: .foundation, who: .you)],
                      streamer: { _ in self.doneStream(ChatDoneAction(walkthrough: WalkthroughAction(taskId: "nope"))) })
        await s.hydrate(companyId: "u")
        await s.sendChat("hi", language: .en)
        // Only THIS send's founder message; no extra guided turn from an unknown id.
        XCTAssertEqual(s.chatMessages.filter { $0.role == .me }.count, 1,
                       "unknown walkthrough id must not start a second founder turn")
    }

    func testWalkthroughKnownIdStartsGuidedTurn() async {
        var calls = 0
        // First send → done(walkthrough t2). The nested walkThroughTask send → plain text.
        let streamer: (CompanyChatRequest) -> AsyncThrowingStream<CompanyChatStreamEvent, Error> = { _ in
            calls += 1
            if calls == 1 { return self.doneStream(ChatDoneAction(walkthrough: WalkthroughAction(taskId: "t2"))) }
            return self.doneStream(ChatDoneAction())   // guided turn's reply: plain, no further verbs
        }
        let s = store(tasks: [RoadmapTask(id: "t2", title: "Pick a name", detail: "", phase: .foundation, who: .you)],
                      streamer: streamer)
        await s.hydrate(companyId: "u")
        await s.sendChat("hi", language: .en)
        XCTAssertTrue(s.chatMessages.contains { $0.role == .me && $0.text.contains("Pick a name") },
                      "known walkthrough id should start the guided 'walk me through … Pick a name' turn")
    }

    /// A reply carrying BOTH verbs: re_plan runs first (replaces tasks), then the
    /// walkthrough id resolves against the POST-replan task set. Locks the deliberate
    /// ordering in handleDoneAction (final-review item #3).
    func testRePlanThenWalkthroughResolvesAgainstNewTasks() async {
        var calls = 0
        let fresh = [RoadmapTask(id: "n1", title: "Fresh task", detail: "", phase: .build, who: .you)]
        let streamer: (CompanyChatRequest) -> AsyncThrowingStream<CompanyChatStreamEvent, Error> = { _ in
            calls += 1
            if calls == 1 {
                return self.doneStream(ChatDoneAction(rePlan: true, walkthrough: WalkthroughAction(taskId: "n1")))
            }
            return self.doneStream(ChatDoneAction())   // the guided turn's reply
        }
        let s = store(tasks: [RoadmapTask(id: "old", title: "Old task", detail: "", phase: .find, who: .you)],
                      streamer: streamer,
                      roadmapFetcher: { _, _ in fresh })
        await s.hydrate(companyId: "u")
        await s.sendChat("re-plan then guide me", language: .en)
        XCTAssertEqual(s.company.tasks.map(\.id), ["n1"], "re_plan runs first, replacing tasks")
        XCTAssertTrue(s.chatMessages.contains { $0.role == .me && $0.text.contains("Fresh task") },
                      "walkthrough resolves against the POST-replan task set and starts the guided turn")
    }

    // MARK: - Engineering composer-pill routing (2D)

    private func storeCapturingStream(_ onStream: @escaping () -> Void) -> CompanyStore {
        let seed = CompanyState(brief: .init(), departments: [], library: [], stage: .building,
                                companionId: "byte", onboardedAt: Date(), tasks: [])
        return CompanyStore(loader: { _ in seed },
                            tasksSaver: { _, _ in true },
                            chatSender: { _ in nil },
                            chatStreamer: { _ in onStream(); return AsyncThrowingStream { c in c.yield(.delta("hi")); c.finish() } },
                            librarySaver: { _, _ in true },
                            threadSaver: { _, _ in true },
                            threadsLoader: { _ in [] })
    }

    func test_engineeringPill_withLink_stagesRun_echoesAsk_noCloudTurn() async {
        var streamed = false
        let s = storeCapturingStream { streamed = true }
        await s.hydrate(companyId: "u")
        let base = NSTemporaryDirectory() + "codepet-2d-" + UUID().uuidString
        try? FileManager.default.createDirectory(atPath: base, withIntermediateDirectories: true)
        s.linkProject(path: base, bootstrapClaudeMd: false)

        await s.sendChat("fix the bug", language: .en, department: DepartmentCatalog.find("eng"))

        XCTAssertFalse(streamed, "engineering pill + linked project → no cloud chat turn")
        XCTAssertNotNil(s.codingRun.run, "a local coding run is staged")
        XCTAssertTrue(s.chatMessages.contains { $0.role == .me && $0.text == "fix the bug" },
                      "the founder's ask is echoed into the transcript")
    }

    // The chat "Turn on" (setup verb) must enable an OFF toolkit item, and be
    // idempotent — a duplicate tap must never flip an already-on item back off.
    func test_activateSetup_enablesOffItem_andIsIdempotent() async {
        var savedTools: [[String]] = []
        let seed = CompanyState(brief: .init(), departments: [], library: [], stage: .building,
                                companionId: "byte", onboardedAt: Date(), tasks: [])
        let s = CompanyStore(loader: { _ in seed },
                             tasksSaver: { _, _ in true },
                             chatSender: { _ in nil },
                             chatStreamer: { _ in AsyncThrowingStream { c in c.finish() } },
                             librarySaver: { _, _ in true },
                             toolsSaver: { _, tools in savedTools.append(tools); return true },
                             threadSaver: { _, _ in true },
                             threadsLoader: { _ in [] })
        await s.hydrate(companyId: "u")
        let item = Toolkit.catalog.first { !s.company.enabledTools.contains($0.id) }!
        let setup = SetupAction(category: item.category.rawValue, name: item.name)

        await s.activateSetup(setup)
        XCTAssertTrue(s.company.enabledTools.contains(item.id), "Turn on must enable the off item")
        await s.activateSetup(setup)   // duplicate tap
        XCTAssertTrue(s.company.enabledTools.contains(item.id), "duplicate Turn on must NOT toggle it back off")
        XCTAssertFalse(savedTools.isEmpty, "enabling must persist via toolsSaver")
    }

    func test_engineeringPill_noLink_fallsThroughToCloud() async {
        var streamed = false
        let s = storeCapturingStream { streamed = true }
        await s.hydrate(companyId: "u")
        await s.sendChat("fix the bug", language: .en, department: DepartmentCatalog.find("eng"))
        XCTAssertTrue(streamed, "no linked project → the guard must not fire; normal cloud turn runs")
        XCTAssertNil(s.codingRun.run, "no coding run staged without a linked project")
    }
}

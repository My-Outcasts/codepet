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
}

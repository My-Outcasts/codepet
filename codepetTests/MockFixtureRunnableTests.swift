import XCTest
@testable import codepet

#if DEBUG
/// The offline fixture (`-CODEPET_MOCK_CHAT`) exists to demonstrate three surfaces with no
/// Anthropic spend: a task running in chat (execute log → draft card), the parallel
/// department fan-out (`AgentsWorkingRow`), and the specialist handoff.
///
/// All three need `codepetCanDo` work, and all three had silently stopped working: phase
/// gating landed after the fixture was written, `mock-interviews` is `who: .you` in `.find`,
/// and `RoadmapGating.openPhases` therefore shut every later phase — leaving nothing runnable
/// anywhere in the roadmap. The client sent an empty `runnable` list, the CF is given no
/// `run_task` tool for an empty list, and the mock router answered "you don't have a task I
/// can run right now" to every attempt. Reported from the app as the agents UI being broken;
/// it was the fixture.
///
/// These assertions are the guard. They fail the moment the fixture can no longer demonstrate
/// what it is for — which a comment could not do, and did not.
final class MockFixtureRunnableTests: XCTestCase {

    private var tasks: [RoadmapTask] { MockChat.company().tasks }

    private var runnable: [RoadmapTask] {
        tasks.filter { RoadmapEngine.status(for: $0, in: tasks) == .codepetCanDo }
    }

    func testFixtureHasRunnableWorkSoATaskCanActuallyRunInChat() {
        XCTAssertFalse(runnable.isEmpty,
                       "nothing is codepetCanDo — 'run the landing page' will be refused offline")
    }

    /// The fan-out takes the first runnable task per DISTINCT department, capped at
    /// `CompanyStore.maxFanOut`. Three parallel agents therefore need three departments.
    func testFixtureCanFanOutTheFullThreeAgents() {
        let moves = RoadmapEngine.nextMoves(tasks, limit: CompanyStore.maxFanOut)
        XCTAssertEqual(moves.count, CompanyStore.maxFanOut,
                       "AgentsWorkingRow needs \(CompanyStore.maxFanOut) runnable departments; got \(moves.count)")
        XCTAssertEqual(Set(moves.compactMap(\.dept)).count, moves.count, "departments must be distinct")
    }

    /// The runnable work has to sit in the OPEN phase. This is the assertion that actually
    /// encodes the bug: a fixture whose only runnable tasks were in a later phase would pass
    /// nothing at all, because the window shuts them.
    func testRunnableWorkSitsInsideTheOpenWindow() {
        let open = RoadmapGating.openPhases(tasks)
        for task in runnable {
            XCTAssertTrue(open.contains(task.phase),
                          "\(task.id) is runnable but its phase \(task.phase) is outside the open window")
        }
    }

    /// And the gating itself must survive: the founder-owned step still holds the later
    /// phases shut, because that state is the other half of what the fixture demonstrates.
    func testFounderStepStillGatesTheLaterPhases() {
        XCTAssertEqual(RoadmapGating.founderStep(in: tasks)?.id, "mock-interviews")
        let blocked = tasks.filter { RoadmapEngine.status(for: $0, in: tasks) == .blocked }
        XCTAssertFalse(blocked.isEmpty, "the whole point of the needs-you card is that it blocks something")
    }

    /// End-to-end: driving the real `fanOutNextMoves` against the fixture must put agents on
    /// screen. The four assertions above check the roadmap's shape; this one checks that the
    /// shape actually reaches `activeAgentRuns`, which is the only thing `AgentsWorkingRow`
    /// renders from. Asserted from INSIDE `taskRunner` — the moment the agents are working —
    /// because by the time the call returns the row has already been cleared.
    @MainActor
    func testFanOutPutsAgentsOnScreen() async {
        let previousPacing = (CompanyStore.execStepNanos, CompanyStore.execDoneBeatNanos)
        CompanyStore.execStepNanos = 0
        CompanyStore.execDoneBeatNanos = 0
        defer { (CompanyStore.execStepNanos, CompanyStore.execDoneBeatNanos) = previousPacing }

        var agentsOnScreen = 0
        var deptsOnScreen: Set<String> = []
        var ref: CompanyStore?
        let store = CompanyStore(
            loader: { _ in MockChat.company() }, saver: { _, _ in true }, tasksSaver: { _, _ in true },
            chatSender: { _ in nil },
            chatStreamer: { _ in AsyncThrowingStream { $0.finish(throwing: CompanyChatStreamError.notSignedIn) } },
            taskRunner: { req in
                let runs = ref?.activeAgentRuns ?? []
                agentsOnScreen = max(agentsOnScreen, runs.count)
                deptsOnScreen.formUnion(runs.map(\.deptName))
                return RunTaskResponse(kind: "doc", title: req.taskTitle, body: "# draft")
            },
            decisionExtractor: { _, _ in [] })
        ref = store
        await store.hydrate(companyId: "u")
        await store.fanOutNextMoves(language: .en)

        XCTAssertEqual(agentsOnScreen, CompanyStore.maxFanOut,
                       "AgentsWorkingRow had \(agentsOnScreen) agents to draw, expected \(CompanyStore.maxFanOut)")
        XCTAssertEqual(deptsOnScreen.count, CompanyStore.maxFanOut, "each agent must name its own department")
        XCTAssertTrue(store.activeAgentRuns.isEmpty, "the row must clear when the fan-out finishes")
        XCTAssertFalse(store.chatMessages.filter { $0.draft != nil }.isEmpty, "each agent should land a draft")
    }

    /// Every runnable task's title must carry the keyword the mock router matches, or typing
    /// "run <keyword>" silently falls through to the first task in the list instead.
    func testEachRunnableTaskIsReachableByItsKeyword() {
        for task in runnable {
            let words = task.title.lowercased().split(whereSeparator: { !$0.isLetter })
            XCTAssertTrue(words.contains { $0.count >= 4 },
                          "\(task.id) has no 4+ letter word for the router to match: \(task.title)")
        }
    }
}
#endif

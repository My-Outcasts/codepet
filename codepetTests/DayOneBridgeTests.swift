// codepetTests/DayOneBridgeTests.swift
import XCTest
@testable import codepet

/// **The claim this whole change exists to make.** Run the nine questions on day one and you
/// arrive at the board the 24-beat tour walks — same tasks done, same artifacts filed, same
/// beacon. If this drifts, the two demos are telling different stories about one company.
@MainActor
final class DayOneBridgeTests: XCTestCase {

    /// What each run was actually TOLD to build on, captured off the request.
    private var upstreamSeen: [String: [UpstreamWork]] = [:]

    /// Seeded through `loader` + `hydrate`, because `company` is `private(set)`.
    ///
    /// `decisionExtractor` is not politeness: `fileApproval` spawns a fire-and-forget
    /// `rememberFromApproval` whose default `DecisionsClient.extract` calls `Auth.auth()` and
    /// TRAPS with no `FirebaseApp`. It takes down a LATER test, so the symptom is a zero
    /// executed-count somewhere else entirely. Argument order is fixed by the declaration:
    /// `firstApprovalSaver` comes before `decisionsSaver`.
    private func dayOneStore() async -> CompanyStore {
        let project = DemoProject.murrorDayOne
        let seed = CompanyState(brief: project.brief, departments: [], library: project.library(),
                                stage: .building, companionId: "byte", onboardedAt: Date(),
                                tasks: project.tasks)
        let store = CompanyStore(
            loader: { _ in seed },
            tasksSaver: { _, _ in true },
            // The real run path, answering with the fixture's own authored artifact — so the
            // request this receives was built by `runRequest`/`assemble` for real.
            //
            // NOTE: `taskRunner` must precede `librarySaver` here — Swift requires labeled
            // arguments in the callee's declaration order, not merely each by name, and
            // `CompanyStore.init` declares `taskRunner` before `librarySaver`.
            taskRunner: { req in
                self.upstreamSeen[req.taskId] = req.upstream ?? []
                let entry = project.deliverable(for: req.taskTitle)
                return RunTaskResponse(kind: entry.kind, title: req.taskTitle,
                                       body: MockChat.fill(entry.body, title: req.taskTitle))
            },
            librarySaver: { _, _ in true },
            firstApprovalSaver: { _, _ in true },
            decisionsSaver: { _, _ in true },
            decisionExtractor: { _, _ in [] })
        await store.hydrate(companyId: "u")
        return store
    }

    /// Walk the chain the way the script does: record link 1 (founder-only), then RUN and
    /// APPROVE each next link through the store's own API. No `.draft` poking — `company` is
    /// `private(set)`, and driving the real path is what makes this a bridge test at all.
    private func runTheNineQuestions(_ store: CompanyStore) async {
        let project = DemoProject.murrorDayOne
        for id in DemoProject.dayOneChain {
            guard let task = store.company.tasks.first(where: { $0.id == id }) else {
                XCTFail("\(id) missing from the day-one board"); return
            }
            if task.who == .you {
                let entry = project.deliverable(for: task.title)
                await store.recordFounderOutcome(
                    taskId: id, body: MockChat.fill(entry.body, title: task.title), kind: .doc)
            } else {
                await store.runTask(task, language: .en)
                await store.approveTask(id: id)
            }
        }
    }

    func testRunningTheNineLandsOnMidFlight() async {
        let store = await dayOneStore()
        await runTheNineQuestions(store)

        let doneIds = Set(store.company.tasks.filter(\.done).map(\.id))
        XCTAssertEqual(doneIds, Set(DemoProject.murror.filed),
                       "the nine done tasks must be mid-flight's nine filed tasks")

        let filedIds = Set(store.company.library.compactMap(\.sourceTaskId))
        XCTAssertEqual(filedIds, Set(DemoProject.murror.filed),
                       "and every one of them left an artifact behind")
        XCTAssertEqual(store.company.library.count, 9)
    }

    /// The hand-off to the tour. After the nine, the beacon is where the tour's `.runBeacon`
    /// starts — which is what makes the two demos one continuous story.
    func testTheBeaconThenPointsAtTheLandingPage() async {
        let store = await dayOneStore()
        await runTheNineQuestions(store)
        XCTAssertEqual(RoadmapEngine.nextStep(store.company.tasks)?.id, "mur-site")
    }

    /// Mid-flight's headline claim has to survive being ARRIVED at, not just declared.
    func testTheResultingBoardHasEightRunnableTasks() async {
        let store = await dayOneStore()
        await runTheNineQuestions(store)
        let tasks = store.company.tasks
        let runnable = tasks.filter { RoadmapEngine.status(for: $0, in: tasks) == .codepetCanDo }
        XCTAssertEqual(runnable.count, 8)
        XCTAssertEqual(Set(runnable.compactMap(\.dept)), Set(DepartmentCatalog.roster.map(\.key)))
    }

    /// **The hand-off, at the mechanism rather than the caption.**
    ///
    /// Asserted on what each run was HANDED, not on the end state. After all nine are filed,
    /// `assemble` would find work for everything — so an after-the-fact check would pass even
    /// if every run had been given nothing at the moment it ran.
    func testEachRunWasHandedItsPredecessorsWork() async {
        let store = await dayOneStore()
        await runTheNineQuestions(store)

        // Link 1 is recorded, not run, so the eight runs are links 2-9.
        XCTAssertEqual(upstreamSeen.count, 8, "eight runs should have been made")
        for (i, id) in DemoProject.dayOneChain.enumerated() where i > 0 {
            let carried = upstreamSeen[id] ?? []
            XCTAssertFalse(carried.isEmpty,
                           "\(id) ran with no upstream — its card would credit nobody")
        }
    }

    /// Link 1 is the founder's own work, and link 2 must still be able to read it. This is the
    /// hand-off `recordFounderOutcome` exists to make possible.
    func testTheSecondLinkWasHandedTheFoundersOwnInterviews() async {
        let store = await dayOneStore()
        await runTheNineQuestions(store)
        let carried = upstreamSeen["mur-landscape"] ?? []
        XCTAssertTrue(carried.contains { $0.taskTitle.contains("12 people") },
                      "link 2 must credit the interviews the founder ran herself")
    }
}

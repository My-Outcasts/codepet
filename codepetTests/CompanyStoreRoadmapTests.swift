// codepetTests/CompanyStoreRoadmapTests.swift
import XCTest
@testable import codepet

@MainActor
final class CompanyStoreRoadmapTests: XCTestCase {
    private func task(_ id: String, done: Bool = false) -> RoadmapTask {
        RoadmapTask(id: id, title: id, detail: "", phase: .build, who: .does, done: done)
    }

    func testGeneratePersistsFetchedTasks() async {
        var saved: [RoadmapTask] = []
        let s = CompanyStore(loader: { _ in .empty }, saver: { _, _ in true },
                             roadmapFetcher: { _, _ in [self.task("t1")] },
                             tasksSaver: { _, ts in saved = ts; return true })
        await s.hydrate(companyId: "u")
        await s.generateRoadmap()
        XCTAssertEqual(s.company.tasks.map(\.id), ["t1"])
        XCTAssertEqual(saved.map(\.id), ["t1"])
    }
    func testGenerateFailOpenKeepsExisting() async {
        var saveCount = 0
        let seeded = CompanyState(brief: CompanyBrief(), departments: [], library: [], stage: .idea,
                                  companionId: "byte", onboardedAt: Date(), tasks: [task("keep")])
        let s = CompanyStore(loader: { _ in seeded }, saver: { _, _ in true },
                             roadmapFetcher: { _, _ in [] }, tasksSaver: { _, _ in saveCount += 1; return true })
        await s.hydrate(companyId: "u")
        await s.generateRoadmap()
        XCTAssertEqual(s.company.tasks.map(\.id), ["keep"])   // empty fetch → no change
        XCTAssertEqual(saveCount, 0)                          // fail-open path never persists
    }
    func testToggleTaskDoneFlipsAndPersists() async {
        var saved: [RoadmapTask] = []
        let seeded = CompanyState(brief: CompanyBrief(), departments: [], library: [], stage: .idea,
                                  companionId: "byte", onboardedAt: Date(), tasks: [task("t1")])
        let s = CompanyStore(loader: { _ in seeded }, saver: { _, _ in true },
                             roadmapFetcher: { _, _ in [] }, tasksSaver: { _, ts in saved = ts; return true })
        await s.hydrate(companyId: "u")
        await s.toggleTaskDone(id: "t1")
        XCTAssertTrue(s.company.tasks[0].done)
        XCTAssertTrue(saved.first?.done ?? false)
    }
    func testToggleAbsentIdIsNoOp() async {
        var saveCount = 0
        let seeded = CompanyState(brief: CompanyBrief(), departments: [], library: [], stage: .idea,
                                  companionId: "byte", onboardedAt: Date(), tasks: [task("t1")])
        let s = CompanyStore(loader: { _ in seeded }, saver: { _, _ in true },
                             roadmapFetcher: { _, _ in [] }, tasksSaver: { _, _ in saveCount += 1; return true })
        await s.hydrate(companyId: "u")
        await s.toggleTaskDone(id: "nope")
        XCTAssertFalse(s.company.tasks[0].done)   // untouched
        XCTAssertEqual(saveCount, 0)              // absent id → no persist
    }

    /// Every task run shows the agent working — including the ones started from a CARD.
    ///
    /// The founder's model, Aug 5: any task from any department goes through the agent-working UI.
    /// `runTask` (Start on the beacon, Run on the Tasks board, Run in a department, Run on a
    /// roadmap card) used to show nothing but a button reading "Running…"; only the chat path had
    /// an agent. Asserted from INSIDE `taskRunner`, the only moment the run is in flight.
    func testABoardRunPublishesAVisibleAgent() async {
        var seen: TaskRunProgress?
        var ref: CompanyStore?
        let s = CompanyStore(loader: { _ in
            CompanyState(brief: CompanyBrief(), departments: [], library: [], stage: .idea,
                         companionId: "glitch", onboardedAt: Date(),
                         tasks: [RoadmapTask(id: "t1", title: "Write your landing page copy",
                                             detail: "", phase: .find, who: .draft, dept: "mkt")])
        }, saver: { _, _ in true }, tasksSaver: { _, _ in true },
           chatSender: { _ in nil },
           chatStreamer: { _ in AsyncThrowingStream { $0.finish() } },
           taskRunner: { _ in
               seen = ref?.taskRuns["t1"]
               return RunTaskResponse(kind: "doc", title: "Landing copy", body: "# hi")
           },
           decisionExtractor: { _, _ in [] })
        ref = s
        await s.hydrate(companyId: "u")
        guard let task = s.company.tasks.first else { return XCTFail("no task") }
        await s.runTask(task, language: .en)

        XCTAssertNotNil(seen, "a board run published no agent at all")
        XCTAssertFalse(seen?.steps.isEmpty ?? true)
        XCTAssertEqual(seen?.deptName, "Marketing")
        XCTAssertEqual(seen?.companionId, "nova", "the run must carry the DEPARTMENT's pet")
        XCTAssertTrue(s.taskRuns.isEmpty, "the strip must clear when the run ends")
    }

    /// The department's character shows even when it happens to BE the founder's companion.
    /// `taskSpecialist` used to return nil in that case, so with Glitch chosen every ops and
    /// legal run lost its character — Glitch is this map's ops/legal specialist.
    func testTheDepartmentsPetShowsEvenWhenItIsAlsoTheHostCompanion() async {
        var seen: TaskRunProgress?
        var ref: CompanyStore?
        let s = CompanyStore(loader: { _ in
            CompanyState(brief: CompanyBrief(), departments: [], library: [], stage: .idea,
                         companionId: "glitch", onboardedAt: Date(),
                         tasks: [RoadmapTask(id: "ops1", title: "Set up a deploy checklist",
                                             detail: "", phase: .find, who: .draft, dept: "ops")])
        }, saver: { _, _ in true }, tasksSaver: { _, _ in true },
           chatSender: { _ in nil },
           chatStreamer: { _ in AsyncThrowingStream { $0.finish() } },
           taskRunner: { _ in
               seen = ref?.taskRuns["ops1"]
               return RunTaskResponse(kind: "doc", title: "Checklist", body: "# hi")
           },
           decisionExtractor: { _, _ in [] })
        ref = s
        await s.hydrate(companyId: "u")
        guard let task = s.company.tasks.first else { return XCTFail("no task") }
        await s.runTask(task, language: .en)
        XCTAssertEqual(seen?.companionId, "glitch")
        XCTAssertEqual(seen?.deptName, "Operations")
    }

    /// A failed run must not leave a strip claiming an agent is still working.
    func testAFailedBoardRunClearsTheAgent() async {
        let s = CompanyStore(loader: { _ in
            CompanyState(brief: CompanyBrief(), departments: [], library: [], stage: .idea,
                         companionId: "byte", onboardedAt: Date(),
                         tasks: [RoadmapTask(id: "t1", title: "Draft a support FAQ", detail: "",
                                             phase: .find, who: .draft, dept: "support")])
        }, saver: { _, _ in true }, tasksSaver: { _, _ in true },
           chatSender: { _ in nil },
           chatStreamer: { _ in AsyncThrowingStream { $0.finish() } },
           taskRunner: { _ in nil },
           decisionExtractor: { _, _ in [] })
        await s.hydrate(companyId: "u")
        guard let task = s.company.tasks.first else { return XCTFail("no task") }
        await s.runTask(task, language: .en)
        XCTAssertTrue(s.taskRuns.isEmpty)
        XCTAssertNotNil(s.runError)
    }

}

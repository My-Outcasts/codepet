// codepetTests/FounderOutcomeTests.swift
import XCTest
@testable import codepet

/// Completing a task Codepet cannot run must still leave an artifact behind.
///
/// `toggleTaskDone` marks such a task done and files NOTHING, and `approveTask` needs a draft
/// that no founder-only path ever sets. So "talk to 12 people" could be finished and the
/// dependency arrow pointing at it still read as unproduced — which is what
/// `UpstreamWork.firstUnfiled` documents as the case worth chaining.
@MainActor
final class FounderOutcomeTests: XCTestCase {

    /// Savers are injected because a `CompanyStore` reaching Firestore with no `FirebaseApp`
    /// TRAPS — it does not throw — and takes the whole test host with it.
    ///
    /// `company` is `private(set)`, so seeding it goes through the same `loader` + `hydrate`
    /// path every other CompanyStore suite uses (see `CompanyStoreRunTaskTests`), not a
    /// direct assignment from outside the file.
    ///
    /// `decisionExtractor` is injected too: `fileApproval` fires `rememberFromApproval` as an
    /// unstructured `Task`, whose default `DecisionsClient.extract` calls `Auth.auth()` — same
    /// trap as Firestore, hit here because `recordFounderOutcome` goes through `approveTask`.
    /// `FirstApprovalNoteTests` and `ApprovalParityTests` inject it for the same reason.
    private func makeStore(tasks: [RoadmapTask]) async -> CompanyStore {
        let seed = CompanyState(brief: .init(), departments: [], library: [], stage: .building,
                                companionId: "byte", onboardedAt: Date(), tasks: tasks)
        let store = CompanyStore(
            loader: { _ in seed },
            tasksSaver: { _, _ in true },
            librarySaver: { _, _ in true },
            firstApprovalSaver: { _, _ in true },
            decisionsSaver: { _, _ in true },
            decisionExtractor: { _, _ in [] })
        await store.hydrate(companyId: "u")
        return store
    }

    private func founderTask(id: String = "t-you", done: Bool = false) -> RoadmapTask {
        RoadmapTask(id: id, title: "Talk to 12 people about being lonely",
                    detail: "", phase: .find, who: .you, done: done, dept: "mkt")
    }

    func testRecordingFilesADeliverableAndMarksTheTaskDone() async {
        let store = await makeStore(tasks: [founderTask()])
        await store.recordFounderOutcome(taskId: "t-you", body: "Nine of twelve said the same thing.",
                                         kind: .doc)
        XCTAssertEqual(store.company.library.count, 1)
        let filed = store.company.library.first
        XCTAssertEqual(filed?.sourceTaskId, "t-you")
        XCTAssertEqual(filed?.title, "Talk to 12 people about being lonely")
        XCTAssertEqual(filed?.body, "Nine of twelve said the same thing.")
        XCTAssertTrue(store.company.tasks[0].done, "recording is what completes it")
    }

    /// A `.you` task carrying a prepared draft awaiting approval must not be silently
    /// overwritten. `BeaconOffer` documents that a founder-only task can hold such a draft —
    /// recording over it here would clobber it with a different body instead of asking the
    /// founder to approve or discard what is already waiting.
    func testItRefusesADraftedTask() async {
        var task = founderTask(id: "t-drafted")
        task.drafted = true
        task.draft = Deliverable(kind: .doc, title: task.title, body: "already waiting",
                                 sourceTaskId: "t-drafted")
        let store = await makeStore(tasks: [task])
        await store.recordFounderOutcome(taskId: "t-drafted", body: "clobbering body", kind: .doc)
        XCTAssertTrue(store.company.library.isEmpty, "a drafted task must not be filed this way")
        XCTAssertFalse(store.company.tasks[0].done)
        XCTAssertEqual(store.company.tasks[0].draft?.body, "already waiting",
                       "the prepared draft must survive untouched")
    }

    /// Codepet's own tasks have a run path that already files. Routing them through here too
    /// would give one task two ways to be completed and two artifacts.
    func testItRefusesATaskCodepetCanRun() async {
        let codepetTask = RoadmapTask(id: "t-run", title: "Ship an email capture", detail: "",
                                      phase: .build, who: .draft, done: false, dept: "eng")
        let store = await makeStore(tasks: [codepetTask])
        await store.recordFounderOutcome(taskId: "t-run", body: "b", kind: .doc)
        XCTAssertTrue(store.company.library.isEmpty, "only `.you` tasks are recorded this way")
        XCTAssertFalse(store.company.tasks[0].done)
    }

    /// Pressing it twice must not file the same work twice — the same double-file hazard
    /// `fileApproval` guards with its `done` check.
    func testRecordingTwiceFilesOnce() async {
        let store = await makeStore(tasks: [founderTask()])
        await store.recordFounderOutcome(taskId: "t-you", body: "b", kind: .doc)
        await store.recordFounderOutcome(taskId: "t-you", body: "b again", kind: .doc)
        XCTAssertEqual(store.company.library.count, 1)
    }
}

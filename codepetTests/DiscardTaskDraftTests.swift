// codepetTests/DiscardTaskDraftTests.swift
import XCTest
@testable import codepet

/// Throwing a draft away. Found testing as a non-technical founder (5 Oct): the companion said
/// a draft was waiting to "approve or reject", and there was nothing to reject it with — the
/// only ways out of a bad draft were approving it or revising it forever.
@MainActor
final class DiscardTaskDraftTests: XCTestCase {
    private func drafted(_ id: String = "t1") -> RoadmapTask {
        RoadmapTask(id: id, title: "T", detail: "", phase: .find, who: .does, drafted: true,
                    draft: Deliverable(kind: .doc, title: "D", body: "body", sourceTaskId: id))
    }
    private func seed(_ tasks: [RoadmapTask]) -> CompanyState {
        CompanyState(brief: .init(), departments: [], library: [], stage: .building,
                     companionId: "byte", onboardedAt: Date(), tasks: tasks)
    }

    func testDiscardClearsTheDraftAndReopensTheTask() async {
        var savedTasks: [RoadmapTask]?
        var librarySaves = 0
        let s = CompanyStore(loader: { [seed] _ in seed([self.drafted()]) },
                             tasksSaver: { _, t in savedTasks = t; return true },
                             librarySaver: { _, _ in librarySaves += 1; return true })
        await s.hydrate(companyId: "u")
        await s.discardTaskDraft(id: "t1")
        let t = s.company.tasks[0]
        XCTAssertFalse(t.drafted)
        XCTAssertNil(t.draft)
        XCTAssertFalse(t.done)                              // back to runnable, not completed
        XCTAssertEqual(RoadmapEngine.status(for: t, in: s.company.tasks), .codepetCanDo)
        XCTAssertTrue(s.company.library.isEmpty)            // nothing filed
        XCTAssertEqual(librarySaves, 0)
        XCTAssertEqual(savedTasks?.first?.drafted, false)   // persisted
    }

    func testDiscardIsANoOpWithoutADraft() async {
        var saves = 0
        let plain = RoadmapTask(id: "t1", title: "T", detail: "", phase: .find, who: .does)
        let s = CompanyStore(loader: { [seed] _ in seed([plain]) },
                             tasksSaver: { _, _ in saves += 1; return true })
        await s.hydrate(companyId: "u")
        await s.discardTaskDraft(id: "t1")
        XCTAssertEqual(saves, 0)
    }

    /// A done task keeps whatever it has — discard is for drafts awaiting approval only.
    func testDiscardLeavesADoneTaskAlone() async {
        var t = drafted(); t.done = true
        var saves = 0
        let s = CompanyStore(loader: { [seed] _ in seed([t]) },
                             tasksSaver: { _, _ in saves += 1; return true })
        await s.hydrate(companyId: "u")
        await s.discardTaskDraft(id: "t1")
        XCTAssertEqual(saves, 0)
        XCTAssertTrue(s.company.tasks[0].done)
    }
}

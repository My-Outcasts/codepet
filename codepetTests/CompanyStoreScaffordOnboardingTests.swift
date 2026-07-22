// codepetTests/CompanyStoreScaffordOnboardingTests.swift
import XCTest
@testable import codepet

@MainActor
final class CompanyStoreScaffordOnboardingTests: XCTestCase {
    private func task(_ id: String) -> RoadmapTask {
        RoadmapTask(id: id, title: "Task " + id, detail: "", phase: .build, who: .does)
    }

    func testPersistsBriefScaffoldsAndReturnsRevealWithoutLeavingOnboarding() async {
        var savedBrief: CompanyBrief?
        let s = CompanyStore(
            loader: { _ in .empty },
            saver: { _, b in savedBrief = b; return true },
            roadmapFetcher: { _ in [self.task("a"), self.task("b")] },
            tasksSaver: { _, _ in true }   // stub the tasks write (real CompanyData.saveTasks crashes the test host)
        )
        await s.hydrate(companyId: "u")     // fresh account ⇒ isOnboarding true
        XCTAssertTrue(s.isOnboarding)
        let brief = CompanyBrief(projectName: "Codepet", oneLiner: "run your company with AI")
        let reveal = await s.scaffoldFromOnboarding(brief: brief, token: s.onboardingToken)
        XCTAssertEqual(savedBrief?.projectName, "Codepet")   // brief persisted
        XCTAssertEqual(s.company.brief.projectName, "Codepet")
        XCTAssertEqual(s.company.tasks.count, 2)              // roadmap scaffolded
        XCTAssertTrue(reveal.ok)
        XCTAssertEqual(reveal.taskCount, 2)
        XCTAssertEqual(reveal.sampleTasks, ["Task a", "Task b"])
        XCTAssertTrue(s.isOnboarding)                        // still in the wizard (reveal shows next)
    }

    func testEmptyScaffoldReturnsNotOk() async {
        let s = CompanyStore(loader: { _ in .empty }, saver: { _, _ in true },
                             roadmapFetcher: { _ in [] })     // fail-open: no tasks
        await s.hydrate(companyId: "u")
        let reveal = await s.scaffoldFromOnboarding(brief: CompanyBrief(projectName: "X"), token: s.onboardingToken)
        XCTAssertFalse(reveal.ok)
        XCTAssertEqual(reveal.taskCount, 0)
        XCTAssertTrue(s.company.tasks.isEmpty)
    }

    func testStaleTokenAfterSwitchDiscards() async {
        var savedTo: [String] = []
        let s = CompanyStore(loader: { _ in .empty },
                             saver: { cid, _ in savedTo.append(cid); return true },
                             roadmapFetcher: { _ in [self.task("a")] })
        await s.hydrate(companyId: "A")
        let aToken = s.onboardingToken
        s.reset()
        await s.hydrate(companyId: "B")
        let reveal = await s.scaffoldFromOnboarding(brief: CompanyBrief(projectName: "A-Co"), token: aToken)
        XCTAssertEqual(reveal, OnboardingReveal.empty)       // discarded
        XCTAssertFalse(savedTo.contains("A"))                // A's brief not written after switch
        XCTAssertEqual(s.company.brief.projectName, nil)     // B (empty) not clobbered
    }
}

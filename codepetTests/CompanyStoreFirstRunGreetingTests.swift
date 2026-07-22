import XCTest
@testable import codepet

@MainActor
final class CompanyStoreFirstRunGreetingTests: XCTestCase {
    private func seeded(tasks: [RoadmapTask], brief: CompanyBrief) -> CompanyState {
        CompanyState(brief: brief, departments: [], library: [], stage: .idea,
                     companionId: "byte", onboardedAt: nil, tasks: tasks)
    }

    func testFinishSeedsGreetingWithActionFromNextStep() async {
        let t = RoadmapTask(id: "t1", title: "Write your landing page", detail: "", phase: .find, who: .does)
        let state = seeded(tasks: [t], brief: CompanyBrief(founderName: "Mona", projectName: "Codepet"))
        let s = CompanyStore(loader: { _ in state }, saver: { _, _ in true })
        await s.hydrate(companyId: "u")
        await s.finishOnboarding(brief: state.brief, token: s.onboardingToken, language: .en)
        XCTAssertEqual(s.chatMessages.count, 1)
        let m = s.chatMessages[0]
        XCTAssertEqual(m.role, .companion)
        XCTAssertTrue(m.text.contains("Write your landing page"))
        XCTAssertEqual(m.firstRunAction?.taskId, "t1")
        XCTAssertFalse(m.actionConsumed)
    }

    func testFinishWithNoTasksSeedsGreetingWithoutAction() async {
        let state = seeded(tasks: [], brief: CompanyBrief(founderName: "Mona", projectName: "Codepet"))
        let s = CompanyStore(loader: { _ in state }, saver: { _, _ in true })
        await s.hydrate(companyId: "u")
        await s.finishOnboarding(brief: state.brief, token: s.onboardingToken, language: .en)
        XCTAssertEqual(s.chatMessages.count, 1)
        XCTAssertNil(s.chatMessages[0].firstRunAction)
    }
}

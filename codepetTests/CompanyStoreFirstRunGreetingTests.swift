import XCTest
@testable import codepet

@MainActor
final class CompanyStoreFirstRunGreetingTests: XCTestCase {
    private func seeded(tasks: [RoadmapTask], brief: CompanyBrief) -> CompanyState {
        CompanyState(brief: brief, departments: [], library: [], stage: .idea,
                     companionId: "byte", onboardedAt: nil, tasks: tasks)
    }

    /// A brief with no enrichment gaps (see `EnrichInterview.detectGaps`).
    private func completeBrief() -> CompanyBrief {
        CompanyBrief(founderName: "Mona", projectName: "Codepet",
                     goal: "Ship v1", traction: "None yet", problem: "Founders lose context")
    }

    /// New first-run contract: `finishOnboarding` seeds nothing into
    /// `chatMessages` — the dock renders the landing hero (ChatEmptyState +
    /// starter cards), not a companion greeting. Holds for a full brief
    /// (previously: seeded greeting directly).
    func testFullBriefFinishOpensEmptyForLandingHero() async {
        let t = RoadmapTask(id: "t1", title: "Write your landing page", detail: "", phase: .find, who: .does)
        let state = seeded(tasks: [t], brief: completeBrief())
        let s = CompanyStore(loader: { _ in state }, saver: { _, _ in true })
        await s.hydrate(companyId: "u")
        await s.finishOnboarding(brief: state.brief, token: s.onboardingToken, language: .en)
        XCTAssertTrue(s.chatMessages.isEmpty)
    }

    /// Same contract for a sparse brief with enrichment gaps (previously:
    /// auto-started the interview instead of the greeting). The interview must
    /// NOT auto-start either — no message carries an `.interview` gap.
    func testSparseBriefOpensEmptyForLandingHero() async {
        let t = RoadmapTask(id: "t1", title: "Write your landing page", detail: "", phase: .find, who: .does)
        let sparse = CompanyBrief(founderName: "Mona", projectName: "Codepet")
        let state = seeded(tasks: [t], brief: sparse)
        let s = CompanyStore(loader: { _ in state }, saver: { _, _ in true })
        await s.hydrate(companyId: "u")
        await s.finishOnboarding(brief: sparse, token: s.onboardingToken, language: .en)
        XCTAssertTrue(s.chatMessages.isEmpty)
        XCTAssertFalse(s.chatMessages.contains { $0.interview != nil })
    }
}

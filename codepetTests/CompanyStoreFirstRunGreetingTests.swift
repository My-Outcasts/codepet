import XCTest
@testable import codepet

@MainActor
final class CompanyStoreFirstRunGreetingTests: XCTestCase {
    private func seeded(tasks: [RoadmapTask], brief: CompanyBrief) -> CompanyState {
        CompanyState(brief: brief, departments: [], library: [], stage: .idea,
                     companionId: "byte", onboardedAt: nil, tasks: tasks)
    }

    /// A brief with no enrichment gaps, so `finishOnboarding` seeds the greeting
    /// directly instead of starting the interview.
    private func completeBrief() -> CompanyBrief {
        CompanyBrief(founderName: "Mona", projectName: "Codepet",
                     goal: "Ship v1", traction: "None yet", problem: "Founders lose context")
    }

    func testFinishSeedsGreetingWithActionFromNextStep() async {
        let t = RoadmapTask(id: "t1", title: "Write your landing page", detail: "", phase: .find, who: .does)
        let state = seeded(tasks: [t], brief: completeBrief())
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
        let state = seeded(tasks: [], brief: completeBrief())
        let s = CompanyStore(loader: { _ in state }, saver: { _, _ in true })
        await s.hydrate(companyId: "u")
        await s.finishOnboarding(brief: state.brief, token: s.onboardingToken, language: .en)
        XCTAssertEqual(s.chatMessages.count, 1)
        XCTAssertNil(s.chatMessages[0].firstRunAction)
    }

    func testRunFirstRunActionAppendsDraftAndConsumes() async {
        let t = RoadmapTask(id: "t1", title: "Landing page", detail: "d", phase: .find, who: .does)
        let state = seeded(tasks: [t], brief: completeBrief())
        let s = CompanyStore(loader: { _ in state }, saver: { _, _ in true },
                             taskRunner: { _ in RunTaskResponse(kind: "doc", title: "Landing page", body: "# Hello") })
        await s.hydrate(companyId: "u")
        await s.finishOnboarding(brief: state.brief, token: s.onboardingToken, language: .en)
        let greetingId = s.chatMessages[0].id
        await s.runFirstRunAction(messageId: greetingId, language: .en)
        XCTAssertTrue(s.chatMessages[0].actionConsumed)
        XCTAssertEqual(s.chatMessages.count, 2)
        XCTAssertEqual(s.chatMessages[1].draft?.body, "# Hello")
    }

    func testRunFirstRunActionIsIdempotentOnceConsumed() async {
        let t = RoadmapTask(id: "t1", title: "Landing page", detail: "d", phase: .find, who: .does)
        let state = seeded(tasks: [t], brief: completeBrief())
        let s = CompanyStore(loader: { _ in state }, saver: { _, _ in true },
                             taskRunner: { _ in RunTaskResponse(kind: "doc", title: "x", body: "# y") })
        await s.hydrate(companyId: "u")
        await s.finishOnboarding(brief: state.brief, token: s.onboardingToken, language: .en)
        let id = s.chatMessages[0].id
        await s.runFirstRunAction(messageId: id, language: .en)
        await s.runFirstRunAction(messageId: id, language: .en)   // second call is a no-op
        XCTAssertEqual(s.chatMessages.count, 2)                    // greeting + one draft only
    }

    func testRunFirstRunActionFailOpenRestoresActionAndAppendsMessage() async {
        let t = RoadmapTask(id: "t1", title: "Landing page", detail: "d", phase: .find, who: .does)
        let state = seeded(tasks: [t], brief: completeBrief())
        let s = CompanyStore(loader: { _ in state }, saver: { _, _ in true },
                             taskRunner: { _ in nil })
        await s.hydrate(companyId: "u")
        await s.finishOnboarding(brief: state.brief, token: s.onboardingToken, language: .en)
        let id = s.chatMessages[0].id
        await s.runFirstRunAction(messageId: id, language: .en)
        XCTAssertFalse(s.chatMessages[0].actionConsumed)   // button restored
        XCTAssertEqual(s.chatMessages.count, 2)            // greeting + honest fail-open message
        XCTAssertNil(s.chatMessages[1].draft)
    }

    func testSparseBriefStartsInterviewInsteadOfGreeting() async {
        let t = RoadmapTask(id: "t1", title: "Write your landing page", detail: "", phase: .find, who: .does)
        let sparse = CompanyBrief(founderName: "Mona", projectName: "Codepet")
        let state = seeded(tasks: [t], brief: sparse)
        let s = CompanyStore(loader: { _ in state }, saver: { _, _ in true })
        await s.hydrate(companyId: "u")
        await s.finishOnboarding(brief: sparse, token: s.onboardingToken, language: .en)
        XCTAssertEqual(s.chatMessages.count, 1)
        XCTAssertEqual(s.chatMessages[0].interview, .goal)
        XCTAssertNil(s.chatMessages[0].firstRunAction, "greeting must wait for the interview")
    }

    func testGreetingSeededAfterFinalInterviewGapAnswered() async {
        let t = RoadmapTask(id: "t1", title: "Write your landing page", detail: "", phase: .find, who: .does)
        let sparse = CompanyBrief(founderName: "Mona", projectName: "Codepet")
        let state = seeded(tasks: [t], brief: sparse)
        let s = CompanyStore(loader: { _ in state }, saver: { _, _ in true })
        await s.hydrate(companyId: "u")
        await s.finishOnboarding(brief: sparse, token: s.onboardingToken, language: .en)

        for (gap, answer) in [(InterviewGap.goal, "Ship v1"),
                              (.traction, "None yet"),
                              (.problem, "Founders lose context")] {
            guard let q = s.chatMessages.last(where: { $0.interview == gap }) else {
                return XCTFail("expected a question for \(gap)")
            }
            await s.answerInterview(messageId: q.id, gap: gap, answer: answer, language: .en)
        }

        guard let greeting = s.chatMessages.last else { return XCTFail("no messages") }
        XCTAssertEqual(greeting.role, .companion)
        XCTAssertEqual(greeting.firstRunAction?.taskId, "t1")
        XCTAssertTrue(greeting.text.contains("Write your landing page"))
    }
}

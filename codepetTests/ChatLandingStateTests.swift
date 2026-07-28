import XCTest
@testable import codepet

final class ChatLandingStateTests: XCTestCase {
    private func date(hour: Int) -> Date {
        var c = DateComponents(); c.year = 2026; c.month = 7; c.day = 28; c.hour = hour; c.minute = 0
        return Calendar.current.date(from: c)!
    }
    private func company(founder: String? = "Mona", project: String? = "Acme",
                         tasks: [RoadmapTask] = []) -> CompanyState {
        var b = CompanyBrief(); b.founderName = founder; b.projectName = project
        var c = CompanyState.empty; c.brief = b; c.tasks = tasks
        return c
    }

    /// A small fixture spanning: one done task, one drafted (→ needsApproval),
    /// one who==.you not-done (→ needsYou), and one codepetCanDo task — enough
    /// to exercise beacon selection + both counts.
    private func fixtureTasks() -> [RoadmapTask] {
        [
            RoadmapTask(id: "t1", title: "Set up repo", detail: "", phase: .find, who: .does, done: true),
            RoadmapTask(id: "t2", title: "Draft brand brief", detail: "", phase: .foundation, who: .draft, drafted: true),
            RoadmapTask(id: "t3", title: "Pick a name", detail: "", phase: .foundation, who: .you),
            RoadmapTask(id: "t4", title: "Write landing copy", detail: "", phase: .build, who: .does),
        ]
    }

    func testGreetingHourBoundaries() {
        XCTAssertTrue(ChatLandingState(company: company(), now: date(hour: 11), language: .en).greeting.hasPrefix("Good morning"))
        XCTAssertTrue(ChatLandingState(company: company(), now: date(hour: 12), language: .en).greeting.hasPrefix("Good afternoon"))
        XCTAssertTrue(ChatLandingState(company: company(), now: date(hour: 17), language: .en).greeting.hasPrefix("Good afternoon"))
        XCTAssertTrue(ChatLandingState(company: company(), now: date(hour: 18), language: .en).greeting.hasPrefix("Good evening"))
    }
    func testGreetingFounderNameAndFallback() {
        XCTAssertEqual(ChatLandingState(company: company(founder: "Mona"), now: date(hour: 9), language: .en).greeting, "Good morning, Mona.")
        XCTAssertEqual(ChatLandingState(company: company(founder: "  "), now: date(hour: 9), language: .en).greeting, "Good morning, there.")
        XCTAssertEqual(ChatLandingState(company: company(founder: nil), now: date(hour: 9), language: .vi).greeting, "Chào buổi sáng, bạn.")
    }
    func testQuestionUsesProjectWithFallback() {
        XCTAssertTrue(ChatLandingState(company: company(project: "Acme"), now: date(hour: 9), language: .en).question.contains("Acme"))
        XCTAssertTrue(ChatLandingState(company: company(project: " "), now: date(hour: 9), language: .en).question.contains("Codepet"))
    }
    func testBeaconCountsAndEmpty() {
        XCTAssertTrue(ChatLandingState(company: company(tasks: []), now: date(hour: 9), language: .en).isEmpty)
        let tasks = fixtureTasks()
        let s = ChatLandingState(company: company(tasks: tasks), now: date(hour: 9), language: .en)
        XCTAssertEqual(s.beacon?.id, RoadmapEngine.nextStep(tasks)?.id)
        XCTAssertEqual(s.awaitingApprovalCount, tasks.filter { RoadmapEngine.status(for: $0, in: tasks) == .needsApproval }.count)
        XCTAssertEqual(s.needsYouCount, tasks.filter { RoadmapEngine.status(for: $0, in: tasks) == .needsYou && $0.id != s.beacon?.id }.count)
        XCTAssertFalse(s.isEmpty)
    }
}

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

    /// A small fixture spanning: one done task, one who==.you not-done at the
    /// EARLIEST phase/position (→ this is the beacon, status .needsYou), one
    /// drafted task (→ needsApproval), and a SECOND independent who==.you task
    /// (→ needsYou, but not the beacon). This deliberately makes the beacon
    /// itself a .needsYou task so `needsYouCount`'s "exclude the beacon's id"
    /// clause is actually exercised: without it, needsYouCount would double
    /// count the beacon instead of reporting just the other needsYou task.
    // ChatLandingStateTests.fixtureTasks() — t4 must stay a second `needsYou` task, so it
    // belongs in the SAME phase as the beacon rather than a later, now-locked one.
    private func fixtureTasks() -> [RoadmapTask] {
        [
            RoadmapTask(id: "t1", title: "Set up repo", detail: "", phase: .find, who: .does, done: true),
            RoadmapTask(id: "t2", title: "Pick a name", detail: "", phase: .foundation, who: .you),
            RoadmapTask(id: "t3", title: "Draft brand brief", detail: "", phase: .foundation, who: .draft, drafted: true),
            RoadmapTask(id: "t4", title: "Write landing copy", detail: "", phase: .foundation, who: .you),
        ]
    }

    func testGreetingHourBoundaries() {
        XCTAssertTrue(ChatLandingState(company: company(), now: date(hour: 11), language: .en).greeting.hasPrefix("Good morning"))
        XCTAssertTrue(ChatLandingState(company: company(), now: date(hour: 12), language: .en).greeting.hasPrefix("Good afternoon"))
        XCTAssertTrue(ChatLandingState(company: company(), now: date(hour: 17), language: .en).greeting.hasPrefix("Good afternoon"))
        XCTAssertTrue(ChatLandingState(company: company(), now: date(hour: 18), language: .en).greeting.hasPrefix("Good evening"))
    }
    /// The fallback CHANGED, deliberately: a missing name now drops the clause
    /// instead of substituting one ("Good morning." not "Good morning, there.").
    /// Two surfaces were inventing different placeholders for the same unknown
    /// founder — the rail said "Founder" beside a hero saying "there" — and
    /// `herePhrase`/`FirstRunGreetingBuilder` already rewrote rather than
    /// substituted. See `FounderName`.
    ///
    /// What this test has always been for is unchanged: an absent name must not
    /// produce a broken or half-punctuated string.
    func testGreetingFounderNameAndFallback() {
        XCTAssertEqual(ChatLandingState(company: company(founder: "Mona"), now: date(hour: 9), language: .en).greeting, "Good morning, Mona.")
        XCTAssertEqual(ChatLandingState(company: company(founder: "  "), now: date(hour: 9), language: .en).greeting, "Good morning.")
        XCTAssertEqual(ChatLandingState(company: company(founder: nil), now: date(hour: 9), language: .vi).greeting, "Chào buổi sáng.")
    }

    /// The account is the second source: the app captures Firebase's display name
    /// into `AppState.displayName`, and the greeting used to ignore it and call a
    /// signed-in founder "there".
    func testGreetingFallsBackToTheAccountNameBeforeGivingUp() {
        XCTAssertEqual(ChatLandingState(company: company(founder: nil), now: date(hour: 9),
                                        language: .en, accountName: "Mona").greeting,
                       "Good morning, Mona.")
        XCTAssertEqual(ChatLandingState(company: company(founder: "Mona"), now: date(hour: 9),
                                        language: .en, accountName: "someone@else.com").greeting,
                       "Good morning, Mona.", "the brief outranks the account")
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
        // The beacon itself must be a .needsYou task, otherwise the exclusion
        // clause below is never actually exercised.
        XCTAssertEqual(RoadmapEngine.status(for: s.beacon!, in: tasks), .needsYou)
        XCTAssertEqual(s.awaitingApprovalCount, tasks.filter { RoadmapEngine.status(for: $0, in: tasks) == .needsApproval }.count)
        let expectedNeedsYouExcludingBeacon = tasks.filter {
            RoadmapEngine.status(for: $0, in: tasks) == .needsYou && $0.id != s.beacon?.id
        }.count
        XCTAssertGreaterThanOrEqual(expectedNeedsYouExcludingBeacon, 1)
        XCTAssertEqual(s.needsYouCount, expectedNeedsYouExcludingBeacon)
        XCTAssertFalse(s.isEmpty)
    }
}

import XCTest
@testable import codepet

final class SpacedSchedulerTests: XCTestCase {

    /// Fixed reference point; intervals are expressed in days from here.
    private let now = Date(timeIntervalSince1970: 1_750_000_000)
    private let config = SpacedScheduler.Config()

    private func days(_ d: Double) -> TimeInterval { d * 86_400 }
    private func at(_ d: Double) -> Date { now.addingTimeInterval(days(d)) }

    /// A state in `box`, due `dueInDays` from `now`.
    private func state(box: Int, dueInDays: Double) -> ReviewState {
        ReviewState(box: box, dueAt: at(dueInDays), lastReviewed: nil)
    }

    // MARK: - Lifecycle

    func testInitialIsEncounteredAndDueAfterFirstInterval() {
        let s = SpacedScheduler.initial(now: now)
        XCTAssertEqual(s.box, 0)
        XCTAssertEqual(s.dueAt, at(2))                 // intervals[0] = 2 days
        XCTAssertNil(s.lastReviewed)
        XCTAssertEqual(SpacedScheduler.stage(forBox: s.box), "encountered")
        XCTAssertFalse(SpacedScheduler.isDue(s, now: now))
        XCTAssertTrue(SpacedScheduler.isDue(s, now: at(2)))   // inclusive at the boundary
    }

    // MARK: - Success transitions

    func testGotItAdvancesBoxAndReschedules() {
        let next = SpacedScheduler.advance(state(box: 0, dueInDays: 0), grade: .gotIt, now: now)
        XCTAssertEqual(next.box, 1)
        XCTAssertEqual(next.dueAt, at(5))              // intervals[1] = 5 days
        XCTAssertEqual(next.lastReviewed, now)
        XCTAssertEqual(SpacedScheduler.stage(forBox: next.box), "used")
    }

    func testRecurredAdvancesLikeSuccess() {
        // The passive path advances exactly like an active "got it".
        let viaRecur = SpacedScheduler.advance(state(box: 1, dueInDays: 0), grade: .recurred, now: now)
        let viaGotIt = SpacedScheduler.advance(state(box: 1, dueInDays: 0), grade: .gotIt, now: now)
        XCTAssertEqual(viaRecur, viaGotIt)
        XCTAssertEqual(viaRecur.box, 2)
        XCTAssertEqual(viaRecur.dueAt, at(12))         // intervals[2] = 12 days
    }

    func testReachingMasteredBoxFlipsTheStage() {
        // Climb 0 → 3 with successful reps; box 3 is the mastered threshold.
        var s = state(box: 2, dueInDays: 0)
        s = SpacedScheduler.advance(s, grade: .gotIt, now: now)
        XCTAssertEqual(s.box, 3)
        XCTAssertEqual(s.dueAt, at(30))                // intervals[3] = 30 days
        XCTAssertEqual(SpacedScheduler.stage(forBox: s.box), "mastered")
    }

    func testTopBoxCapsAtLongestInterval() {
        // Already at the top box: another success parks it, never overflows.
        let top = SpacedScheduler.maxBox()             // 4
        let next = SpacedScheduler.advance(state(box: top, dueInDays: 0), grade: .gotIt, now: now)
        XCTAssertEqual(next.box, top)
        XCTAssertEqual(next.dueAt, at(90))             // intervals[4] = 90 days
        XCTAssertEqual(SpacedScheduler.stage(forBox: next.box), "mastered")
    }

    // MARK: - Fuzzy / forgot

    func testFuzzyHoldsBoxAndBringsBackTomorrow() {
        let next = SpacedScheduler.advance(state(box: 2, dueInDays: 0), grade: .fuzzy, now: now)
        XCTAssertEqual(next.box, 2)                    // held, not advanced
        XCTAssertEqual(next.dueAt, at(1))              // fuzzy = 1 day
    }

    func testForgotDemotesAcrossMasteryAndResurfacesQuickly() {
        // A "mastered" term (box 3) that's forgotten drops to "used" (box 2) and
        // comes back within hours — mastery is revocable, the honesty contract.
        let next = SpacedScheduler.advance(state(box: 3, dueInDays: 0), grade: .forgot, now: now)
        XCTAssertEqual(next.box, 2)
        XCTAssertEqual(SpacedScheduler.stage(forBox: next.box), "used")
        XCTAssertEqual(next.dueAt, at(0.25))           // forgot = 6 hours
    }

    func testForgotAtBoxZeroStaysAtFloor() {
        let next = SpacedScheduler.advance(state(box: 0, dueInDays: 0), grade: .forgot, now: now)
        XCTAssertEqual(next.box, 0)                    // never goes negative
    }

    // MARK: - Passive recurrence gate

    func testRecurrenceCountsOnlyWhenDue() {
        // Due → a real re-encounter advances the box.
        let due = state(box: 1, dueInDays: -1)         // overdue by a day
        let advanced = SpacedScheduler.applyRecurrence(due, now: now)
        XCTAssertEqual(advanced.box, 2)

        // Not yet due → the same re-encounter changes nothing (spacing preserved,
        // so a term used 5× in one session doesn't rocket to mastered).
        let notDue = state(box: 1, dueInDays: 3)
        let unchanged = SpacedScheduler.applyRecurrence(notDue, now: now)
        XCTAssertEqual(unchanged, notDue)
    }

    // MARK: - Due selection

    func testDueReturnsOverdueSortedByUrgencyAndCapped() {
        var cfg = SpacedScheduler.Config()
        cfg.dailyCap = 2
        let states: [String: ReviewState] = [
            "closure":  state(box: 1, dueInDays: -2),  // most overdue
            "optional": state(box: 0, dueInDays: -1),
            "binding":  state(box: 2, dueInDays: -3),  // even more overdue, but…
            "future":   state(box: 0, dueInDays: 4),   // not due → excluded
        ]
        let due = SpacedScheduler.due(states, now: now, config: cfg)
        // Soonest-due first = most-negative dueAt first; capped at 2.
        XCTAssertEqual(due, ["binding", "closure"])
        XCTAssertFalse(due.contains("future"))
    }

    func testDueTieBreaksBySlugDeterministically() {
        let states: [String: ReviewState] = [
            "beta":  state(box: 0, dueInDays: -1),
            "alpha": state(box: 0, dueInDays: -1),     // identical dueAt
        ]
        XCTAssertEqual(SpacedScheduler.due(states, now: now), ["alpha", "beta"])
    }

    func testDueIsEmptyWhenNothingOverdue() {
        let states: [String: ReviewState] = [
            "a": state(box: 0, dueInDays: 1),
            "b": state(box: 2, dueInDays: 5),
        ]
        XCTAssertTrue(SpacedScheduler.due(states, now: now).isEmpty)
    }

    // MARK: - Stage mapping

    func testStageMappingAcrossAllBoxes() {
        XCTAssertEqual(SpacedScheduler.stage(forBox: 0), "encountered")
        XCTAssertEqual(SpacedScheduler.stage(forBox: 1), "used")
        XCTAssertEqual(SpacedScheduler.stage(forBox: 2), "used")
        XCTAssertEqual(SpacedScheduler.stage(forBox: 3), "mastered")
        XCTAssertEqual(SpacedScheduler.stage(forBox: 4), "mastered")
    }
}

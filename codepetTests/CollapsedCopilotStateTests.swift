// codepetTests/CollapsedCopilotStateTests.swift
import XCTest
@testable import codepet

/// The collapsed copilot button is the only signal the closed dock has, so its two
/// rules are load-bearing: a wrong count misreports what's waiting, and a wrong
/// unread rule either nags forever or stays silent when a reply landed.
final class CollapsedCopilotStateTests: XCTestCase {

    // MARK: - unread dot

    func testNoDotWhenNothingArrivedSinceTheDockWasOpen() {
        XCTAssertFalse(CollapsedCopilotState.showsUnreadDot(messageCount: 4, seen: 4))
        XCTAssertFalse(CollapsedCopilotState.showsUnreadDot(messageCount: 0, seen: 0))
    }

    func testDotWhenMessagesArrivedWhileClosed() {
        XCTAssertTrue(CollapsedCopilotState.showsUnreadDot(messageCount: 5, seen: 4))
    }

    /// A thread switch or "New chat" can leave fewer messages than were seen; that
    /// is not unread, and must not read as a negative-delta dot.
    func testShrinkingTranscriptIsNotUnread() {
        XCTAssertFalse(CollapsedCopilotState.showsUnreadDot(messageCount: 2, seen: 9))
    }

    // MARK: - needs-you count agrees with the nav badge

    /// The button's count and the Tasks nav badge must never disagree about the
    /// same state, so the button derives from the same `TopbarCounts.tasks` rule.
    func testNeedsYouMatchesTheTasksNavBadge() {
        let tasks = [
            task("a", who: .you),                 // counts — hers to do
            task("b", who: .draft),               // counts — draft awaiting approval
            task("c", who: .you, done: true),     // done → excluded
            task("d", who: .does),                // Codepet's move → excluded
        ]
        XCTAssertEqual(CollapsedCopilotState.needsYouCount(tasks: tasks), 2)
        // Pinned to the nav badge's own rule, so the two can't drift apart.
        XCTAssertEqual(CollapsedCopilotState.needsYouCount(tasks: tasks),
                       TopbarCounts.tasks(tasks))
    }

    func testNeedsYouIsZeroWithNoTasks() {
        XCTAssertEqual(CollapsedCopilotState.needsYouCount(tasks: []), 0)
    }

    private func task(_ id: String, who: TaskWho, done: Bool = false) -> RoadmapTask {
        RoadmapTask(id: id, title: id, detail: "", phase: .build, who: who, done: done)
    }
}

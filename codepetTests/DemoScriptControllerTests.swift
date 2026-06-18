import XCTest
@testable import codepet

@MainActor
final class DemoScriptControllerTests: XCTestCase {

    func test_initialState_isClean() async {
        let c = DemoScriptController()
        XCTAssertTrue(c.firedMilestones.isEmpty)
        XCTAssertFalse(c.reflectionRevealed)
        XCTAssertNil(c.sessionStartedAt)
    }

    func test_startSession_setsTimestamp() async {
        let c = DemoScriptController()
        c.startSession()
        XCTAssertNotNil(c.sessionStartedAt)
    }

    func test_fireMilestone_appendsToFiredList() async {
        let c = DemoScriptController()
        c.startSession()
        c.fireMilestone(index: 1)
        XCTAssertEqual(c.firedMilestones.map(\.index), [1])
    }

    func test_fireMilestone_isIdempotent() async {
        let c = DemoScriptController()
        c.startSession()
        c.fireMilestone(index: 1)
        c.fireMilestone(index: 1)
        XCTAssertEqual(c.firedMilestones.map(\.index), [1])
    }

    func test_fireMilestone_invalidIndex_isNoop() async {
        let c = DemoScriptController()
        c.startSession()
        c.fireMilestone(index: 99)
        XCTAssertTrue(c.firedMilestones.isEmpty)
    }

    func test_fireMilestone_beforeStart_isNoop() async {
        let c = DemoScriptController()
        c.fireMilestone(index: 1)
        XCTAssertTrue(c.firedMilestones.isEmpty)
    }

    func test_revealReflection_setsFlag() async {
        let c = DemoScriptController()
        c.startSession()
        c.revealReflection()
        XCTAssertTrue(c.reflectionRevealed)
    }

    func test_reset_clearsEverything() async {
        let c = DemoScriptController()
        c.startSession()
        c.fireMilestone(index: 1)
        c.fireMilestone(index: 2)
        c.revealReflection()
        c.reset()
        XCTAssertTrue(c.firedMilestones.isEmpty)
        XCTAssertFalse(c.reflectionRevealed)
        XCTAssertNil(c.sessionStartedAt)
    }

    func test_panicSkip_firesAllRemainingMilestonesAndRevealsReflection() async {
        let c = DemoScriptController()
        c.startSession()
        c.fireMilestone(index: 1)
        c.panicSkip()
        XCTAssertEqual(c.firedMilestones.map(\.index), [1, 2, 3, 4])
        XCTAssertTrue(c.reflectionRevealed)
    }
}

import XCTest
@testable import codepet

final class RoadmapDispatchTests: XCTestCase {
    func testActionPerStatus() {
        XCTAssertEqual(RoadmapDispatch.action(for: .codepetCanDo), .run)
        XCTAssertEqual(RoadmapDispatch.action(for: .needsYou), .walkThrough)
        XCTAssertEqual(RoadmapDispatch.action(for: .needsApproval), .approve)
        XCTAssertEqual(RoadmapDispatch.action(for: .done), .openDeliverable)
        XCTAssertEqual(RoadmapDispatch.action(for: .blocked), RoadmapAction.none)
    }

    /// Only the two actions whose output streams into chat should move the founder there.
    func testOnlyStreamingActionsNavigateToChat() {
        XCTAssertTrue(RoadmapDispatch.navigatesToChat(.run))
        XCTAssertTrue(RoadmapDispatch.navigatesToChat(.walkThrough))
        XCTAssertFalse(RoadmapDispatch.navigatesToChat(.approve))
        XCTAssertFalse(RoadmapDispatch.navigatesToChat(.openDeliverable))
        XCTAssertFalse(RoadmapDispatch.navigatesToChat(RoadmapAction.none))
    }
}

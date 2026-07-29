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

    /// The actions whose output streams into chat should move the founder there.
    func testOnlyStreamingActionsNavigateToChat() {
        XCTAssertTrue(RoadmapDispatch.navigatesToChat(.run))
        XCTAssertTrue(RoadmapDispatch.navigatesToChat(.walkThrough))
        XCTAssertTrue(RoadmapDispatch.navigatesToChat(.editCode))
        XCTAssertFalse(RoadmapDispatch.navigatesToChat(.approve))
        XCTAssertFalse(RoadmapDispatch.navigatesToChat(.openDeliverable))
        XCTAssertFalse(RoadmapDispatch.navigatesToChat(RoadmapAction.none))
    }

    // MARK: - Engineering → edit_code (adaptive: local only when a project is linked)

    func test_engineeringCanDo_withLinkedProject_routesToEditCode() {
        XCTAssertEqual(RoadmapDispatch.action(for: .codepetCanDo, isEngineering: true, projectLinked: true), .editCode)
    }
    func test_engineeringCanDo_noLink_staysCloudRun() {
        XCTAssertEqual(RoadmapDispatch.action(for: .codepetCanDo, isEngineering: true, projectLinked: false), .run)
    }
    func test_nonEngineeringCanDo_staysRun_evenWhenLinked() {
        XCTAssertEqual(RoadmapDispatch.action(for: .codepetCanDo, isEngineering: false, projectLinked: true), .run)
    }
    func test_engineeringNonCanDo_unaffected() {
        XCTAssertEqual(RoadmapDispatch.action(for: .needsYou, isEngineering: true, projectLinked: true), .walkThrough)
        XCTAssertEqual(RoadmapDispatch.action(for: .done, isEngineering: true, projectLinked: true), .openDeliverable)
    }
    func test_defaultParams_preserveLegacyMapping() {
        XCTAssertEqual(RoadmapDispatch.action(for: .codepetCanDo), .run)  // no flags → unchanged
    }
}

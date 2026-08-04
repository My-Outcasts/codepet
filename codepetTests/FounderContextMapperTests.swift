import XCTest
@testable import codepet

final class FounderContextMapperTests: XCTestCase {

    func testBuildsProfileFromRoleAndTech() {
        let brief = CompanyBrief(founderName: "Giang", role: "Solo founder, technical",
                                 tech: "Swift, Firebase")
        let founder = FounderContextMapper.founder(from: brief)
        XCTAssertTrue(founder.profile.contains("Solo founder, technical"))
        XCTAssertTrue(founder.profile.contains("Swift, Firebase"))
    }

    func testStageCarriesTractionGoalAndRunway() {
        var brief = CompanyBrief(stage: "Building", oneLiner: "An AI coding companion",
                                 goal: "Ship to the App Store this month",
                                 traction: "30 beta users, no revenue")
        brief.runway = "About 4 months of money left"
        let founder = FounderContextMapper.founder(from: brief)
        XCTAssertTrue(founder.stage.contains("Building"))
        XCTAssertTrue(founder.stage.contains("30 beta users"))
        XCTAssertTrue(founder.stage.contains("Ship to the App Store this month"))
        XCTAssertTrue(founder.stage.contains("4 months"), "runway belongs in stage")
    }

    func testConstraintsSplitOnNewlines() {
        var brief = CompanyBrief()
        brief.constraints = "Không thuê người quý này.\nPhải ship trong tháng này."
        let founder = FounderContextMapper.founder(from: brief)
        XCTAssertEqual(founder.constraints,
                       ["Không thuê người quý này.", "Phải ship trong tháng này."])
    }

    func testSingleLineConstraintBecomesOneEntry() {
        var brief = CompanyBrief()
        brief.constraints = "Không nhận đầu tư ở giai đoạn này."
        XCTAssertEqual(FounderContextMapper.founder(from: brief).constraints,
                       ["Không nhận đầu tư ở giai đoạn này."])
    }

    func testEmptyBriefStillProducesAValidPayload() {
        // The endpoint rejects a missing profile or stage with HTTP 400, so both
        // must be strings even when the founder has told us nothing.
        let founder = FounderContextMapper.founder(from: CompanyBrief())
        XCTAssertFalse(founder.profile.isEmpty)
        XCTAssertFalse(founder.stage.isEmpty)
        XCTAssertTrue(founder.constraints.isEmpty)
    }

    func testBlankFieldsAreDroppedNotJoinedAsEmptySegments() {
        let brief = CompanyBrief(role: "   ", tech: "Swift")
        let founder = FounderContextMapper.founder(from: brief)
        XCTAssertFalse(founder.profile.contains("·  ·"))
        XCTAssertTrue(founder.profile.contains("Swift"))
    }
}

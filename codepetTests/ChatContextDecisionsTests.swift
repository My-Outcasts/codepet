import XCTest
@testable import codepet

final class ChatContextDecisionsTests: XCTestCase {
    func testComposeIncludesDecisionsBlockWhenPresent() {
        let s = ChatContext.compose(brief: CompanyBrief(projectName: "Codepet"), tasks: [],
                                    decisions: [DecisionEntry(topic: "pricing", statement: "$4/mo", source: nil, updatedAt: nil)])
        XCTAssertTrue(s.contains("- pricing: $4/mo"))
        XCTAssertTrue(s.contains("honor these"))
    }

    func testComposeOmitsDecisionsWhenEmpty() {
        let s = ChatContext.compose(brief: CompanyBrief(projectName: "Codepet"), tasks: [])
        XCTAssertFalse(s.contains("honor these"))
    }
}

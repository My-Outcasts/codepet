import XCTest
@testable import codepet

/// The header the chat view puts above a reply, asserted through the shared rule rather
/// than through the view (`headerName` is private to a SwiftUI view and unreachable).
final class CopilotChatHeaderTests: XCTestCase {

    private func header(_ m: CopilotMessage) -> String? {
        CodepetBrand.header(companionId: m.companionId, deptName: m.deptName)
    }

    private func reply(companionId: String? = nil, deptName: String? = nil) -> CopilotMessage {
        CopilotMessage(role: .companion, text: "x",
                       companionId: companionId, deptName: deptName)
    }

    func testASpecialistReplyIsHeadedWithPetAndDepartment() {
        XCTAssertEqual(header(reply(companionId: "sage", deptName: "Support")), "Sage · Support")
    }

    func testAnOrdinaryReplyHasNoHeader() {
        XCTAssertNil(header(reply()))
    }

    /// The regression this whole change exists to prevent: no reply anywhere reads "Codepet".
    func testNoReplyIsEverHeadedCodepet() {
        let cases = [reply(), reply(companionId: "nova", deptName: "Marketing"),
                     reply(companionId: "byte", deptName: "Engineering"), reply(deptName: "Legal")]
        for m in cases {
            XCTAssertNotEqual(header(m), "Codepet", "no reply may sign itself with the product name")
        }
    }

    // Task 4 adds `testEveryPetAskedQuestionResolvesToAPetHeader` here, once `.petAsks` exists
    // on `DayOneScript`'s intent enum. Tracked in the progress ledger — do not add it early.
}

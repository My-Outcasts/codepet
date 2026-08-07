// codepetTests/DepartmentAddressingTests.swift
import XCTest
@testable import codepet

/// A department has to be ADDRESSED, not merely mentioned.
///
/// `mentionedDeptKey` used to be `lower.contains(dept.name.lowercased())` over the whole message.
/// On Aug 7 that handed a SALES task to Support, because the founder pasted a bakery's habits:
/// "emails me when something's off instead of using support". One incidental word inside quoted
/// customer data changed who answered.
final class DepartmentAddressingTests: XCTestCase {

    /// The founder's actual message, trimmed to the sentence that caused it.
    func testAnIncidentalMentionInPastedDataDoesNotHandOff() {
        let paste = "Ninth Street Sourdough — 220 loaves/wk, 42 orders, in 5–6 days a week, "
            + "emails me when something's off instead of using support."
        XCTAssertNil(DepartmentCompanions.mentionedDeptKey(in: paste),
                     "a department word inside customer data is not a handoff")
    }

    /// Substrings were the other half of the bug.
    func testSubstringsNoLongerMatch() {
        XCTAssertNil(DepartmentCompanions.mentionedDeptKey(in: "the app is well designed"))
        XCTAssertNil(DepartmentCompanions.mentionedDeptKey(in: "our operational costs are high"))
        XCTAssertNil(DepartmentCompanions.mentionedDeptKey(in: "supporting nine bakeries is a lot"))
    }

    /// The cases the heuristic exists for must still work.
    func testAddressingADepartmentStillHandsOff() {
        XCTAssertEqual(DepartmentCompanions.mentionedDeptKey(in: "ask marketing about the launch"), "mkt")
        XCTAssertEqual(DepartmentCompanions.mentionedDeptKey(in: "what does finance think of this?"), "fin")
        XCTAssertEqual(DepartmentCompanions.mentionedDeptKey(in: "bring in legal before we sign"), "legal")
        XCTAssertEqual(DepartmentCompanions.mentionedDeptKey(in: "marketing's take on the copy?"), "mkt")
    }

    /// Opening with the name is addressing it.
    func testOpeningWithTheDepartmentNameCounts() {
        XCTAssertEqual(DepartmentCompanions.mentionedDeptKey(in: "Design, can you look at this?"), "design")
    }

    /// Plain prose about a topic is not a handoff — this is the direction it must fail in, since
    /// the host answering looks normal and the wrong pet answering does not.
    func testTalkingAboutATopicIsNotAddressingIt() {
        XCTAssertNil(DepartmentCompanions.mentionedDeptKey(in: "our marketing has been quiet lately"))
        XCTAssertNil(DepartmentCompanions.mentionedDeptKey(in: "I need a support inbox eventually"))
    }

    func testEmptyAndUnrelatedTextYieldNothing() {
        XCTAssertNil(DepartmentCompanions.mentionedDeptKey(in: ""))
        XCTAssertNil(DepartmentCompanions.mentionedDeptKey(in: "how many loaves should we bake?"))
    }
}

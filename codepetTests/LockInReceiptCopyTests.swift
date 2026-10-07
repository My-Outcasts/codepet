import XCTest
@testable import codepet

/// CP-075 (7 Oct design pass): a locked-in call says so once, in the call card's footer —
/// "Locked in · <pick> · saved to memory" — instead of a 📌 "Noted" strip under the card.
/// CP-050's lesson still holds: the receipt names the PICK, never the room's long question.
final class LockInReceiptCopyTests: XCTestCase {
    func testTheReceiptNamesThePick() {
        XCTAssertEqual(LockInReceiptCopy.pick("Naive unit-number lookup"), "Naive unit-number lookup")
        XCTAssertEqual(LockInReceiptCopy.pick("  Invoice ten founders now \n"), "Invoice ten founders now")
    }

    func testNoPickNamesNothing() {
        XCTAssertNil(LockInReceiptCopy.pick(nil), "a lock-in of the recommendation: the headline already says it")
        XCTAssertNil(LockInReceiptCopy.pick("   "))
    }

    func testCopyIsLocalised() {
        XCTAssertEqual(LockInReceiptCopy.lockedIn(.en), "Locked in")
        XCTAssertEqual(LockInReceiptCopy.saved(.en), "saved to memory")
        XCTAssertEqual(LockInReceiptCopy.lockedIn(.vi), "Đã chốt")
        XCTAssertEqual(LockInReceiptCopy.saved(.vi), "đã lưu vào bộ nhớ")
    }
}

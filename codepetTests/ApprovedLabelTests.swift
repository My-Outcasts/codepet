// codepetTests/ApprovedLabelTests.swift
import XCTest
@testable import codepet

/// After Approve, the draft card says what happened. A revision REPLACES a Library item (CP-025),
/// so "Added to Library" was untrue there — seen in the in-app check on 25 Sep. A first pass is
/// still added, and keeps its wording.
final class ApprovedLabelTests: XCTestCase {
    func testAFirstPassIsAddedToTheLibrary() {
        XCTAssertEqual(DraftCardCopy.approvedLabel(.en, replacedItem: false), "Added to Library")
        XCTAssertEqual(DraftCardCopy.approvedLabel(.vi, replacedItem: false), "Đã thêm vào Thư viện")
    }

    func testARevisionSaysItUpdatedTheItem() {
        XCTAssertEqual(DraftCardCopy.approvedLabel(.en, replacedItem: true), "Updated in your Library")
        XCTAssertEqual(DraftCardCopy.approvedLabel(.vi, replacedItem: true), "Đã cập nhật trong Thư viện")
    }
}

// codepetTests/CopilotMessageDraftTests.swift
import XCTest
@testable import codepet

final class CopilotMessageDraftTests: XCTestCase {
    func testDraftDefaultsNilAndNotApproved() {
        let m = CopilotMessage(role: .companion, text: "hi")
        XCTAssertNil(m.draft)
        XCTAssertFalse(m.draftApproved)
    }
    func testCarriesDraftAndEquatable() {
        let d = Deliverable(id: "d1", kind: .doc, title: "T", body: "b")
        let t = Date(timeIntervalSince1970: 0)
        let m = CopilotMessage(id: "m1", role: .companion, createdAt: t, text: "", draft: d)
        XCTAssertEqual(m.draft?.id, "d1")
        XCTAssertEqual(m, CopilotMessage(id: "m1", role: .companion, createdAt: t, text: "", draft: d))
        XCTAssertNotEqual(m, CopilotMessage(id: "m1", role: .companion, createdAt: t, text: "", draft: d, draftApproved: true))
    }
}

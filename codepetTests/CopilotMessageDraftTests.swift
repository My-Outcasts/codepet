// codepetTests/CopilotMessageDraftTests.swift
import XCTest
@testable import codepet

final class CopilotMessageDraftTests: XCTestCase {
    func testDraftDefaultsNilAndNotApproved() {
        let m = CopilotMessage(role: .companion, text: "hi")
        XCTAssertNil(m.draft)
        XCTAssertFalse(m.draftApproved)
    }
    /// Equality is about CONTENT, so `createdAt` is pinned on both sides.
    ///
    /// It used to be left to default, and this test went red the moment `createdAt: Date =
    /// Date()` joined the struct (`f0f9253`, the per-message actions work): the synthesized
    /// `==` started comparing a timestamp taken at construction, so two messages built one
    /// statement apart were never equal and the assertion could not pass. It failed on `main`
    /// for a day without being noticed. Pinning the date restores what the test was written to
    /// protect — that `draftApproved` is part of identity — instead of measuring the clock.
    func testCarriesDraftAndEquatable() {
        let t = Date(timeIntervalSince1970: 1_754_400_000)
        let d = Deliverable(id: "d1", kind: .doc, title: "T", body: "b")
        let m = CopilotMessage(id: "m1", role: .companion, createdAt: t, text: "", draft: d)
        XCTAssertEqual(m.draft?.id, "d1")
        XCTAssertEqual(m, CopilotMessage(id: "m1", role: .companion, createdAt: t, text: "", draft: d))
        XCTAssertNotEqual(m, CopilotMessage(id: "m1", role: .companion, createdAt: t, text: "",
                                             draft: d, draftApproved: true))
    }

    /// The regression that broke the test above, pinned as its own guard: two messages that
    /// differ ONLY in when they landed are different messages. Without this, restoring the old
    /// default-`createdAt` shape would make the test above pass again by accident.
    func testCreatedAtParticipatesInEquality() {
        let d = Deliverable(id: "d1", kind: .doc, title: "T", body: "b")
        let a = CopilotMessage(id: "m1", role: .companion,
                               createdAt: Date(timeIntervalSince1970: 1_754_400_000), text: "", draft: d)
        let b = CopilotMessage(id: "m1", role: .companion,
                               createdAt: Date(timeIntervalSince1970: 1_754_400_060), text: "", draft: d)
        XCTAssertNotEqual(a, b)
    }
}

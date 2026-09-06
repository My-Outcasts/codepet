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

    /// Goes red if a department stops attributing its message — the guard the rule-tests
    /// cannot provide, because they assert a pure function that is already correct.
    /// The SwiftUI row itself stays verified on screen; a unit test cannot reach it.
    ///
    /// **Deduped by department, not by beat.** `.petSays` now fires 24 times (8 departments ×
    /// `asks`/`frames`/`reports`), but attribution is resolved from `deptKey` alone — the same
    /// `companionId`/`dept` lookup runs regardless of which line is speaking. Checking all 24
    /// beats would re-run the identical assertion three times per department and call it more
    /// coverage; it isn't. Checking each department once is the same guard this test always
    /// was, just reached through the new case.
    func testEveryPetSaidLineResolvesToAPetHeader() {
        var seen = Set<String>()
        for b in DayOneScript.beats {
            guard case let .petSays(deptKey, _) = b.intent else { continue }
            guard seen.insert(deptKey).inserted else { continue }
            guard let companionId = DepartmentCompanions.companionId(for: deptKey),
                  let dept = DepartmentCatalog.find(deptKey) else {
                return XCTFail("\(deptKey) cannot be attributed at all")
            }
            let h = CodepetBrand.header(companionId: companionId, deptName: dept.name)
            XCTAssertNotNil(h, "\(deptKey)'s line would render with no header")
            XCTAssertNotEqual(h, "Codepet", "\(deptKey)'s line would be signed by the product")
        }
        XCTAssertEqual(seen.count, 8, "expected all eight speaking departments to be checked")
    }
}

// codepetTests/SplitSummaryTests.swift
import XCTest
@testable import codepet

/// CP-030: a landed room listed every disagreeing department PAIR as its own orange line —
/// six "Product ↔ Design · blocker" rows for what the narrative under it called "two live
/// fights". `SplitSummary` says it once, naming who holds the objection.
final class SplitSummaryTests: XCTestCase {
    private let names = ["product": "Product", "design": "Design", "marketing": "Marketing",
                         "sales": "Sales", "finance": "Finance"]
    private func c(_ a: String, _ b: String, _ kind: String) -> VCConflict {
        VCConflict(a: a, b: b, kind: kind, reason: "r")
    }
    private func line(_ cs: [VCConflict], _ lang: AppLanguage = .en) -> String? {
        SplitSummary.line(cs, name: { self.names[$0] ?? $0 }, lang: lang)
    }

    func testNoDisagreementIsNoLine() {
        XCTAssertNil(line([]))
        XCTAssertNil(line([c("product", "sales", "ALIGNED")]), "agreements are not a split")
    }

    /// One department blocking everyone else is ONE objection, not three rows.
    func testOneDepartmentAgainstTheRestNamesThatDepartment() {
        let cs = [c("product", "sales", "BLOCKER"), c("finance", "sales", "BLOCKER"),
                  c("marketing", "sales", "BLOCKER")]
        XCTAssertEqual(line(cs), "Sales holds a hard objection the others don't share.")
        XCTAssertEqual(line(cs, .vi), "Sales có một phản đối cứng mà các phòng ban khác không có.")
    }

    func testOnePairIsNamedAsThatPair() {
        XCTAssertEqual(line([c("product", "design", "CONFLICT")]), "Product and Design see this differently.")
        XCTAssertEqual(line([c("product", "design", "BLOCKER")]), "Product and Design disagree on a hard point.")
    }

    /// CP-040, the changelog room of 29 Sep: one TENSION pair ("same direction, different
    /// priority" or two sets of unread conditions) was headlined "Product and Marketing see this
    /// differently." over a narrative that opened "There is no substantive disagreement". The
    /// backend itself counts only CONFLICT and BLOCKER as a split (`needsNegotiation`,
    /// `briefOmitsDissent`), so tension alone gets the line that says what it is.
    func testTensionAloneIsSameDirectionNotASplit() {
        XCTAssertEqual(line([c("product", "marketing", "TENSION")]),
                       "Product and Marketing agree on the direction but not on every condition.")
        XCTAssertEqual(line([c("product", "marketing", "TENSION")], .vi),
                       "Product và Marketing cùng hướng nhưng chưa thống nhất mọi điều kiện.")
    }

    func testSeveralTensionsNameEveryDepartmentOnce() {
        let cs = [c("product", "marketing", "TENSION"), c("product", "design", "TENSION"),
                  c("marketing", "design", "TENSION")]
        XCTAssertEqual(line(cs),
                       "Product, Marketing and Design agree on the direction but not on every condition.")
    }

    /// A real split beside tensions is headlined by the split alone: the tension pairs must not
    /// turn a single objecting department into "no hub".
    func testARealSplitOutranksTension() {
        let cs = [c("product", "sales", "BLOCKER"), c("finance", "sales", "BLOCKER"),
                  c("product", "finance", "TENSION")]
        XCTAssertEqual(line(cs), "Sales holds a hard objection the others don't share.")
    }

    /// The screenshot case: every pair of four departments marked blocker. That is everyone
    /// holding a condition, not six separate fights.
    func testEveryPairBlockingNamesTheCountNotThePairs() {
        let ds = ["product", "design", "marketing", "sales"]
        var cs: [VCConflict] = []
        for i in 0..<ds.count { for j in (i + 1)..<ds.count { cs.append(c(ds[i], ds[j], "BLOCKER")) } }
        XCTAssertEqual(cs.count, 6, "precondition: the 6-row list from the screenshot")
        XCTAssertEqual(line(cs), "4 departments each hold a hard condition: Product, Design, Marketing, Sales.")
    }

    /// Mixed kinds with no single hub: the departments involved, in first-seen order, once each.
    func testSeveralSplitsNameTheDepartmentsOnce() {
        let cs = [c("product", "design", "CONFLICT"), c("marketing", "sales", "BLOCKER")]
        XCTAssertEqual(line(cs), "Product, Design, Marketing and Sales disagree on parts of this.")
        XCTAssertEqual(line(cs, .vi), "Product, Design, Marketing và Sales bất đồng ở một số điểm.")
    }

    /// Agreements mixed in are ignored, so an ALIGNED pair never turns a hub into "no hub".
    func testAlignedPairsDoNotCount() {
        let cs = [c("product", "sales", "BLOCKER"), c("finance", "sales", "BLOCKER"),
                  c("product", "finance", "ALIGNED")]
        XCTAssertEqual(line(cs), "Sales holds a hard objection the others don't share.")
    }
}

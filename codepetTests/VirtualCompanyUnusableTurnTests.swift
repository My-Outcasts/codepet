// codepetTests/VirtualCompanyUnusableTurnTests.swift
import XCTest
@testable import codepet

/// A negotiation turn the backend could not parse is an ERROR, not content.
///
/// `functions/src/company/negotiation.ts:207` writes `(unusable turn: <error>)` into
/// `precise_disagreement` and leaves the other two fields empty. The round card rendered that as
/// a body paragraph and then printed the headings "Proposes:" and "What would change their mind:"
/// with nothing under them — three lines of furniture around an absence (founder screenshot,
/// Aug 6). `VCRunCards.isUnusable` is the rule that suppresses it, kept pure and static so it can
/// be tested without standing up a view.
final class VirtualCompanyUnusableTurnTests: XCTestCase {

    private func turn(_ disagreement: String,
                      proposal: String = "",
                      change: String = "") -> VCNegotiationTurn {
        VCNegotiationTurn(agent: "product", preciseDisagreement: disagreement,
                          whatWouldChangeMyMind: change, proposal: proposal, resolved: false)
    }

    /// The exact string the backend emits, from the founder's screenshot.
    func testTheBackendsUnusableMarkerIsRecognised() {
        XCTAssertTrue(VCRunCards.isUnusable(
            turn("(unusable turn: what_would_change_my_mind is required)")))
    }

    /// Matched on the PREFIX, because the error text after it varies with whatever the parser
    /// rejected — pinning the whole string would pass today and miss every other failure.
    func testAnyErrorTextAfterThePrefixStillCounts() {
        XCTAssertTrue(VCRunCards.isUnusable(turn("(unusable turn: proposal is required)")))
        XCTAssertTrue(VCRunCards.isUnusable(turn("(unusable turn: )")))
    }

    /// Leading whitespace must not smuggle a broken turn through as content.
    func testLeadingWhitespaceDoesNotDefeatIt() {
        XCTAssertTrue(VCRunCards.isUnusable(turn("   (unusable turn: bad json)")))
    }

    /// A real turn is never suppressed — that would delete a department's argument, which is the
    /// opposite failure and a worse one.
    func testARealTurnIsNotSuppressed() {
        XCTAssertFalse(VCRunCards.isUnusable(
            turn("Finance wants the discovery phase bounded in cost and time.",
                 proposal: "Timebox it to 3 weeks.",
                 change: "If runway were longer than 9 months.")))
    }

    /// A department legitimately discussing unusable data must not be mistaken for a parse
    /// failure: the marker is a prefix, not a substring.
    func testTheWordUnusableInsideARealArgumentIsFine() {
        XCTAssertFalse(VCRunCards.isUnusable(
            turn("The beta cohort is too small to be usable, so an unusable turn of data is all "
                 + "we would get from a survey.")))
    }

    func testEmptyDisagreementIsNotTreatedAsTheMarker() {
        XCTAssertFalse(VCRunCards.isUnusable(turn("")))
    }
}

/// Pairs that share one reason are rendered once, not once per pair.
///
/// A department raising a hard blocker conflicts with EVERY other department that wants to
/// proceed, so `classifyPair` emits the same `reason` for each of those pairs. With Sales blocking,
/// the founder read the identical paragraph twice — under "Product ↔ Sales" and "Finance ↔ Sales"
/// (screenshot, Aug 7). The classifier is right; the card was repeating it.
final class ConflictGroupingTests: XCTestCase {

    private func c(_ a: String, _ b: String, _ kind: String, _ reason: String) -> VCConflict {
        VCConflict(a: a, b: b, kind: kind, reason: reason)
    }

    func testPairsSharingAReasonAreGroupedUnderOneCopyOfIt() {
        let blocker = "sales raised a hard blocker: Do not publish a public price list."
        let groups = VCRunCards.groupedByReason([
            c("product", "sales", "BLOCKER", blocker),
            c("finance", "sales", "BLOCKER", blocker),
        ])
        XCTAssertEqual(groups.count, 1, "one blocker, one paragraph")
        XCTAssertEqual(groups[0].reason, blocker)
        XCTAssertEqual(groups[0].pairs.count, 2, "both pairs must still be named")
    }

    /// Distinct reasons stay distinct — grouping must not merge two different arguments.
    func testDifferentReasonsStaySeparate() {
        let groups = VCRunCards.groupedByReason([
            c("product", "sales", "BLOCKER", "sales blocked the price list"),
            c("finance", "sales", "CONFLICT", "directly opposed on sequencing"),
        ])
        XCTAssertEqual(groups.count, 2)
    }

    /// First-seen order, so the card follows the classifier's stable output rather than a
    /// dictionary's iteration order — which would reshuffle the card on every redraw.
    func testGroupsKeepFirstSeenOrder() {
        let groups = VCRunCards.groupedByReason([
            c("a", "b", "BLOCKER", "second-listed reason"),
            c("c", "d", "BLOCKER", "first-listed reason"),
            c("e", "f", "BLOCKER", "second-listed reason"),
        ])
        XCTAssertEqual(groups.map(\.reason), ["second-listed reason", "first-listed reason"])
        XCTAssertEqual(groups[0].pairs.count, 2)
    }

    func testEmptyInputYieldsNoGroups() {
        XCTAssertTrue(VCRunCards.groupedByReason([]).isEmpty)
    }
}

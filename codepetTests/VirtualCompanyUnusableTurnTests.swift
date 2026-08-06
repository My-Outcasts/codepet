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

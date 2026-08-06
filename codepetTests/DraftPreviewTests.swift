// codepetTests/DraftPreviewTests.swift
import XCTest
@testable import codepet

final class DraftPreviewTests: XCTestCase {

    /// The founder's Aug 6 screenshot, verbatim: of three preview lines, one was a heading
    /// echoing the card's own title and one was `**` markers, so the copy itself was pushed
    /// out of view. Both lines must be gone and the prose must lead.
    func testTheReportedCardPreviewShowsProseNotSyntax() {
        let body = """
        # Codepet — Landing Page Copy

        **Tab / SEO title:** Codepet — The AI cofounder that runs your busywork
        """
        let out = DraftPreview.plain(body, title: "Codepet Landing Page Copy")
        XCTAssertEqual(out, "Tab / SEO title: Codepet — The AI cofounder that runs your busywork")
        XCTAssertFalse(out.contains("#"))
        XCTAssertFalse(out.contains("**"))
    }

    // MARK: - The title echo

    func testLeadingHeadingThatEchoesTheTitleIsDropped() {
        let out = DraftPreview.plain("# Pricing Plan\n\nWe land at $20/mo.", title: "Pricing Plan")
        XCTAssertEqual(out, "We land at $20/mo.")
    }

    /// Punctuation must not defeat the match — the generated bodies use em dashes and colons
    /// where the stored title does not.
    func testEchoMatchesAcrossPunctuationDifferences() {
        let out = DraftPreview.plain("## Codepet: Landing — Page Copy\nReal copy.",
                                     title: "Codepet Landing Page Copy")
        XCTAssertEqual(out, "Real copy.")
    }

    /// A heading that says something else is content, and keeping it is the whole point of
    /// stripping only the marker.
    func testLeadingHeadingThatDiffersIsKeptAsProse() {
        let out = DraftPreview.plain("# The offer\nBuy it.", title: "Pricing Plan")
        XCTAssertEqual(out, "The offer\nBuy it.")
    }

    /// Scoped to the LEADING heading: once prose has been emitted, a later section heading
    /// matching the title is real structure and stays.
    func testLaterHeadingMatchingTheTitleSurvives() {
        let out = DraftPreview.plain("Intro line.\n\n# Pricing Plan\nDetail.", title: "Pricing Plan")
        XCTAssertEqual(out, "Intro line.\n\nPricing Plan\nDetail.")
    }

    func testEmptyTitleDropsNothing() {
        let out = DraftPreview.plain("# Anything\nBody.")
        XCTAssertEqual(out, "Anything\nBody.")
    }

    // MARK: - Inline markers

    func testBoldItalicAndCodeMarkersAreRemoved() {
        XCTAssertEqual(DraftPreview.plain("**bold** and __also bold__ and *slanted* and `code`"),
                       "bold and also bold and slanted and code")
    }

    func testLinksAndImagesCollapseToTheirLabel() {
        XCTAssertEqual(DraftPreview.plain("See [the docs](https://x.com/a?b=1) now."),
                       "See the docs now.")
        XCTAssertEqual(DraftPreview.plain("![hero shot](img.png) below"), "hero shot below")
    }

    /// `_` is left alone on purpose — stripping it would corrupt identifiers, which show up in
    /// engineering deliverables far more often than `_italics_`.
    func testUnderscoresInsideIdentifiersSurvive() {
        XCTAssertEqual(DraftPreview.plain("Call run_task_id on the client."),
                       "Call run_task_id on the client.")
    }

    /// A lone asterisk is arithmetic or a footnote, not emphasis, and must not be eaten.
    func testUnpairedAsteriskIsLeftAlone() {
        XCTAssertEqual(DraftPreview.plain("Costs 3 * 4 dollars"), "Costs 3 * 4 dollars")
        XCTAssertEqual(DraftPreview.plain("Free tier*"), "Free tier*")
    }

    // MARK: - Line markers

    func testBulletsBlockquotesAndOrderedItemsKeepTheirText() {
        let body = """
        - first point
        * second point
        + third point
        1. ordered point
        > quoted point
        """
        XCTAssertEqual(DraftPreview.plain(body),
                       "first point\nsecond point\nthird point\nordered point\nquoted point")
    }

    /// A bullet marker needs a following space. `*Bold*` opening a line is emphasis, and eating
    /// it as a bullet would delete the closing marker's partner and leave a stray `*`.
    func testLeadingEmphasisIsNotMistakenForABullet() {
        XCTAssertEqual(DraftPreview.plain("*Note:* read this"), "Note: read this")
    }

    func testHorizontalRulesAreDropped() {
        XCTAssertEqual(DraftPreview.plain("Above\n\n---\n\nBelow"), "Above\n\nBelow")
    }

    // MARK: - Whitespace

    func testBlankRunsCollapseAndEdgesAreTrimmed() {
        XCTAssertEqual(DraftPreview.plain("\n\n# H\n\n\n\nBody\n\n\n", title: "H"), "Body")
    }

    func testPlainProseIsReturnedUnchanged() {
        let prose = "We priced it at $20 a month.\n\nThat covers 800 credits."
        XCTAssertEqual(DraftPreview.plain(prose, title: "Pricing"), prose)
    }

    func testEmptyBodyStaysEmpty() {
        XCTAssertEqual(DraftPreview.plain("", title: "Anything"), "")
    }
}

// codepetTests/MarkdownBlocksTests.swift
import XCTest
@testable import codepet

final class MarkdownBlocksTests: XCTestCase {
    func testParsesHeadingsBulletsParagraphs() {
        let md = """
        # Title
        intro line one
        intro line two

        ## Section
        - first
        - second
        """
        XCTAssertEqual(MarkdownBlocks.parse(md), [
            .heading(level: 1, text: "Title"),
            .paragraph("intro line one intro line two"),
            .heading(level: 2, text: "Section"),
            .bullet("first"),
            .bullet("second"),
        ])
    }
    func testLevelsAndStarBullets() {
        XCTAssertEqual(MarkdownBlocks.parse("### Deep"), [.heading(level: 3, text: "Deep")])
        XCTAssertEqual(MarkdownBlocks.parse("* star"), [.bullet("star")])
    }
    func testEmptyAndPlain() {
        XCTAssertEqual(MarkdownBlocks.parse(""), [])
        XCTAssertEqual(MarkdownBlocks.parse("just text"), [.paragraph("just text")])
    }
    func testExtraSpacingAndCRLFTrimmed() {
        XCTAssertEqual(MarkdownBlocks.parse("-  item"), [.bullet("item")])   // double space after marker
        XCTAssertEqual(MarkdownBlocks.parse("# Title\r"), [.heading(level: 1, text: "Title")])  // CRLF
    }

    // MARK: - Tables (24 Sep test session: every table in a unit-economics sheet rendered as
    // one run-on paragraph of pipes, because table rows fell through to `.paragraph`.)

    func testParsesPipeTableBetweenParagraphs() {
        let md = """
        Per-session cost:
        | Component | Rate | Per session |
        |---|:---:|---:|
        | Speech-to-text | $0.0060 / min | **$0.036** |
        | LLM inference | $0.80 / M in | **$0.048** |
        Round to $0.13.
        """
        XCTAssertEqual(MarkdownBlocks.parse(md), [
            .paragraph("Per-session cost:"),
            .table(header: ["Component", "Rate", "Per session"],
                   alignments: [.leading, .center, .trailing],
                   rows: [["Speech-to-text", "$0.0060 / min", "**$0.036**"],
                          ["LLM inference", "$0.80 / M in", "**$0.048**"]]),
            .paragraph("Round to $0.13."),
        ])
    }

    func testTableWithoutOuterPipesRaggedRowsAndEscapedPipe() {
        let md = """
        Cohort | Sessions
        --- | ---
        Light | 8 | extra
        a \\| b | 2
        Heavy users churn.
        """
        XCTAssertEqual(MarkdownBlocks.parse(md), [
            .table(header: ["Cohort", "Sessions"],
                   alignments: [.leading, .leading],
                   rows: [["Light", "8"],        // extra cell dropped
                          ["a | b", "2"]]),      // escaped pipe is cell text, not a divider
            // A line with no pipe ends the table rather than becoming a one-cell row.
            .paragraph("Heavy users churn."),
        ])
    }

    func testPipesWithoutSeparatorRowStayParagraph() {
        // No `|---|` under the first row: not a table, so the old behaviour holds.
        XCTAssertEqual(MarkdownBlocks.parse("a | b\nc | d"), [.paragraph("a | b c | d")])
    }

    func testHeaderOnlyTableAndShortRowPadded() {
        let md = """
        | A | B | C |
        |---|---|---|
        | 1 |
        """
        XCTAssertEqual(MarkdownBlocks.parse(md), [
            .table(header: ["A", "B", "C"],
                   alignments: [.leading, .leading, .leading],
                   rows: [["1", "", ""]]),
        ])
        XCTAssertEqual(MarkdownBlocks.parse("| A |\n|---|"), [
            .table(header: ["A"], alignments: [.leading], rows: []),
        ])
    }
}

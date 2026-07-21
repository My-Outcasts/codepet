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
}

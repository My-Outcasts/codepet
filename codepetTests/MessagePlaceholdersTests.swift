// codepetTests/MessagePlaceholdersTests.swift
import XCTest
import SwiftUI
@testable import codepet

final class MessagePlaceholdersTests: XCTestCase {

    private func found(_ text: String) -> [String] {
        MessagePlaceholders.spans(in: text).map { String(Array(text)[$0]) }
    }

    /// The founder's Aug 10 screenshot, verbatim: a cold-outreach draft whose two blanks sat
    /// invisible in the middle of a sentence. Both must be found, and nothing else.
    func testTheReportedDraftFindsExactlyItsTwoBlanks() {
        let body = "Hi [name] — we cut onboarding from three weeks to two days for teams your "
                 + "size, and it runs about $[X]/month. Worth fifteen minutes?"
        XCTAssertEqual(found(body), ["[name]", "[X]"])
        XCTAssertEqual(MessagePlaceholders.labels(in: body).count, 2)
    }

    // MARK: - What counts

    func testBracketAndMustacheFormsAreBothFound() {
        XCTAssertEqual(found("Hi [Name], welcome to {{company}}."), ["[Name]", "{{company}}"])
    }

    func testAPlaceholderMayHoldSpacesAndPunctuation() {
        XCTAssertEqual(found("Ask about [their Series A timing]."), ["[their Series A timing]"])
    }

    // MARK: - What is rejected, and why

    /// A markdown link is a destination, not a blank — tinting `the docs` yellow would tell
    /// the founder to go fill in something that is already filled in.
    func testMarkdownLinksAreNotPlaceholders() {
        XCTAssertEqual(found("See [the docs](https://codepet.app) first."), [])
    }

    /// `[1]` is a footnote marker. Sources and citations show up in the research-backed
    /// deliverables often enough that painting them would be constant noise.
    func testNumericReferencesAreNotPlaceholders() {
        XCTAssertEqual(found("Retention rose 12% [1] last quarter [42]."), [])
        XCTAssertEqual(found("Budget is [X] but headcount is [2]."), ["[X]"])
    }

    func testEmptyAndBlankBracketsAreNotPlaceholders() {
        XCTAssertEqual(found("Checkbox [] and [   ] here."), [])
    }

    /// An unclosed `[` is prose that happens to open a bracket. Running to the end of the
    /// document looking for its partner would swallow the whole message.
    func testAnUnclosedBracketSwallowsNothing() {
        XCTAssertEqual(found("We shipped [the beta\nand it went well."), [])
    }

    /// A label is a label. Long bracketed asides are the author talking, not a blank.
    func testOverlongBracketedProseIsLeftAlone() {
        let aside = "[" + String(repeating: "a", count: MessagePlaceholders.maxLabelLength + 5) + "]"
        XCTAssertEqual(found("Note \(aside) here."), [])
    }

    func testProseWithNoBlanksReportsNone() {
        let clean = "Thanks for the intro — I'll follow up Thursday with the numbers."
        XCTAssertEqual(found(clean), [])
        XCTAssertTrue(MessagePlaceholders.labels(in: clean).isEmpty)
        XCTAssertTrue(MessagePlaceholders.spans(in: "").isEmpty)
    }

    // MARK: - Counting

    /// The count answers "how many things must I decide", so a name used four times is one
    /// decision. Case follows suit: `[Name]` and `[name]` are the same blank.
    func testRepeatsCollapseAndCaseIsIgnored() {
        let body = "Hi [Name], I saw [name] posted about [topic]. Regards to [NAME]."
        XCTAssertEqual(found(body).count, 4)
        XCTAssertEqual(MessagePlaceholders.labels(in: body), ["[Name]", "[topic]"])
    }

    // MARK: - Highlighting the parsed string

    /// Offsets are computed AFTER markdown parsing, never on the source. Parsing removes the
    /// `**` markers, so a span measured on the raw text would land two characters late and
    /// tint the wrong words.
    func testHighlightSurvivesMarkdownShiftingTheOffsets() {
        let attr = MessagePlaceholders.attributed("**Hi [name]** — good to meet you.",
                                            tint: .yellow, ink: .black)
        let plain = String(attr.characters)
        XCTAssertFalse(plain.contains("**"), "markers should be parsed away")

        guard let range = plain.range(of: "[name]") else { return XCTFail("placeholder lost") }
        let lo = plain.distance(from: plain.startIndex, to: range.lowerBound)
        let hi = plain.distance(from: plain.startIndex, to: range.upperBound)
        let start = attr.index(attr.startIndex, offsetByCharacters: lo)
        let end = attr.index(attr.startIndex, offsetByCharacters: hi)

        XCTAssertNotNil(attr[start..<end].backgroundColor, "the blank should be tinted")
        XCTAssertNil(attr[attr.startIndex..<start].backgroundColor,
                     "the greeting before it should not be")
        XCTAssertNil(attr[end..<attr.endIndex].backgroundColor,
                     "the sentence after it should not be")
    }

    func testHighlightLeavesCleanProseUntouched() {
        let attr = MessagePlaceholders.attributed("Nothing to fill in here.", tint: .yellow, ink: .black)
        XCTAssertNil(attr[attr.startIndex..<attr.endIndex].backgroundColor)
    }

    // MARK: - Plain text (the chat transcript)

    /// The chat renders prose literally. Tinting must not quietly turn it into a markdown
    /// renderer — `**` in a transcript has always stayed `**`, and changing that alongside
    /// the tint would be a second, unasked-for change.
    func testTintedLeavesMarkdownMarkersAlone() {
        let attr = MessagePlaceholders.tinted("**Hey [name]** — quick one.",
                                              tint: .yellow, ink: .black)
        XCTAssertTrue(String(attr.characters).contains("**"), "plain text must stay plain")
    }

    /// The founder's Aug 10 chat reply: two drafted messages written as prose, four blanks
    /// between them. All four light up even with no deliverable involved.
    func testTheChatReplyBlanksAreAllFound() {
        let reply = """
        Here's two versions — one for the two who already asked, one for the rest.

        "Hey [name] — you asked about paying for Ferment, so here's the real offer: \
        $39/month, locked in for a year. Goes live [date]."

        "Quick heads up — Ferment's moving to paid starting [date], $39/month."
        """
        XCTAssertEqual(found(reply), ["[name]", "[date]", "[date]"])
        XCTAssertEqual(MessagePlaceholders.labels(in: reply), ["[name]", "[date]"])
    }
}

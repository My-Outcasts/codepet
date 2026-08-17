// codepetTests/SyntaxHighlightTests.swift
import XCTest
@testable import codepet

/// The Review pane's tokeniser.
///
/// It is not a parser and never will be. What it must never do is CHANGE the
/// code — a diff whose text is subtly wrong is worse than a diff with no
/// colour at all, because the founder is about to approve it.
final class SyntaxHighlightTests: XCTestCase {

    private func joined(_ line: String, _ language: SyntaxHighlight.Language?) -> String {
        SyntaxHighlight.spans(line, language: language).map(\.text).joined()
    }

    // MARK: - the property that matters

    func test_theCodeIsNeverAltered() {
        // The renderer concatenates spans back into one Text. If tokenising
        // dropped or duplicated a character, the founder would review code
        // that is not what the agent wrote — and approve it.
        let lines = [
            #"const sk = process.env.STRIPE_KEY // secret"#,
            #"let total = cart.sum() * 1.5"#,
            #"if (x === "a\"b") { return 42 }"#,
            #"    <a href="https://example.com">Join</a>"#,
            #"def main(argv: list[str]) -> None:"#,
            "",
            "   ",
            #"emoji = "🌱 plant""#,
            #"`template ${with} parts`"#
        ]
        for language: SyntaxHighlight.Language? in [.cFamily, .python, .css, .markup, .json, nil] {
            for line in lines {
                XCTAssertEqual(joined(line, language), line,
                               "tokenising altered the line: \(line) as \(String(describing: language))")
            }
        }
    }

    // MARK: - the four classes

    func test_aWholeWordIsAKeywordAndAPrefixIsNot() {
        // "information" must not colour because it begins with "in".
        let spans = SyntaxHighlight.spans("return information", language: .cFamily)
        XCTAssertEqual(spans.first(where: { $0.text == "return" })?.kind, .keyword)
        XCTAssertEqual(spans.first(where: { $0.text == "information" })?.kind, .plain)
    }

    func test_stringsIncludeTheirQuotes() {
        let spans = SyntaxHighlight.spans(#"x = "hello""#, language: .cFamily)
        XCTAssertTrue(spans.contains(SyntaxHighlight.Span(text: #""hello""#, kind: .string)))
    }

    func test_anEscapedQuoteDoesNotEndTheString() {
        let spans = SyntaxHighlight.spans(#"a = "x\"y" + b"#, language: .cFamily)
        XCTAssertTrue(spans.contains { $0.kind == .string && $0.text == #""x\"y""# })
    }

    func test_anUnterminatedStringRunsToEndOfLine() {
        // Normal in a diff: GitHub truncates long lines, so an unclosed quote
        // is a rendering problem rather than a syntax error.
        let spans = SyntaxHighlight.spans(#"msg = "half a str"#, language: .cFamily)
        XCTAssertEqual(spans.last?.kind, .string)
        XCTAssertEqual(joined(#"msg = "half a str"#, .cFamily), #"msg = "half a str"#)
    }

    func test_aDecimalStaysOneNumber() {
        let spans = SyntaxHighlight.spans("total = 3.14", language: .cFamily)
        XCTAssertTrue(spans.contains(SyntaxHighlight.Span(text: "3.14", kind: .number)))
    }

    func test_aCommentSwallowsTheRestOfTheLine() {
        let spans = SyntaxHighlight.spans("x = 1 // set the thing", language: .cFamily)
        XCTAssertEqual(spans.last?.kind, .comment)
        XCTAssertEqual(spans.last?.text, "// set the thing")
    }

    func test_aUrlInsideAStringIsNotAComment() {
        // The classic false positive. `https://x` would otherwise paint half
        // the line grey and hide the rest of the code.
        let line = #"const u = "https://example.com/x""#
        let spans = SyntaxHighlight.spans(line, language: .cFamily)
        XCTAssertFalse(spans.contains { $0.kind == .comment }, "a URL was read as a comment")
        XCTAssertEqual(joined(line, .cFamily), line)
    }

    func test_pythonUsesHashNotSlashes() {
        XCTAssertEqual(SyntaxHighlight.spans("x = 1 # note", language: .python).last?.kind, .comment)
        XCTAssertNil(SyntaxHighlight.spans("x = 1 // note", language: .python)
            .first { $0.kind == .comment })
    }

    // MARK: - which language, if any

    func test_theLanguageComesFromTheExtension() {
        XCTAssertEqual(SyntaxHighlight.Language.of(path: "api/billing.ts"), .cFamily)
        XCTAssertEqual(SyntaxHighlight.Language.of(path: "codepet/App.swift"), .cFamily)
        XCTAssertEqual(SyntaxHighlight.Language.of(path: "scripts/run.py"), .python)
        XCTAssertEqual(SyntaxHighlight.Language.of(path: "site/styles.css"), .css)
        XCTAssertEqual(SyntaxHighlight.Language.of(path: "site/index.html"), .markup)
        XCTAssertEqual(SyntaxHighlight.Language.of(path: "package.json"), .json)
    }

    func test_anUnknownExtensionIsNotGuessedAt() {
        // Plain is correct rather than colourful. Guessing would paint a
        // lockfile or a binary blob as if we understood it.
        XCTAssertNil(SyntaxHighlight.Language.of(path: "public/logo.png"))
        XCTAssertNil(SyntaxHighlight.Language.of(path: "Dockerfile"))
        XCTAssertEqual(SyntaxHighlight.spans("anything at all", language: nil),
                       [SyntaxHighlight.Span(text: "anything at all", kind: .plain)])
    }

    func test_theExtensionIsCaseInsensitive() {
        XCTAssertEqual(SyntaxHighlight.Language.of(path: "A/B/Main.SWIFT"), .cFamily)
    }
}

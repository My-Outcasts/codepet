import XCTest
@testable import codepet

/// Turning a growing string into speakable sentences.
///
/// The input is not a stream of chunks — it is the SAME string, longer each time
/// (`chatMessages[i].text = streamedText`). So `take` is called repeatedly with a
/// superset of what it saw before and must return only what is newly complete.
/// Everything here is that contract.
final class SentenceSplitterTests: XCTestCase {

    func testHoldsBackAnIncompleteSentence() {
        var s = SentenceSplitter()
        XCTAssertEqual(s.take(from: "Your pricing page"), [],
                       "a half sentence must never be spoken — it sounds like a fault")
    }

    func testEmitsOnceTerminated() {
        var s = SentenceSplitter()
        _ = s.take(from: "Your pricing page buries the price")
        XCTAssertEqual(s.take(from: "Your pricing page buries the price. And the CTA"),
                       ["Your pricing page buries the price."])
    }

    /// The core contract: repeated calls with a growing string never repeat output.
    func testNeverRepeatsASentence() {
        var s = SentenceSplitter()
        let full = "One. Two. Three."
        var out: [String] = []
        for end in stride(from: 1, through: full.count, by: 1) {
            out += s.take(from: String(full.prefix(end)))
        }
        XCTAssertEqual(out, ["One.", "Two.", "Three."])
    }

    func testHandlesQuestionsExclamationsAndNewlines() {
        var s = SentenceSplitter()
        XCTAssertEqual(s.take(from: "Why? Because!\nDone. "),
                       ["Why?", "Because!", "Done."])
    }

    /// A terminator only ends a sentence when whitespace or the end follows it —
    /// without that check, "$3.14" splits mid-number into "$3." and "14 today."
    func testDoesNotSplitADecimalNumberMidSentence() {
        var s = SentenceSplitter()
        XCTAssertEqual(s.take(from: "The price is $3.14 today."),
                       ["The price is $3.14 today."])
    }

    // MARK: - Markdown, because replies are markdown

    func testStripsEmphasisAndBackticks() {
        XCTAssertEqual(SentenceSplitter.speakable("**bold** and `code` and _soft_"),
                       "bold and code and soft")
    }

    func testStripsHeadingHashesButKeepsTheWords() {
        XCTAssertEqual(SentenceSplitter.speakable("## Next steps"), "Next steps")
    }

    func testReadsLinksAsTheWordLink() {
        // Spelling out "h t t p s colon slash slash" is unbearable.
        let out = SentenceSplitter.speakable("See https://codepet.app/pricing for more")
        XCTAssertFalse(out.contains("https"))
        XCTAssertTrue(out.contains("link"))
    }

    /// **Fenced code is skipped entirely.** Reading `func viewDidLoad() {` aloud is
    /// noise, and a reply that is only code has nothing to say.
    func testSkipsFencedCodeBlocks() {
        let md = "Here is the fix.\n```swift\nlet x = 1\nprint(x)\n```\nThat should do it."
        let out = SentenceSplitter.speakable(md)
        XCTAssertFalse(out.contains("let x"))
        XCTAssertFalse(out.contains("print"))
        XCTAssertTrue(out.contains("Here is the fix."))
        XCTAssertTrue(out.contains("That should do it."))
    }

    func testAnUnclosedFenceDoesNotSwallowTheRestForever() {
        // Mid-stream, a fence opens before it closes. Everything after it is held
        // rather than spoken — but the text BEFORE it still speaks.
        let out = SentenceSplitter.speakable("Try this.\n```swift\nlet x = 1")
        XCTAssertTrue(out.contains("Try this."))
        XCTAssertFalse(out.contains("let x"))
    }

    func testResetClearsProgress() {
        var s = SentenceSplitter()
        _ = s.take(from: "One. Two.")
        s.reset()
        XCTAssertEqual(s.take(from: "One. Two."), ["One.", "Two."],
                       "reset must let the next reply start from nothing")
    }

    /// A reply that is only a code block yields nothing speakable, which the
    /// overlay reads as "no reply to speak" rather than speaking an empty string.
    func testACodeOnlyReplyIsSilent() {
        var s = SentenceSplitter()
        XCTAssertEqual(s.take(from: "```swift\nlet x = 1\n```\n"), [])
    }
}

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

    /// The core contract: repeated calls with a growing string never repeat
    /// output. The trailing "Three." has nothing after its period while the
    /// string is still growing, so `take` alone cannot release it — only the
    /// closing `flush`, once the stream is known to be over, can.
    func testNeverRepeatsASentence() {
        var s = SentenceSplitter()
        let full = "One. Two. Three."
        var out: [String] = []
        for end in stride(from: 1, through: full.count, by: 1) {
            out += s.take(from: String(full.prefix(end)))
        }
        out += s.flush(from: full)
        XCTAssertEqual(out, ["One.", "Two.", "Three."])
    }

    func testHandlesQuestionsExclamationsAndNewlines() {
        var s = SentenceSplitter()
        XCTAssertEqual(s.take(from: "Why? Because!\nDone. "),
                       ["Why?", "Because!", "Done."])
    }

    /// A terminator only ends a sentence when whitespace follows it in the
    /// rendered text — never because it happens to be the last character
    /// available right now. Streamed one character at a time (the real
    /// calling pattern), the period inside "$3.14" is followed by "1" and
    /// never qualifies; the final period never has anything after it while
    /// still streaming, so `take` must hold the ENTIRE sentence back and
    /// only `flush` — called once the stream ends — releases it. Without
    /// this test, an `atEnd` shortcut that treats "last character available"
    /// as "the reply is over" would speak "The price is $3." mid-stream and
    /// still pass, because a single non-incremental `take` call never
    /// exposes the difference.
    func testDoesNotSplitADecimalNumberMidSentence() {
        var s = SentenceSplitter()
        let full = "The price is $3.14 today."
        var out: [String] = []
        for end in stride(from: 1, through: full.count, by: 1) {
            out += s.take(from: String(full.prefix(end)))
        }
        XCTAssertEqual(out, [], "take alone must never release this sentence")
        XCTAssertEqual(s.flush(from: full), ["The price is $3.14 today."])
    }

    // MARK: - flush: the seam that releases what take refused

    /// The unterminated tail `take` refuses is exactly what `flush` releases
    /// — this is the seam Task 6 calls when the stream ends.
    func testFlushReleasesTheTailThatTakeRefused() {
        var s = SentenceSplitter()
        XCTAssertEqual(s.take(from: "Almost done"), [])
        XCTAssertEqual(s.flush(from: "Almost done"), ["Almost done"])
    }

    /// `flush` only releases what is NEW — it must not repeat a sentence
    /// `take` already returned.
    func testFlushDoesNotReEmitWhatTakeAlreadyReturned() {
        var s = SentenceSplitter()
        XCTAssertEqual(s.take(from: "One. Two."), ["One."])
        XCTAssertEqual(s.flush(from: "One. Two."), ["Two."])
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

    /// Reset must let a fully-consumed reply (take, then flush for the final
    /// sentence) start over from nothing.
    func testResetClearsProgress() {
        var s = SentenceSplitter()
        _ = s.take(from: "One. Two.")
        _ = s.flush(from: "One. Two.")
        s.reset()
        let out = s.take(from: "One. Two.") + s.flush(from: "One. Two.")
        XCTAssertEqual(out, ["One.", "Two."],
                       "reset must let the next reply start from nothing")
    }

    /// A reply that is only a code block yields nothing speakable, which the
    /// overlay reads as "no reply to speak" rather than speaking an empty string.
    func testACodeOnlyReplyIsSilent() {
        var s = SentenceSplitter()
        XCTAssertEqual(s.take(from: "```swift\nlet x = 1\n```\n"), [])
    }
}

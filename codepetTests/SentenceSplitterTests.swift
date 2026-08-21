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
    /// output, across a take-then-flush sequence. This does NOT by itself
    /// guard against a removed `atEnd` shortcut that released "Three." one
    /// call early, mid-stream — the final concatenated output is identical
    /// either way, since that shortcut only moves WHERE "Three." is
    /// released, not what the sequence adds up to. That regression is
    /// caught instead by `testDoesNotSplitADecimalNumberMidSentence` (its
    /// mid-loop `out == []` assertion goes red the instant anything is
    /// released early) and `testFlushDoesNotReEmitWhatTakeAlreadyReturned`
    /// (a single-shot `take` would wrongly also return the second sentence,
    /// since its terminator is the last character of that call's string).
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
        XCTAssertEqual(s.flush(from: full), [full])
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
        let full = "One. Two."
        XCTAssertEqual(s.take(from: full), ["One."])
        XCTAssertEqual(s.flush(from: full), ["Two."])
    }

    // MARK: - Sentence count vs. character offset (the guard this type exists for)

    /// The type doc's own regression case. The opener precedes a terminator
    /// that gets emitted while the emphasis span is still unclosed (so the
    /// asterisk is still literal in that emission); the closer only arrives
    /// in a later delta, which retroactively shortens the rendering by
    /// stripping both asterisks. A character offset recorded against the
    /// first (unresolved) rendering would then point into the middle of the
    /// second (resolved, shorter) one. A sentence COUNT does not care that
    /// the content shifted — only that one sentence was already returned —
    /// so the already-emitted sentence keeps its original (cosmetically
    /// stray-asterisk) wording instead of being corrupted or duplicated.
    func testMarkdownCloserArrivingInALaterDeltaDoesNotDesyncEmittedCount() {
        var s = SentenceSplitter()
        let firstDelta = "This is *bad. "
        let fullDelta = "This is *bad. This is *worse* actually."

        XCTAssertEqual(s.take(from: firstDelta), ["This is *bad."],
                       "emitted while the span is still open — the stray asterisk is the known cosmetic cost")
        XCTAssertEqual(s.take(from: fullDelta), [],
                       "the closer arriving later must not re-emit the sentence it belongs to")
        XCTAssertEqual(s.flush(from: fullDelta), ["This is worse* actually."],
                       "must be the real remaining sentence, not a fragment sliced at a stale character offset")
    }

    // MARK: - URLs must not swallow the sentence's own terminator

    /// Found by review: `\S*` is greedy, so a URL with no space before its
    /// sentence's terminator used to consume the terminator into the match
    /// and strip it away with the rest of the URL — merging two sentences
    /// into one run-on utterance. Never silent, never a half-sentence, but
    /// a real pacing defect, so this is asserted at the sentence level.
    func testURLGreedyMatchDoesNotEatTheFollowingTerminator() {
        var s = SentenceSplitter()
        let full = "Visit https://codepet.app/pricing. Thanks for reading."
        XCTAssertEqual(s.take(from: full) + s.flush(from: full),
                       ["Visit link.", "Thanks for reading."])
    }

    /// The fix must not regress the opposite case: a URL's own trailing
    /// slash is not sentence punctuation and must stay fully consumed.
    func testURLWithTrailingSlashIsFullyConsumed() {
        var s = SentenceSplitter()
        let full = "Try https://codepet.app/. It works."
        XCTAssertEqual(s.take(from: full) + s.flush(from: full),
                       ["Try link.", "It works."])
    }

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
        let full = "One. Two."
        _ = s.take(from: full)
        _ = s.flush(from: full)
        s.reset()
        let out = s.take(from: full) + s.flush(from: full)
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

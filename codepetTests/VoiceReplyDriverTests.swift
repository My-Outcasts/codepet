// codepetTests/VoiceReplyDriverTests.swift
import XCTest
@testable import codepet

/// The driver is one line of logic guarding a defect that is INVISIBLE to a suite
/// and audible to a human: drop the flush and every reply loses its last sentence,
/// silently. That asymmetry is the reason this file exists.
@MainActor
final class VoiceReplyDriverTests: XCTestCase {

    func testTheLastSentenceIsSpokenOnlyOnceStreamingStops() {
        var driver = VoiceReplyDriver()
        XCTAssertEqual(driver.sentencesToSpeak(replyText: "One. Two.", isStreaming: true),
                       ["One."], "mid-stream, 'Two.' may still be the head of 'Two.5 million'")
        XCTAssertEqual(driver.sentencesToSpeak(replyText: "One. Two.", isStreaming: false),
                       ["Two."], "the flush is the ONLY thing that releases the last sentence")
        XCTAssertEqual(driver.sentencesToSpeak(replyText: "One. Two.", isStreaming: false),
                       [], "flushing twice must not repeat it")
    }

    /// A second voice turn must not inherit the first one's progress. Without the
    /// reset, `emitted` still counts the previous reply's sentences and the new
    /// reply's opening sentences are skipped — the founder asks again and hears the
    /// answer start halfway through.
    func testResetLetsTheNextReplyStartFromItsFirstSentence() {
        var driver = VoiceReplyDriver()
        XCTAssertEqual(driver.sentencesToSpeak(replyText: "One. Two.", isStreaming: false),
                       ["One.", "Two."])
        driver.reset()
        XCTAssertEqual(driver.sentencesToSpeak(replyText: "Fresh. Reply.", isStreaming: false),
                       ["Fresh.", "Reply."], "reset must clear the sentence count")
    }
}

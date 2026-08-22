// codepet/Models/VoiceReplyDriver.swift
import Foundation

/// Turns "the reply text as it currently stands, and whether it is still arriving"
/// into the sentences to hand the synthesiser. One pure step, so the flush rule
/// below is testable rather than buried in a view closure.
///
/// **Why this exists as a named type for one line.** `SentenceSplitter.take` cannot
/// speak half a sentence — a terminator that is merely the last character currently
/// available is not proof the reply ended, so the final sentence is held back until
/// something says the stream is over. That something is `flush`, and omitting it is
/// the quietest defect in this feature: nothing throws, nothing logs, the suite stays
/// green, and every reply just stops one sentence short. Inline in a `.onChange`
/// closure no test could reach it. Here, `VoiceReplyDriverTests` goes red.
///
/// `flush` is also not safe to call speculatively — flush early, receive more text,
/// and the continuation is dropped — so the caller must make `isStreaming → false`
/// one-way and exactly once per reply.
struct VoiceReplyDriver {
    private var splitter = SentenceSplitter()

    init() {}

    /// The sentences not yet handed over. While streaming, complete ones only; once
    /// the stream has ended, everything still held back.
    mutating func sentencesToSpeak(replyText: String, isStreaming: Bool) -> [String] {
        isStreaming ? splitter.take(from: replyText) : splitter.flush(from: replyText)
    }

    /// Forget how far the previous reply got. Called when a new turn is sent: without
    /// it the splitter's sentence count still stands against the last reply, and the
    /// new reply's opening sentences are skipped as "already spoken".
    mutating func reset() { splitter.reset() }
}

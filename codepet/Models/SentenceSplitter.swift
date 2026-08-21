// codepet/Models/SentenceSplitter.swift
import Foundation

/// Decides what is newly speakable as a reply streams in — spec §5.
///
/// **The input is not chunks.** `CompanyStore` assigns
/// `chatMessages[i].text = streamedText` on every delta, so this is called
/// repeatedly with the SAME string, longer each time. It tracks how many
/// complete sentences it has already emitted and returns only the ones that
/// are new.
///
/// **Why a sentence COUNT and not a character offset.** `speakable()`
/// re-renders the WHOLE growing string on every call, and single-`*`/`_`
/// emphasis and `[text](url)` links need a CLOSING token before they can be
/// stripped. If an opener precedes a terminator that gets consumed in one
/// call, and its closer only arrives in a later call, the earlier text
/// shifts retroactively — a character offset recorded against the old
/// rendering would then point into the middle of the new one (found by
/// review: `"This is *bad. This is *worse* actually."` spoke `"This is
/// *bad."` with the asterisk still in it, and every offset after it was
/// wrong). A count of complete sentences survives that rewrite: the worst
/// case is one sentence spoken with a stray marker still in it — cosmetic —
/// instead of repeated or skipped audio.
///
/// Speaking half a sentence and then pausing sounds like a fault, which is
/// why an unterminated tail is always held back by `take`. That holdback
/// applies even at the very end of a reply: `take` sees only however much of
/// the string has streamed in so far, so it has no way to tell "the stream
/// paused right after this terminator" from "the reply is finished" — a
/// terminator that happens to be the last character currently available is
/// NOT proof the reply is over (found by review: streaming `"The price is
/// $3.14 today."` one character at a time made the period after "$3"
/// momentarily the last character available, and the old `atEnd` shortcut
/// spoke "$3." early). The true last sentence of a reply is only released
/// through `flush`.
struct SentenceSplitter {
    /// Sentences already returned, by COUNT — see the type doc for why not
    /// a character offset.
    private var emitted: Int = 0

    init() {}

    mutating func reset() { emitted = 0 }

    /// Complete sentences in `full` that have not been returned before. A
    /// terminator only ends a sentence when whitespace follows it in the
    /// rendered text — never because it happens to be the last character we
    /// currently have, since more of the stream may still be coming. Call
    /// `flush` once the stream is known to be over to release whatever
    /// `take` is still holding back.
    mutating func take(from full: String) -> [String] {
        let (sentences, _) = Self.split(Self.speakable(full))
        return Self.newSentences(from: sentences, emitted: &emitted)
    }

    /// Emits everything `take` has not already returned, INCLUDING a
    /// trailing unterminated fragment. Call this once the stream is known
    /// to be complete (`companyStore.isStreaming` going false) — without it
    /// the final sentence of every reply, which typically has nothing after
    /// its terminator to confirm it is finished, would never be spoken.
    mutating func flush(from full: String) -> [String] {
        let (sentences, tail) = Self.split(Self.speakable(full))
        var all = sentences
        if tail.count > 1 { all.append(tail) }
        return Self.newSentences(from: all, emitted: &emitted)
    }

    /// Sentences past `emitted`, advancing `emitted` to match.
    private static func newSentences(from all: [String], emitted: inout Int) -> [String] {
        guard all.count > emitted else { return [] }
        let fresh = Array(all[emitted...])
        emitted = all.count
        return fresh
    }

    private static let terminators: Set<Character> = [".", "!", "?", "\n"]

    /// Splits `text` into sentences whose terminator is followed by
    /// whitespace — definitely finished, not just currently the last
    /// character available — plus whatever unterminated fragment is left
    /// over at the end.
    private static func split(_ text: String) -> (sentences: [String], tail: String) {
        var out: [String] = []
        var current = ""
        var idx = text.startIndex
        while idx < text.endIndex {
            let ch = text[idx]
            current.append(ch)
            if terminators.contains(ch) {
                let next = text.index(after: idx)
                if next < text.endIndex, text[next].isWhitespace {
                    let trimmed = current.trimmingCharacters(in: .whitespacesAndNewlines)
                    if trimmed.count > 1 { out.append(trimmed) }
                    current = ""
                }
            }
            idx = text.index(after: idx)
        }
        let tail = current.trimmingCharacters(in: .whitespacesAndNewlines)
        return (out, tail)
    }

    /// Markdown rendered for the ear.
    ///
    /// Fenced code is removed rather than read: `func viewDidLoad() {` aloud is
    /// noise. An UNCLOSED fence — which every streaming reply has, briefly — drops
    /// everything from the fence onward, so prose before it still speaks and the
    /// code never does.
    static func speakable(_ raw: String) -> String {
        var s = raw

        // Fenced blocks first, so their contents never reach the other rules.
        s = s.replacingOccurrences(of: "```[\\s\\S]*?```", with: " ",
                                   options: .regularExpression)
        if let openFence = s.range(of: "```") { s = String(s[s.startIndex..<openFence.lowerBound]) }

        // Links become the word, not the URL.
        s = s.replacingOccurrences(of: "\\[([^\\]]+)\\]\\([^)]+\\)", with: "$1",
                                   options: .regularExpression)
        s = s.replacingOccurrences(of: "https?://[^\\s]+", with: "link",
                                   options: .regularExpression)

        // Emphasis, inline code, headings, list bullets.
        s = s.replacingOccurrences(of: "`", with: "")
        s = s.replacingOccurrences(of: "\\*\\*|__", with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: "(?<![A-Za-z0-9])[*_](?![A-Za-z0-9])", with: "",
                                   options: .regularExpression)
        s = s.replacingOccurrences(of: "\\*(\\S[^*]*?)\\*", with: "$1",
                                   options: .regularExpression)
        s = s.replacingOccurrences(of: "_(\\S[^_]*?)_", with: "$1",
                                   options: .regularExpression)
        s = s.replacingOccurrences(of: "(?m)^\\s{0,3}#{1,6}\\s*", with: "",
                                   options: .regularExpression)
        s = s.replacingOccurrences(of: "(?m)^\\s*[-*+]\\s+", with: "",
                                   options: .regularExpression)

        return s.replacingOccurrences(of: "[ \\t]{2,}", with: " ", options: .regularExpression)
    }
}

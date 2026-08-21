// codepet/Models/SentenceSplitter.swift
import Foundation

/// Decides what is newly speakable as a reply streams in — spec §5.
///
/// **The input is not chunks.** `CompanyStore` assigns
/// `chatMessages[i].text = streamedText` on every delta, so this is called
/// repeatedly with the SAME string, longer each time. It tracks how much it has
/// already emitted and returns only what has newly become a complete sentence.
///
/// Speaking half a sentence and then pausing sounds like a fault, which is why an
/// unterminated tail is always held back — even though that means the last sentence
/// of a reply only speaks once the stream ends with punctuation.
struct SentenceSplitter {
    /// Characters already emitted, counted against the SPEAKABLE rendering rather
    /// than the raw markdown, because the two lengths differ.
    private var consumed: Int = 0

    init() {}

    mutating func reset() { consumed = 0 }

    /// Complete sentences in `full` that have not been returned before.
    mutating func take(from full: String) -> [String] {
        let text = Self.speakable(full)
        guard text.count > consumed else { return [] }
        let fresh = String(text.dropFirst(consumed))

        var out: [String] = []
        var current = ""
        var emittedCount = 0
        var idx = fresh.startIndex
        while idx < fresh.endIndex {
            let ch = fresh[idx]
            current.append(ch)
            if Self.terminators.contains(ch) {
                // A terminator ends a sentence only when what follows is whitespace
                // or the end of what we have — otherwise "3.14" splits.
                let next = fresh.index(after: idx)
                let atEnd = next == fresh.endIndex
                let followedBySpace = !atEnd && fresh[next].isWhitespace
                if atEnd || followedBySpace {
                    let trimmed = current.trimmingCharacters(in: .whitespacesAndNewlines)
                    if trimmed.count > 1 { out.append(trimmed) }
                    emittedCount += current.count
                    current = ""
                }
            }
            idx = fresh.index(after: idx)
        }
        consumed += emittedCount
        return out
    }

    private static let terminators: Set<Character> = [".", "!", "?", "\n"]

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

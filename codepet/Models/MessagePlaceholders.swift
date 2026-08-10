// codepet/Models/MessagePlaceholders.swift
import SwiftUI

/// The blanks a drafted message still has in it — `[Name]`, `$[X]/month`, `{{company}}`.
///
/// A message deliverable differs from a document in one way that matters: you are meant to
/// paste it somewhere and send it, and it is not sendable while a placeholder is still in it.
/// The founder's Aug 10 reference (ChatGPT's email card) tints them for exactly that reason —
/// so the eye finds what must be filled in before the message leaves the app.
///
/// Pure text in, offsets out; the tinting itself lives in the viewers. Kept deliberately
/// conservative — a false positive paints ordinary prose yellow, which is worse than missing
/// one blank, so every rule below exists to reject something that merely looks like a
/// placeholder.
enum MessagePlaceholders {

    /// A placeholder is a label, not a sentence. Past this, `[` ... `]` is almost certainly
    /// bracketed prose (an aside, a citation block) rather than a blank to fill.
    static let maxLabelLength = 60

    /// Character offsets of every placeholder in `text`, in order, non-overlapping.
    ///
    /// Recognised: `[label]` and `{{label}}`. Rejected, each for its own reason:
    /// - `[label](url)` — a markdown link, not a blank
    /// - `[1]`, `[42]` — a footnote or citation reference
    /// - `[]`, `[   ]` — nothing to fill in
    /// - a `[` whose `]` is on a later line — unbalanced prose, not a label
    /// - anything longer than `maxLabelLength`
    static func spans(in text: String) -> [Range<Int>] {
        let chars = Array(text)
        var out: [Range<Int>] = []
        var i = 0

        while i < chars.count {
            if chars[i] == "{", i + 1 < chars.count, chars[i + 1] == "{" {
                if let end = close(chars, from: i + 2, terminator: "}", repeated: 2) {
                    if isFillable(chars, body: (i + 2)..<end) {
                        out.append(i..<(end + 2))
                        i = end + 2
                        continue
                    }
                }
            } else if chars[i] == "[" {
                if let end = close(chars, from: i + 1, terminator: "]", repeated: 1) {
                    let body = (i + 1)..<end
                    let followedByURL = end + 1 < chars.count && chars[end + 1] == "("
                    if isFillable(chars, body: body), !followedByURL, !isNumericReference(chars, body: body) {
                        out.append(i..<(end + 1))
                        i = end + 1
                        continue
                    }
                }
            }
            i += 1
        }
        return out
    }

    /// The distinct blanks, in first-appearance order, compared case-insensitively so
    /// `[Name]` and `[name]` count as one thing to fill in. This is what the viewer counts —
    /// a name repeated four times is one decision, not four.
    static func labels(in text: String) -> [String] {
        let chars = Array(text)
        var seen = Set<String>()
        var out: [String] = []
        for span in spans(in: text) {
            let raw = String(chars[span])
            let key = raw.lowercased()
            if seen.insert(key).inserted { out.append(raw) }
        }
        return out
    }

    /// Tints every placeholder in an already-parsed `AttributedString`.
    ///
    /// Takes the parsed string rather than the raw markdown on purpose: parsing removes
    /// `**` and `_` markers, which would shift every offset computed on the source.
    static func highlight(_ attr: inout AttributedString, tint: Color, ink: Color) {
        let plain = String(attr.characters)
        let count = attr.characters.count
        for span in spans(in: plain) {
            // `offsetByCharacters` traps past the end rather than returning nil, and the two
            // counts are only equal while `spans` reads the same string the attributes index.
            guard span.upperBound <= count else { continue }
            let lower = attr.index(attr.startIndex, offsetByCharacters: span.lowerBound)
            let upper = attr.index(attr.startIndex, offsetByCharacters: span.upperBound)
            attr[lower..<upper].backgroundColor = tint
            attr[lower..<upper].foregroundColor = ink
        }
    }

    // MARK: - Scanning

    /// The index of the first `terminator` (repeated `repeated` times) after `start`, on the
    /// same line and within `maxLabelLength`. Returns the index of the FIRST terminator char.
    private static func close(_ chars: [Character], from start: Int,
                              terminator: Character, repeated: Int) -> Int? {
        var j = start
        while j < chars.count, j - start <= maxLabelLength {
            let c = chars[j]
            if c.isNewline { return nil }
            if c == terminator {
                guard repeated > 1 else { return j }
                if j + 1 < chars.count, chars[j + 1] == terminator { return j }
            }
            j += 1
        }
        return nil
    }

    private static func isFillable(_ chars: [Character], body: Range<Int>) -> Bool {
        guard !body.isEmpty else { return false }
        return chars[body].contains { !$0.isWhitespace }
    }

    /// `[1]` / `[42]` is a footnote marker, and tinting it yellow in a message would be noise.
    private static func isNumericReference(_ chars: [Character], body: Range<Int>) -> Bool {
        chars[body].allSatisfy { $0.isNumber || $0.isWhitespace }
    }
}

extension MessagePlaceholders {
    /// Tints the blanks in PLAIN text, parsing nothing.
    ///
    /// Separate from `attributed(_:tint:ink:)` on purpose. The chat transcript renders its
    /// prose literally — `**` stays `**` — and quietly switching it to a markdown parser while
    /// adding the tint would be two changes wearing one coat.
    static func tinted(_ text: String, tint: Color, ink: Color) -> AttributedString {
        var attr = AttributedString(text)
        highlight(&attr, tint: tint, ink: ink)
        return attr
    }

    /// What the viewers actually call: parse inline markdown, then tint the blanks.
    ///
    /// Deliberately NOT an `AttributedString` static — that type is `@dynamicMemberLookup`
    /// over its attribute scopes, so a static named for an attribute resolves to the scope
    /// instead of the function and the call site fails to type-check.
    static func attributed(_ text: String, tint: Color, ink: Color) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace)
        var attr = (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
        highlight(&attr, tint: tint, ink: ink)
        return attr
    }
}

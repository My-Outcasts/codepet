// codepet/Models/DraftPreview.swift
import Foundation

/// Turns a deliverable's markdown body into the prose a card should preview.
///
/// `Text(d.body)` renders a runtime `String` literally — SwiftUI only parses markdown from
/// static string literals — so the chat's draft card was printing its own syntax: the founder
/// saw `# Codepet — Landing Page Copy` and `**Tab / SEO title:**` where the copy should be
/// (Aug 6). With a 3-line preview, one line went to a heading that merely repeated the card's
/// own title and another to `**` markers, leaving almost none of the writing the card exists
/// to show.
///
/// This is deliberately NOT a markdown renderer. It strips the syntax that shows up in
/// generated deliverables and leaves everything else alone, because a preview only has to read
/// as prose — the full document is one tap away in `DeliverableDetailView`.
enum DraftPreview {
    /// Plain prose for a preview, with a leading heading dropped when it only echoes `title`.
    ///
    /// The echo rule is scoped to the *leading* heading: a later section that happens to share
    /// the title's wording is real content and stays.
    static func plain(_ body: String, title: String = "") -> String {
        var out: [String] = []
        var seenContent = false

        for raw in body.split(separator: "\n", omittingEmptySubsequences: false) {
            var line = String(raw).trimmingCharacters(in: .whitespaces)

            if isHorizontalRule(line) { continue }

            let wasHeading = line.hasPrefix("#")
            line = strippingLinePrefix(line)
            line = strippingInline(line)

            // The title echo: only before any real content has been emitted.
            if wasHeading, !seenContent, !title.isEmpty, isSameHeading(line, title) { continue }

            if line.isEmpty {
                // Collapse runs of blank lines, and never open with one.
                if out.isEmpty || out.last?.isEmpty == true { continue }
            } else {
                seenContent = true
            }
            out.append(line)
        }

        while out.last?.isEmpty == true { out.removeLast() }
        return out.joined(separator: "\n")
    }

    // MARK: - Line-level markers

    /// `---`, `***`, `___` — a rule carries nothing in a preview.
    private static func isHorizontalRule(_ line: String) -> Bool {
        guard line.count >= 3 else { return false }
        return ["-", "*", "_"].contains { m in line.allSatisfy { String($0) == m } }
    }

    /// Heading (`##`), blockquote (`>`), bullet (`-`, `*`, `+`) and ordered (`1.`) markers.
    private static func strippingLinePrefix(_ line: String) -> String {
        var s = Substring(line)
        while let f = s.first, f == "#" || f == ">" { s = s.dropFirst() }
        s = s.drop(while: { $0 == " " })

        if let f = s.first, f == "-" || f == "*" || f == "+" {
            let after = s.dropFirst()
            // A marker only counts as a bullet when a space follows it, so `*bold*` at the
            // start of a line is left for the inline pass rather than eaten as a bullet.
            if after.first == " " { s = after.drop(while: { $0 == " " }) }
        } else {
            let digits = s.prefix(while: { $0.isNumber })
            let rest = s.dropFirst(digits.count)
            if !digits.isEmpty, rest.first == ".", rest.dropFirst().first == " " {
                s = rest.dropFirst().drop(while: { $0 == " " })
            }
        }
        return String(s)
    }

    // MARK: - Inline markers

    private static func strippingInline(_ line: String) -> String {
        var s = line
        s = convertingLinks(s)
        for marker in ["**", "__"] { s = s.replacingOccurrences(of: marker, with: "") }
        s = s.replacingOccurrences(of: "`", with: "")
        s = strippingPairedAsterisks(s)
        return s.trimmingCharacters(in: .whitespaces)
    }

    /// `[label](url)` and `![label](url)` collapse to `label`.
    private static func convertingLinks(_ line: String) -> String {
        var out = ""
        var rest = Substring(line)
        while let open = rest.firstIndex(of: "[") {
            guard let close = rest[open...].firstIndex(of: "]"),
                  rest.index(after: close) < rest.endIndex,
                  rest[rest.index(after: close)] == "(",
                  let paren = rest[close...].firstIndex(of: ")")
            else { break }
            var head = rest[..<open]
            if head.last == "!" { head = head.dropLast() }   // image
            out += head + rest[rest.index(after: open)..<close]
            rest = rest[rest.index(after: paren)...]
        }
        return out + rest
    }

    /// Single-`*` emphasis, removed only as a matched pair that hugs its text.
    ///
    /// `_` is deliberately left alone: stripping it would corrupt `snake_case` identifiers,
    /// which appear in engineering deliverables far more often than `_italics_` does.
    private static func strippingPairedAsterisks(_ line: String) -> String {
        var chars = Array(line)
        var opens: [Int] = []
        var drop = Set<Int>()
        for (i, c) in chars.enumerated() where c == "*" {
            let prev = i > 0 ? chars[i - 1] : " "
            let next = i + 1 < chars.count ? chars[i + 1] : " "
            if let open = opens.last, prev != " " {          // closing: text then marker
                drop.insert(open); drop.insert(i); opens.removeLast()
            } else if next != " " {                          // opening: marker then text
                opens.append(i)
            }
        }
        guard !drop.isEmpty else { return line }
        chars = chars.enumerated().filter { !drop.contains($0.offset) }.map(\.element)
        return String(chars)
    }

    // MARK: - Title comparison

    /// Compares on letters and digits only, so `# Codepet — Landing Page Copy` is recognised
    /// as an echo of the title `Codepet Landing Page Copy` despite the em dash.
    private static func isSameHeading(_ heading: String, _ title: String) -> Bool {
        func key(_ s: String) -> String {
            s.lowercased().unicodeScalars
                .filter { CharacterSet.alphanumerics.contains($0) }
                .map(String.init).joined()
        }
        let h = key(heading)
        return !h.isEmpty && h == key(title)
    }
}

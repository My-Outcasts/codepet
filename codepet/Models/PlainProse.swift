import Foundation

/// Turns a Markdown body into plain prose for places that render text as-is —
/// list previews, titles, sidebar labels.
///
/// The chat transcript and every card preview show their string literally (the app
/// has no Markdown renderer), so a deliverable body written by the model arrives
/// with its syntax intact: the Library was showing `**Palette**` and `` `#1f1b15` ``
/// verbatim in every preview.
///
/// Hoisted out of `ReflectionTab`'s private copy so there is one implementation.
enum PlainProse {

    /// Strips inline Markdown markers — emphasis, code ticks, leading heading and
    /// quote marks, and list bullets — leaving the words.
    ///
    /// Deliberately NOT a Markdown parser: these previews are one or two lines of
    /// prose, and a parser would be a much larger dependency for the same result.
    /// Link text is kept and the URL dropped, since a preview cannot be clicked.
    static func strip(_ s: String) -> String {
        var out = s

        // `[label](url)` -> `label`, before the brackets are stripped as punctuation.
        out = out.replacingOccurrences(
            of: #"\[([^\]]*)\]\([^)]*\)"#,
            with: "$1",
            options: .regularExpression)

        out = out
            .replacingOccurrences(of: "*", with: "")
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: "`", with: "")
            .replacingOccurrences(of: "~", with: "")

        // Leading block markers: heading hashes, quote carets, and list bullets,
        // including an indented or numbered one ("  - ", "1. ").
        out = out.replacingOccurrences(
            of: #"(?m)^[ \t]*(?:[#>]+[ \t]*|[-+•][ \t]+|\d+\.[ \t]+)"#,
            with: "",
            options: .regularExpression)

        // A run of dashes left by a horizontal rule reads as noise mid-sentence.
        out = out.replacingOccurrences(
            of: #"(?m)^[ \t]*-{3,}[ \t]*$"#,
            with: "",
            options: .regularExpression)

        // Collapse the whitespace the removals leave behind, newlines included, so a
        // two-line preview joins into one readable line.
        out = out.replacingOccurrences(
            of: #"[ \t\r\n]+"#,
            with: " ",
            options: .regularExpression)

        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

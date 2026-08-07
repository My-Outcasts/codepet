// codepet/Models/ModelText.swift
import Foundation

/// Strips tool-call markup that leaked out of the model and into a content field.
///
/// Seen in the reader on Aug 7: the "Do this next" section opened with
/// `<parameter name="action">Write the one-sentence value prop…`. The model emitted a fragment of
/// its own tool-call syntax inside `next_action.action`, the Cloud Function stored it verbatim, and
/// the client rendered it as prose.
///
/// The real fix belongs upstream — the CF should not persist a field that still contains tool
/// syntax — but the client is where the founder sees it, and rendering the app's own plumbing to
/// her is worse than a defensive strip. Same reasoning as `DraftPreview`.
///
/// Deliberately conservative: only tags from a known list of tool-call names are removed. A
/// blanket "delete anything in angle brackets" would eat `if x < y` and `<html>` out of an
/// engineering deliverable, which is a worse failure than leaving one stray tag.
enum ModelText {

    /// Tool-call tag names that have no business in founder-facing prose.
    private static let toolTags = [
        "parameter", "invoke", "function_calls", "function_results", "antml:parameter",
        "antml:invoke", "antml:function_calls",
    ]

    static func stripToolMarkup(_ text: String) -> String {
        var out = text
        for tag in toolTags {
            out = removingTags(named: tag, from: out)
        }
        // Collapse the blank space a removed tag can leave mid-sentence, without touching the
        // paragraph breaks the document relies on for structure.
        while out.contains("  ") { out = out.replacingOccurrences(of: "  ", with: " ") }
        return out.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
    }

    /// Removes `<tag …>` and `</tag>` for one exact tag name. Scans rather than using a regex so
    /// the match stays anchored to the name — `<parameters>` and `<paramX>` are left alone.
    private static func removingTags(named tag: String, from text: String) -> String {
        var out = ""
        var rest = Substring(text)
        while let open = rest.firstIndex(of: "<") {
            out += rest[..<open]
            let after = rest[rest.index(after: open)...]
            let isClose = after.first == "/"
            let nameStart = isClose ? after.dropFirst() : after
            // The tag name must be followed by a space, a `>` or a `/` — otherwise this is a
            // different tag that merely starts with the same letters.
            let matches = nameStart.hasPrefix(tag) && {
                let next = nameStart.dropFirst(tag.count).first
                return next == nil || next == " " || next == ">" || next == "/"
            }()
            guard matches, let close = rest[open...].firstIndex(of: ">") else {
                out.append("<")
                rest = rest[rest.index(after: open)...]
                continue
            }
            rest = rest[rest.index(after: close)...]
        }
        return out + rest
    }
}

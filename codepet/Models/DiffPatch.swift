import Foundation

/// One rendered line of a unified diff.
///
/// Carries its line NUMBERS, not just its text, and that is the point. Inline
/// line comments are the first thing after freeze (design §10), and a comment
/// attaches to `file:line` — so the number has to exist from the first render
/// or the diff renderer gets rewritten to add it. Nothing reads `newLine` yet.
struct DiffLine: Identifiable, Equatable {
    enum Kind: Equatable {
        /// `@@ -1,3 +1,4 @@` — a jump in the file, not a change.
        case hunk
        case context
        case added
        case removed
    }

    let kind: Kind
    let text: String
    /// Line number in the file BEFORE the change; nil for an added line.
    let oldLine: Int?
    /// Line number in the file AFTER the change; nil for a removed line.
    let newLine: Int?

    /// Stable within one file's parse. Index-based rather than derived from the
    /// line numbers, because a hunk header has neither and two hunks can repeat
    /// a number after a jump.
    let id: Int

    /// Where a future comment would attach: the post-change line where one
    /// exists, otherwise the pre-change line. nil for a hunk header, which is
    /// not a line of the file at all.
    var commentAnchor: Int? { newLine ?? oldLine }
}

enum DiffPatch {
    /// GitHub's unified patch → renderable lines.
    ///
    /// Deliberately tolerant. A patch is generated text from another system, and
    /// the failure this avoids is a founder seeing an empty pane because one
    /// header did not match a regex: an unparseable hunk header still renders as
    /// a `.hunk` row, and a line with no recognised prefix renders as context.
    /// Showing something slightly wrong beats showing nothing at all — but note
    /// the counting is only correct while the headers parse, which is why the
    /// header is where the strictness lives.
    static func parse(_ patch: String?) -> [DiffLine] {
        guard let patch, !patch.isEmpty else { return [] }
        var lines: [DiffLine] = []
        var oldCursor = 0
        var newCursor = 0
        var id = 0

        for raw in patch.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(raw)
            defer { id += 1 }

            if line.hasPrefix("@@") {
                if let (oldStart, newStart) = parseHunkHeader(line) {
                    oldCursor = oldStart
                    newCursor = newStart
                }
                lines.append(DiffLine(kind: .hunk, text: line, oldLine: nil, newLine: nil, id: id))
                continue
            }

            // "\ No newline at end of file" is a note about the previous line,
            // not a line of the file. Counting it would shift every number
            // after it by one.
            if line.hasPrefix("\\") {
                lines.append(DiffLine(kind: .context, text: line, oldLine: nil, newLine: nil, id: id))
                continue
            }

            let body = line.isEmpty ? "" : String(line.dropFirst())
            switch line.first {
            case "+":
                lines.append(DiffLine(kind: .added, text: body, oldLine: nil, newLine: newCursor, id: id))
                newCursor += 1
            case "-":
                lines.append(DiffLine(kind: .removed, text: body, oldLine: oldCursor, newLine: nil, id: id))
                oldCursor += 1
            default:
                // A context line starts with a space; an unrecognised one is
                // treated the same rather than dropped.
                let text = line.first == " " ? body : line
                lines.append(DiffLine(kind: .context, text: text, oldLine: oldCursor, newLine: newCursor, id: id))
                oldCursor += 1
                newCursor += 1
            }
        }
        return lines
    }

    /// `@@ -12,7 +12,9 @@ optional context` → the two starting line numbers.
    ///
    /// The counts after the commas are deliberately ignored: they describe how
    /// many lines the hunk spans, which the loop above discovers by walking it.
    /// Trusting them instead would put every later line number wrong whenever a
    /// patch is truncated mid-hunk, which GitHub does at its size cap.
    static func parseHunkHeader(_ header: String) -> (old: Int, new: Int)? {
        // Two runs of digits, the first after "-" and the second after "+".
        guard let minus = header.range(of: "-"), let plus = header.range(of: "+") else { return nil }
        func number(from index: String.Index) -> Int? {
            let rest = header[index...].dropFirst()
            let digits = rest.prefix { $0.isNumber }
            return digits.isEmpty ? nil : Int(digits)
        }
        guard let old = number(from: minus.lowerBound), let new = number(from: plus.lowerBound) else {
            return nil
        }
        return (old, new)
    }
}

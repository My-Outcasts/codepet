// codepet/Models/MarkdownBlocks.swift
import Foundation

/// A parsed markdown block — the minimal set for deliverable bodies.
enum MarkdownBlock: Equatable {
    case heading(level: Int, text: String)
    case bullet(String)
    case paragraph(String)
    /// A GFM pipe table. Cells are raw inline markdown (the renderer handles `**` etc.);
    /// every row is padded or truncated to the header's column count.
    case table(header: [String], alignments: [MarkdownTableAlignment], rows: [[String]])
}

/// Column alignment from a table's separator row: `---` / `:---` leading, `:---:` center,
/// `---:` trailing.
enum MarkdownTableAlignment: Equatable {
    case leading, center, trailing
}

/// Pure line-based markdown → blocks. Headings (# / ## / ###), bullets (- / *), pipe tables,
/// and paragraphs (consecutive non-blank lines joined; a blank line flushes).
///
/// Tables were missing, and they are what the model reaches for whenever a deliverable has
/// numbers in it: on 24 Sep every cost and margin table in a unit-economics sheet rendered as
/// one run-on paragraph of pipes, because each row fell through to `.paragraph` and got joined
/// to the next with a space. A table is a line containing `|` followed by a separator row
/// (`|---|:---:|`) with the same number of cells — the GFM rule. Without that separator a line
/// with pipes is still prose, so "a | b" in a sentence is not turned into a grid.
enum MarkdownBlocks {
    static func parse(_ md: String) -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        var para: [String] = []
        func flush() {
            if !para.isEmpty {
                blocks.append(.paragraph(para.joined(separator: " ")))
                para = []
            }
        }
        // Trim newlines too so a CRLF-sourced body doesn't leave a trailing \r.
        func content(_ s: Substring) -> String {
            s.trimmingCharacters(in: .whitespaces)
        }
        let lines = md.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        var i = 0
        while i < lines.count {
            let line = lines[i]
            i += 1
            if line.isEmpty { flush(); continue }
            if line.contains("|"), i < lines.count,
               let alignments = separatorAlignments(lines[i]),
               alignments.count == tableCells(line).count {
                flush()
                let header = tableCells(line)
                var rows: [[String]] = []
                i += 1  // past the separator
                // A row is any following line with a pipe; a blank or pipe-free line ends it.
                while i < lines.count, lines[i].contains("|") {
                    rows.append(fitted(tableCells(lines[i]), to: header.count))
                    i += 1
                }
                blocks.append(.table(header: header, alignments: alignments, rows: rows))
                continue
            }
            if line.hasPrefix("### ") {
                flush(); blocks.append(.heading(level: 3, text: content(line.dropFirst(4))))
            } else if line.hasPrefix("## ") {
                flush(); blocks.append(.heading(level: 2, text: content(line.dropFirst(3))))
            } else if line.hasPrefix("# ") {
                flush(); blocks.append(.heading(level: 1, text: content(line.dropFirst(2))))
            } else if line.hasPrefix("- ") || line.hasPrefix("* ") {
                flush(); blocks.append(.bullet(content(line.dropFirst(2))))
            } else {
                para.append(line)
            }
        }
        flush()
        return blocks
    }

    /// Splits a row into trimmed cells: optional outer pipes dropped, `\|` kept as a literal
    /// pipe inside the cell rather than read as a divider.
    private static func tableCells(_ line: String) -> [String] {
        var s = Substring(line)
        if s.hasPrefix("|") { s = s.dropFirst() }
        if s.hasSuffix("|") && !s.hasSuffix("\\|") { s = s.dropLast() }
        var cells: [String] = []
        var cell = ""
        var escaped = false
        for ch in s {
            if escaped {
                cell.append(ch == "|" ? "|" : "\\\(ch)")
                escaped = false
            } else if ch == "\\" {
                escaped = true
            } else if ch == "|" {
                cells.append(cell.trimmingCharacters(in: .whitespaces))
                cell = ""
            } else {
                cell.append(ch)
            }
        }
        if escaped { cell.append("\\") }
        cells.append(cell.trimmingCharacters(in: .whitespaces))
        return cells
    }

    /// The column alignments if `line` is a separator row (`|---|:--:|--:|`), else nil.
    private static func separatorAlignments(_ line: String) -> [MarkdownTableAlignment]? {
        guard line.contains("-") else { return nil }
        let cells = tableCells(line)
        var out: [MarkdownTableAlignment] = []
        for cell in cells {
            let dashes = cell.trimmingCharacters(in: CharacterSet(charactersIn: ":"))
            guard !dashes.isEmpty, dashes.allSatisfy({ $0 == "-" }) else { return nil }
            switch (cell.hasPrefix(":"), cell.hasSuffix(":")) {
            case (true, true): out.append(.center)
            case (false, true): out.append(.trailing)
            default: out.append(.leading)
            }
        }
        return out
    }

    private static func fitted(_ cells: [String], to count: Int) -> [String] {
        cells.count >= count ? Array(cells.prefix(count))
                             : cells + Array(repeating: "", count: count - cells.count)
    }
}

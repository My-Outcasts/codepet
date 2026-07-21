// codepet/Models/MarkdownBlocks.swift
import Foundation

/// A parsed markdown block — the minimal set for deliverable bodies.
enum MarkdownBlock: Equatable {
    case heading(level: Int, text: String)
    case bullet(String)
    case paragraph(String)
}

/// Pure line-based markdown → blocks. Headings (# / ## / ###), bullets (- / *),
/// and paragraphs (consecutive non-blank lines joined; a blank line flushes).
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
        for rawLine in md.components(separatedBy: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty { flush(); continue }
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
}

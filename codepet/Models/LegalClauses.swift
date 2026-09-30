// codepet/Models/LegalClauses.swift
import Foundation

/// A `.legal` deliverable's clauses, numbered — the one place the numbering is decided, so the
/// viewer, the exported `.md` and a Team Build's `docs/` file cannot disagree about it.
///
/// `legal` carried no structured payload until CP-002 A: the schema documented `sections` as
/// "doc/legal", the prompt never asked Legal to fill it, and the server dropped it anyway. Now the
/// server keeps it with the model's own numbering stripped ("1. Definitions" → "Definitions"), so
/// the number is added here and only here.
///
/// `nil` means "render the body" — a legal deliverable filed before CP-002 A, or one whose clauses
/// did not survive coercion. That is every legal draft already in a founder's Library, so the
/// fallback is the common case for now, not an edge.
enum LegalClauses {

    static func of(_ d: Deliverable) -> [DocSection]? {
        d.kind == .legal ? clauses(in: d.payload) : nil
    }

    /// The payload half of `of(_:)`, for a caller that has already switched on the kind.
    static func clauses(in payload: DeliverablePayload?) -> [DocSection]? {
        guard let sections = payload?.sections?.filter({ !$0.h.isEmpty && !$0.p.isEmpty }),
              !sections.isEmpty else { return nil }
        return sections
    }

    /// "1. Definitions" — the heading as the founder reads it.
    static func heading(_ index: Int, _ section: DocSection) -> String {
        "\(index + 1). \(section.h)"
    }

    /// The clauses as Markdown, each under a numbered `##` heading.
    static func markdown(_ sections: [DocSection]) -> String {
        sections.enumerated()
            .map { "## \(heading($0.offset, $0.element))\n\n\($0.element.p)" }
            .joined(separator: "\n\n")
    }

    /// The clauses as pasteable prose — what Copy puts on the clipboard, in the order it is shown.
    static func plainText(_ sections: [DocSection]) -> String {
        sections.enumerated()
            .map { "\(heading($0.offset, $0.element))\n\($0.element.p)" }
            .joined(separator: "\n\n")
    }
}

// codepet/Models/DeliverableExport.swift
import Foundation

/// One file the founder is about to save: a filename and its bytes.
struct ExportFile {
    let name: String
    let data: Data
}

/// Turns a `Deliverable` into files on disk.
///
/// **Pure on purpose.** No AppKit, no view, no `NSSavePanel` — those live in
/// `DeliverableExporter`, the same split `AttachmentPicker` states for the panel it owns.
/// A viewer cannot be asserted on; this can, so every kind's rendering is a unit test.
///
/// `files(for:)` never returns an empty array. A kind whose payload is missing or malformed
/// falls back to the markdown `body`, because `body` is always written — the generator's
/// prompt says "ALWAYS write the markdown `body`" — and a founder pressing Export must never
/// get nothing.
enum DeliverableExport {

    /// A filename the filesystem will accept, from a title that may contain anything.
    ///
    /// Diacritics are FOLDED, not dropped: a Vietnamese title stripped of its accents is
    /// still recognisable ("ke-hoach-ra-mat"), whereas dropping the characters leaves "".
    static func slug(_ title: String, fallback: String = "deliverable") -> String {
        let folded = title.folding(options: [.diacriticInsensitive, .caseInsensitive],
                                  locale: Locale(identifier: "en_US"))
        var out = ""
        var lastWasDash = false
        for ch in folded {
            if ch.isASCII && (ch.isLetter || ch.isNumber) {
                out.append(ch)
                lastWasDash = false
            } else if !lastWasDash && !out.isEmpty {
                out.append("-")
                lastWasDash = true
            }
        }
        while out.hasSuffix("-") { out.removeLast() }
        return out.isEmpty ? fallback : out
    }

    static func files(for d: Deliverable) -> [ExportFile] {
        let base = slug(d.title)
        switch d.kind {
        case .doc:
            return [md(base, docMarkdown(d))]
        case .checklist:
            return [md(base, checklistMarkdown(d))]
        case .plan:
            return [md(base, planMarkdown(d))]
        case .legal, .text, .other, .post, .email, .dms, .sheet, .calendar, .site, .screens:
            // Extended by later tasks; every one of these is markdown-safe today.
            return [md(base, titled(d, d.body))]
        }
    }

    // MARK: - builders

    private static func md(_ base: String, _ text: String) -> ExportFile {
        ExportFile(name: "\(base).md", data: Data(text.utf8))
    }

    private static func titled(_ d: Deliverable, _ body: String) -> String {
        "# \(d.title)\n\n\(body)\n"
    }

    private static func docMarkdown(_ d: Deliverable) -> String {
        guard let p = d.payload, let call = p.call, !call.isEmpty else {
            return titled(d, d.body)
        }
        var out = "# \(d.title)\n\n\(call)\n"
        for s in p.sections ?? [] {
            out += "\n## \(s.h)\n\n\(s.p)\n"
        }
        let next = p.next ?? []
        if !next.isEmpty {
            out += "\n## Next\n\n"
            for n in next { out += "- \(n)\n" }
        }
        return out
    }

    private static func checklistMarkdown(_ d: Deliverable) -> String {
        guard let items = d.payload?.items, !items.isEmpty else { return titled(d, d.body) }
        var out = "# \(d.title)\n\n"
        for i in items { out += "- [\(i.done ? "x" : " ")] \(i.t)\n" }
        return out
    }

    private static func planMarkdown(_ d: Deliverable) -> String {
        guard let p = d.payload, let goal = p.goal, !goal.isEmpty else {
            return titled(d, d.body)
        }
        var out = "# \(d.title)\n\n\(goal)\n"
        let steps = p.steps ?? []
        if !steps.isEmpty {
            out += "\n## Steps\n\n"
            for (i, s) in steps.enumerated() { out += "\(i + 1). \(s)\n" }
        }
        let changes = p.changes ?? []
        if !changes.isEmpty {
            out += "\n## Changes\n\n"
            for c in changes { out += "- **\(c.area)** — \(c.edit)\n" }
        }
        let verify = p.verify ?? []
        if !verify.isEmpty {
            out += "\n## Verify\n\n"
            for v in verify { out += "- \(v)\n" }
        }
        if let r = p.risks, !r.isEmpty { out += "\n## Risk\n\n\(r)\n" }
        return out
    }
}

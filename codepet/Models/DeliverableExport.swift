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
        case .post, .email:
            return [txt(base, d.body)]
        case .dms:
            return dmsFiles(d, base: base)
        case .sheet:
            return [sheetFile(d, base: base)]
        case .legal, .text, .other, .calendar, .site, .screens:
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

    private static func txt(_ base: String, _ text: String) -> ExportFile {
        ExportFile(name: "\(base).txt", data: Data((text + "\n").utf8))
    }

    /// One file per message. A `dms` deliverable is four different conversations, and a
    /// single file would make the founder cut them apart by hand before sending any.
    ///
    /// The `note` is kept in the file. It is the reason this person is worth writing to,
    /// and it is the part the founder needs in front of them when they personalise the
    /// message — dropping it would export the words and lose the intent.
    private static func dmsFiles(_ d: Deliverable, base: String) -> [ExportFile] {
        let messages = d.payload?.messages ?? []
        guard !messages.isEmpty else { return [txt(base, d.body)] }
        return messages.enumerated().map { i, m in
            let who = slug(m.name, fallback: "recipient")
            let text = "To: \(m.name)\nWhy: \(m.note)\n\n\(m.msg)"
            return ExportFile(name: "\(base)-\(i + 1)-\(who).txt", data: Data((text + "\n").utf8))
        }
    }

    /// A model, not a number. The inputs carry their ranges so the reader can see what the
    /// author considered plausible, and the outputs carry their formulas so the reader can
    /// disagree with the derivation rather than only with the result.
    ///
    /// The two derived rows mirror `SheetViewer`'s own arithmetic. They are recomputed here
    /// rather than read off the view, because export must work on a deliverable that is not
    /// on screen.
    private static func sheetFile(_ d: Deliverable, base: String) -> ExportFile {
        guard let s = d.payload?.sheet else {
            return md(base, titled(d, d.body))
        }
        func n(_ v: Double) -> String {
            v == v.rounded() ? String(Int(v)) : String(format: "%.4g", v)
        }
        func row(_ name: String, _ i: SheetInput) -> String {
            "\(name),\(n(i.val)),\(n(i.min)),\(n(i.max)),\(n(i.step))\n"
        }

        var out = "input,value,min,max,step\n"
        out += row("price", s.price)
        out += row("waitlist", s.waitlist)
        out += row("conversion", s.conversion)
        out += row("churn", s.churn)

        let subscribers = (s.waitlist.val * s.conversion.val / 100).rounded()
        let mrr = subscribers * s.price.val
        out += "\noutput,value,formula\n"
        out += "subscribers,\(n(subscribers)),waitlist * conversion / 100\n"
        out += "mrr,\(n(mrr)),subscribers * price\n"

        if let summary = s.summary, !summary.isEmpty {
            out += "\nsummary,\(csvQuoted(summary))\n"
        }
        return ExportFile(name: "\(base).csv", data: Data(out.utf8))
    }

    /// A CSV field that may contain a comma, a quote or a newline. Without this a summary
    /// sentence silently becomes several columns.
    private static func csvQuoted(_ s: String) -> String {
        "\"\(s.replacingOccurrences(of: "\"", with: "\"\""))\""
    }
}

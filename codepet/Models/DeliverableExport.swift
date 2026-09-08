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
        case .calendar:
            return calendarFiles(d, base: base)
        case .site:
            return [siteFile(d, base: base)]
        case .legal, .text, .other, .screens:
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

    /// Two files, because a content calendar is read two ways: as a table to edit, and as
    /// events to drop into the calendar the founder actually lives in.
    ///
    /// **The .ics carries no dates.** `CalendarItem.day` is "Mon", not 2026-09-14 — the
    /// generator produces a relative schedule, and inventing absolute dates would be
    /// inventing data (the rule `PostViewer` states: never render what the app does not
    /// know). Each event is therefore an all-day VEVENT on a floating day counted from the
    /// export date, and the description says so. A founder who wants real dates moves them
    /// once, in their own calendar.
    private static func calendarFiles(_ d: Deliverable, base: String) -> [ExportFile] {
        guard let weeks = d.payload?.calendar?.weeks, !weeks.isEmpty else {
            return [md(base, titled(d, d.body))]
        }

        var csv = "week,day,kind,body\n"
        for w in weeks {
            for i in w.items {
                csv += "\(csvQuoted(w.label)),\(csvQuoted(i.day)),\(csvQuoted(i.kind)),\(csvQuoted(i.body))\n"
            }
        }
        // Plain values read better than quoted ones where the field cannot contain a comma,
        // but week/day/kind are model-authored strings and can. Quote them all; a reader
        // never sees the difference and a stray comma cannot shift a column.

        var ics = "BEGIN:VCALENDAR\r\nVERSION:2.0\r\nPRODID:-//Murror//Codepet//EN\r\n"
        var n = 0
        for (wi, w) in weeks.enumerated() {
            for i in w.items {
                n += 1
                let day = icsDate(weekIndex: wi, dayLabel: i.day)
                ics += "BEGIN:VEVENT\r\n"
                ics += "UID:\(d.id)-\(n)@codepet.murror.app\r\n"
                ics += "DTSTART;VALUE=DATE:\(day)\r\n"
                ics += "SUMMARY:\(icsEscaped(i.body))\r\n"
                ics += "DESCRIPTION:\(icsEscaped("\(w.label) · \(i.kind) — day is relative to export"))\r\n"
                ics += "END:VEVENT\r\n"
            }
        }
        ics += "END:VCALENDAR\r\n"

        return [ExportFile(name: "\(base).csv", data: Data(csv.utf8)),
                ExportFile(name: "\(base).ics", data: Data(ics.utf8))]
    }

    /// One `.html` file, ready to open in a browser or drop on a host.
    ///
    /// **Reuses `SiteViewer.buildHTML`.** The spec called for an ".html folder"; a single
    /// self-contained document satisfies the intent with less machinery, because the builder
    /// already inlines its own styles — there are no sibling assets to place beside it.
    /// Sharing the builder is the load-bearing part: a second renderer here could drift from
    /// the page the founder looked at and approved.
    private static func siteFile(_ d: Deliverable, base: String) -> ExportFile {
        guard let site = d.payload?.site else {
            return md(base, titled(d, d.body))
        }
        return ExportFile(name: "\(base).html", data: Data(SiteViewer.buildHTML(site).utf8))
    }

    /// A floating all-day date: today, plus the week offset, plus the weekday the label names.
    /// An unrecognised label lands on the Monday of its week rather than failing the export.
    private static func icsDate(weekIndex: Int, dayLabel: String) -> String {
        let offsets = ["mon": 0, "tue": 1, "wed": 2, "thu": 3, "fri": 4, "sat": 5, "sun": 6]
        let key = dayLabel.lowercased().prefix(3)
        let within = offsets[String(key)] ?? 0
        let days = weekIndex * 7 + within
        // Arithmetic must use the same time zone as the formatter (UTC) to avoid emitting
        // a day that is off by one near midnight on local timezone boundaries.
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        let date = cal.date(byAdding: .day, value: days, to: Date()) ?? Date()
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyyMMdd"
        fmt.timeZone = TimeZone(identifier: "UTC")
        return fmt.string(from: date)
    }

    /// RFC 5545 text escaping: backslash, semicolon, comma and newline.
    private static func icsEscaped(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: ";", with: "\\;")
            .replacingOccurrences(of: ",", with: "\\,")
            .replacingOccurrences(of: "\n", with: "\\n")
    }
}

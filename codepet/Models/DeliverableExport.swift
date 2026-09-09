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

    /// `locale` is the seam that makes the `.ics` date formatting testable: it is the locale
    /// the formatters would otherwise inherit from the process. Production passes `.current`.
    static func files(for d: Deliverable, locale: Locale = .current) -> [ExportFile] {
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
            return calendarFiles(d, base: base, locale: locale)
        case .site:
            return [siteFile(d, base: base)]
        // `.screens` sits here deliberately: a `.png` per screen needs `ImageRenderer` over a
        // live view, which is a separate plan. Until then `.screens` exports its markdown
        // `body`, same as `.legal`/`.text`/`.other` — the per-screen fields are intentionally
        // not in the file.
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
    /// **The six output rows come from `SheetModel.compute`, the same pure model
    /// `SheetViewer` renders on screen.** This file used to hand-derive `subscribers`/`mrr`
    /// itself, which meant the CSV could disagree with the viewer — `SheetModel` floors
    /// `price` at 1 and `churn` at 1%, so e.g. a `price` of 0 shows a non-zero MRR on screen
    /// while the old hand arithmetic wrote `mrr,0`. Calling the model instead buys the CSV
    /// the same one-renderer guarantee `testExportedHtmlIsByteIdenticalToWhatTheViewerRenders`
    /// buys the site export, and stops the file quietly dropping four of the six figures the
    /// founder reads (`arr`, `ltv`, `life`, `breakeven`).
    private static func sheetFile(_ d: Deliverable, base: String) -> ExportFile {
        guard let s = d.payload?.sheet else {
            return md(base, titled(d, d.body))
        }
        func row(_ name: String, _ i: SheetInput) -> String {
            "\(name),\(n(i.val)),\(n(i.min)),\(n(i.max)),\(n(i.step))\n"
        }

        var out = "input,value,min,max,step\n"
        out += row("price", s.price)
        out += row("waitlist", s.waitlist)
        out += row("conversion", s.conversion)
        out += row("churn", s.churn)

        let m = SheetModel.compute(price: s.price.val, waitlist: s.waitlist.val,
                                    conversion: s.conversion.val, churn: s.churn.val)
        out += "\noutput,value,formula\n"
        out += "paid,\(n(Double(m.paid))),round(waitlist * conversion / 100)\n"
        out += "mrr,\(n(m.mrr)),paid * price (price floored at 1)\n"
        out += "arr,\(n(m.arr)),mrr * 12\n"
        out += "ltv,\(n(Double(m.ltv))),round(price / (churn / 100)) (price floored at 1; churn floored at 1%)\n"
        out += "life,\(n(Double(m.life))),round(1 / (churn / 100)) (churn floored at 1%)\n"
        out += "breakeven,\(n(Double(m.breakeven))),ceil(2500 / price) (price floored at 1)\n"

        if let summary = s.summary, !summary.isEmpty {
            out += "\nsummary,\(csvQuoted(summary))\n"
        }
        return ExportFile(name: "\(base).csv", data: Data(out.utf8))
    }

    /// A CSV number: whole values print without a decimal, and everything else prints in
    /// fixed-decimal form. **Never `%g`** — `%.4g` renders `9999.99` as `"1e+04"`, which for a
    /// currency cell (`mrr`) does not reformat the value, it destroys it. Two decimal places
    /// is right for currency and loses no significant digit a founder would read.
    private static func n(_ v: Double) -> String {
        // `Int(_ Double)` TRAPS on non-finite input and on anything past `Int.max`, and these
        // values arrive straight from the model-generated payload with no magnitude guard —
        // so the old `String(Int(v))` hard-crashed the app the moment the founder pressed
        // Export on a slider bound like `1e19`. `SheetModel.compute` guards its own input;
        // this formatter guarded neither.
        //
        // A non-finite bound is not a number a founder can read, so the cell is left EMPTY
        // rather than printing "inf" or inventing a 0 that would read as a real value.
        guard v.isFinite else { return "" }
        // 2^53 — past this a Double carries no integral precision anyway, so the whole-number
        // branch has nothing left to say and fixed-decimal is both safe and honest.
        if v == v.rounded(), v.magnitude < 9_007_199_254_740_992 {
            return String(Int64(v))
        }
        return String(format: "%.2f", v)
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
    private static func calendarFiles(_ d: Deliverable, base: String, locale: Locale) -> [ExportFile] {
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
        // RFC 5545 requires DTSTAMP on every VEVENT, same axis as the UID requirement below
        // ("the founder's calendar app must not reject the file"). Apple and Google tolerate
        // its absence; Outlook and strict validators do not. One timestamp, shared by every
        // event in this export — it marks when the file was generated, not when any event
        // happens, so it does not need to vary per event.
        let stamp = icsTimestamp(Date())
        var n = 0
        for (wi, w) in weeks.enumerated() {
            for i in w.items {
                n += 1
                let day = icsDate(weekIndex: wi, dayLabel: i.day, locale: locale)
                ics += "BEGIN:VEVENT\r\n"
                ics += "UID:\(d.id)-\(n)@codepet.murror.app\r\n"
                ics += "DTSTAMP:\(stamp)\r\n"
                ics += "DTSTART;VALUE=DATE:\(day)\r\n"
                ics += "SUMMARY:\(icsEscaped(i.body))\r\n"
                ics += "DESCRIPTION:\(icsEscaped("\(w.label) · \(i.day) · \(i.kind) — day is relative to export"))\r\n"
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
    private static func icsDate(weekIndex: Int, dayLabel: String, locale: Locale) -> String {
        let offsets = ["mon": 0, "tue": 1, "wed": 2, "thu": 3, "fri": 4, "sat": 5, "sun": 6]
        let key = dayLabel.lowercased().prefix(3)
        let within = offsets[String(key)] ?? 0
        let days = weekIndex * 7 + within
        // Arithmetic must use the same time zone as the formatter (UTC) to avoid emitting
        // a day that is off by one near midnight on local timezone boundaries.
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        let date = cal.date(byAdding: .day, value: days, to: Date()) ?? Date()
        return fmt("yyyyMMdd", ambient: locale).string(from: date)
    }

    /// RFC 5545 basic UTC datetime (`yyyyMMdd'T'HHmmss'Z'`), for `DTSTAMP`.
    private static func icsTimestamp(_ date: Date) -> String {
        fmt("yyyyMMdd'T'HHmmss'Z'", ambient: .current).string(from: date)
    }

    /// A formatter for an RFC 5545 wire value — one place, because the two callers drifted.
    ///
    /// **The calendar and the numbering system are pinned, not inherited.** `icsTimestamp`
    /// set `en_US_POSIX`; `icsDate` set only the format and the time zone, so its `yyyy` was
    /// rendered in whatever calendar the Mac is set to. On a Mac defaulting to the Buddhist
    /// calendar that emits `DTSTART;VALUE=DATE:25690909` — a date 543 years out, and a file
    /// most calendar apps reject outright. A wire format is not localised; only the founder's
    /// screen is.
    ///
    /// `ambient` is the process locale the formatter would otherwise inherit. It is taken as a
    /// parameter rather than read from `Locale.current` so a test can pass a hostile one and
    /// prove the output does not move — see
    /// `testIcsDatesAreIdenticalWhateverCalendarTheMacIsSetTo`.
    private static func fmt(_ format: String, ambient: Locale) -> DateFormatter {
        var components = Locale.Components(locale: ambient)
        components.calendar = .gregorian
        components.numberingSystem = "latn"

        let f = DateFormatter()
        f.dateFormat = format
        f.timeZone = TimeZone(identifier: "UTC")
        f.locale = Locale(components: components)
        f.calendar = Calendar(identifier: .gregorian)
        return f
    }

    /// RFC 5545 text escaping: backslash, semicolon, comma and newline.
    ///
    /// **Carriage returns are folded into `\n` FIRST.** RFC 5545 line breaks are CRLF, so a
    /// bare `\r` left inside a property value is a line break to a strict parser — the same
    /// split-across-two-physical-lines corruption this escaping exists to prevent, which the
    /// original `\n`-only version still allowed through. Folding happens before the backslash
    /// escape because it introduces no backslashes of its own; doing it after would double the
    /// ones this adds.
    private static func icsEscaped(_ s: String) -> String {
        s.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: ";", with: "\\;")
            .replacingOccurrences(of: ",", with: "\\,")
            .replacingOccurrences(of: "\n", with: "\\n")
    }
}

// codepet/Models/DeliverableMarkdown.swift
import Foundation

/// Turns a department's `Deliverable` into a Markdown file for a Team Build's project
/// `docs/` folder.
///
/// **Read later by Claude Code to build the project** — completeness of the copy matters
/// more than styling here. This is deliberately its own renderer, not a reuse of
/// `DeliverableExport`: that type writes founder-facing files (`.csv`, `.ics`, `.html`, one
/// message per `.txt`) and knows nothing about a department or the instruction that produced
/// the work. This one always writes a single Markdown document, and carries both — a coding
/// agent reading `docs/` needs to know who wrote a file and what they were asked for, not
/// just what they handed back.
///
/// The field reading per kind mirrors `DeliverableExport` and the Library viewers
/// (`Views/Library/DeliverableViewers.swift`) — same guards, same "empty payload falls back
/// to `body`" shape — because those are the existing, tested map of which payload fields
/// matter for which kind.
enum DeliverableMarkdown {

    /// `dept` and `instruction` are the Team Build step's own words, not re-derived from the
    /// deliverable — so the doc says what was actually asked for even if the model wandered.
    static func render(_ d: Deliverable, dept: String, instruction: String) -> String {
        let header = "# \(d.title)\n\n**Department:** \(dept)\n**Asked for:** \(instruction)\n\n"

        guard let payload = d.payload else {
            return header + d.body
        }

        let structured = structuredSection(kind: d.kind, payload: payload)

        var out = header
        if !structured.isEmpty {
            out += structured + "\n\n"
        }

        // `body` is written by the same generation pass as `payload` — the runTask prompt says
        // "ALWAYS write the markdown body", then "ALSO fill payload" for a structured kind — so
        // where the structured render already says everything `body` does, appending it again
        // under a `## Notes` heading would just double the document. Only append it when it is
        // not (byte-for-byte, after trimming) identical to what was just rendered.
        let bodyTrimmed = d.body.trimmingCharacters(in: .whitespacesAndNewlines)
        if !bodyTrimmed.isEmpty && bodyTrimmed != structured.trimmingCharacters(in: .whitespacesAndNewlines) {
            out += "## Notes\n\n" + d.body
        }

        return out
    }

    // MARK: - per-kind structured rendering

    /// Empty string for a kind this payload has nothing structured for (a non-structured kind,
    /// or a structured kind whose matching payload fields are absent/empty) — `render` falls
    /// back to `d.body` in that case, the same "empty payload guard" every kind gets in
    /// `DeliverableExport`.
    private static func structuredSection(kind: DeliverableKind, payload: DeliverablePayload) -> String {
        switch kind {
        case .checklist: return checklistSection(payload)
        case .doc:       return docSection(payload)
        case .plan:      return planSection(payload)
        case .dms:       return dmsSection(payload)
        case .calendar:  return calendarSection(payload)
        case .sheet:     return sheetSection(payload)
        case .site:      return siteSection(payload)
        case .screens:   return screensSection(payload)
        case .post, .email, .legal, .text, .other:
            return ""
        }
    }

    private static func checklistSection(_ p: DeliverablePayload) -> String {
        guard let items = p.items, !items.isEmpty else { return "" }
        return items.map { "- [\($0.done ? "x" : " ")] \($0.t)" }.joined(separator: "\n")
    }

    private static func docSection(_ p: DeliverablePayload) -> String {
        guard let call = p.call, !call.isEmpty else { return "" }
        var out = call
        for s in p.sections ?? [] where !s.h.isEmpty || !s.p.isEmpty {
            out += "\n\n## \(s.h)\n\n\(s.p)"
        }
        let next = p.next ?? []
        if !next.isEmpty {
            out += "\n\n## Next\n\n" + next.map { "- \($0)" }.joined(separator: "\n")
        }
        return out
    }

    private static func planSection(_ p: DeliverablePayload) -> String {
        var parts: [String] = []
        if let goal = p.goal, !goal.isEmpty {
            parts.append("## Goal\n\n\(goal)")
        }
        if let steps = p.steps, !steps.isEmpty {
            parts.append("## Steps\n\n" + steps.enumerated()
                .map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n"))
        }
        if let changes = p.changes, !changes.isEmpty {
            parts.append("## Changes\n\n" + changes
                .map { "- **\($0.area)** — \($0.edit)" }.joined(separator: "\n"))
        }
        if let verify = p.verify, !verify.isEmpty {
            parts.append("## Verify\n\n" + verify.map { "- \($0)" }.joined(separator: "\n"))
        }
        if let risks = p.risks, !risks.isEmpty {
            parts.append("## Risks\n\n\(risks)")
        }
        return parts.joined(separator: "\n\n")
    }

    private static func dmsSection(_ p: DeliverablePayload) -> String {
        guard let messages = p.messages, !messages.isEmpty else { return "" }
        return messages.map { "### \($0.name)\n\n**Why:** \($0.note)\n\n\($0.msg)" }
            .joined(separator: "\n\n")
    }

    private static func calendarSection(_ p: DeliverablePayload) -> String {
        guard let weeks = p.calendar?.weeks, !weeks.isEmpty else { return "" }
        return weeks.map { week in
            "## \(week.label)\n\n" + week.items
                .map { "- **\($0.day) · \($0.kind):** \($0.body)" }.joined(separator: "\n")
        }.joined(separator: "\n\n")
    }

    private static func sheetSection(_ p: DeliverablePayload) -> String {
        guard let s = p.sheet else { return "" }
        func row(_ name: String, _ i: SheetInput) -> String {
            "| \(name) | \(n(i.val)) | \(n(i.min)) | \(n(i.max)) | \(n(i.step)) |"
        }
        var out = [
            "| Input | Value | Min | Max | Step |",
            "|---|---|---|---|---|",
            row("Price", s.price),
            row("Waitlist", s.waitlist),
            row("Conversion", s.conversion),
            row("Churn", s.churn),
        ].joined(separator: "\n")
        if let summary = s.summary, !summary.isEmpty {
            out += "\n\n\(summary)"
        }
        return out
    }

    private static func siteSection(_ p: DeliverablePayload) -> String {
        guard let s = p.site else { return "" }
        var parts: [String] = []

        var hero = "**Brand:** \(s.brand)"
        if !s.kicker.isEmpty { hero += "  \n_\(s.kicker)_" }
        hero += "\n\n## \(s.headline)" + (s.headlineHi.isEmpty ? "" : " \(s.headlineHi)")
        if !s.sub.isEmpty { hero += "\n\n\(s.sub)" }
        var ctas = "**CTA:** \(s.ctaPrimary)"
        if !s.ctaSecondary.isEmpty { ctas += " / \(s.ctaSecondary)" }
        hero += "\n\n\(ctas)"
        parts.append(hero)

        if !s.steps.isEmpty {
            let title = s.howTitle.isEmpty ? "How it works" : s.howTitle
            parts.append("### \(title)\n\n" + s.steps.enumerated()
                .map { "\($0.offset + 1). **\($0.element.h)** — \($0.element.p)" }.joined(separator: "\n"))
        }

        if !s.features.isEmpty {
            let title = s.featTitle.isEmpty ? "Features" : s.featTitle
            parts.append("### \(title)\n\n" + s.features
                .map { "- **\($0.h):** \($0.p)" }.joined(separator: "\n"))
        }

        if !s.quote.isEmpty {
            var q = "> \(s.quote)"
            if !s.quoteBy.isEmpty { q += "\n>\n> — \(s.quoteBy)" }
            parts.append(q)
        }

        var final = "## \(s.finalTitle)"
        if !s.finalSub.isEmpty { final += "\n\n\(s.finalSub)" }
        final += "\n\n**CTA:** \(s.finalCta)"
        parts.append(final)

        if !s.footNote.isEmpty { parts.append(s.footNote) }

        return parts.joined(separator: "\n\n")
    }

    private static func screensSection(_ p: DeliverablePayload) -> String {
        guard let screens = p.screens?.screens, !screens.isEmpty else { return "" }
        return screens.map { s in
            var block = "### \(s.name) (\(s.time))"
            if !s.kick.isEmpty { block += "\n\n**\(s.kick)**" }
            block += "\n\n\(s.title)"
            if !s.sub.isEmpty { block += "\n\n\(s.sub)" }
            block += "\n\nArt: \(s.art)"
            if !s.cta.isEmpty { block += "\n\nCTA: \(s.cta)" }
            if !s.note.isEmpty { block += "\n\n_\(s.note)_" }
            return block
        }.joined(separator: "\n\n")
    }

    /// A table number: whole values print without a decimal point, matching
    /// `DeliverableExport`'s `n(_:)` for the same reason — these are model-authored sliders
    /// (`SheetInput.val/min/max/step`), and a bare `\(Double)` interpolation would print
    /// `49.0` for a value the founder set as `49`.
    private static func n(_ v: Double) -> String {
        guard v.isFinite else { return "" }
        if v == v.rounded(), v.magnitude < 9_007_199_254_740_992 {
            return String(Int64(v))
        }
        return String(format: "%.2f", v)
    }
}

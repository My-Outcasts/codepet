// codepet/Views/Library/DeliverableViewers.swift
import SwiftUI
import AppKit
import WebKit

/// Eleven typed deliverable viewers, one per (mostly) structured
/// `DeliverableKind`. The first several read their slice of `DeliverablePayload`
/// and render it natively — no markdown parsing. `.legal`/`.post`/`.email`
/// carry no structured payload from the backend; they render `title` + `body`
/// inside kind-appropriate chrome instead — `.legal`/`.post` via `MarkdownView`,
/// `.email` via the shared message card in `MessageDraftCard.swift`.
/// All match the CodepetTheme house style used elsewhere in the Library.
/// Callers wrap these in a `ScrollView` (see `DeliverableDetailView`);
/// view-only interactions (toggling a checkbox, marking a DM "sent",
/// tapping through screens, previewing a site) live in local `@State` and are
/// never persisted.

// MARK: - ChecklistViewer

/// Renders a checklist payload: a progress bar over done/total, then one row
/// per item. Rows are tappable to toggle `done` — purely a local visual
/// state, not written back to the store.
///
/// Items are a founder's to-do list, so they are read at `DeliverableStyle.body` like every
/// other deliverable's prose. They were 13pt with no leading; a two-line item ran its own lines
/// together and read as one block of grey.
///
/// The row's fill is `surface` and so is the sheet behind it, which on the dark theme is a ~3%
/// lightness step — the same "the card is black" edgeless nesting the chat's draft card was
/// fixed for on Aug 6. The rows get the hairline they were missing rather than a heavier fill,
/// because a checklist is a list, not a stack of cards.
struct ChecklistViewer: View {
    @State private var items: [ChecklistItem]
    @Environment(\.uiLanguage) private var lang

    init(items: [ChecklistItem]) {
        _items = State(initialValue: items)
    }

    private var doneCount: Int { items.filter(\.done).count }
    private var progress: Double {
        items.isEmpty ? 0 : Double(doneCount) / Double(items.count)
    }

    /// The list as pasteable markdown — a checklist is something a founder moves into their own
    /// tracker, and before this the only way out of the app was retyping it.
    private var copyText: String {
        items.map { "- [\($0.done ? "x" : " ")] \($0.t)" }.joined(separator: "\n")
    }

    var body: some View {
        DeliverableFrame(eyebrow: lang == .vi ? "Danh sách" : "Checklist",
                         action: .copy(copyText)) {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(lang == .vi ? "Tiến độ" : "Progress")
                            .font(.pixelSystem(size: DeliverableStyle.footnote, weight: .semibold))
                            .foregroundColor(CodepetTheme.mutedText)
                        Spacer()
                        Text("\(doneCount)/\(items.count)")
                            .font(.pixelSystem(size: DeliverableStyle.footnote, weight: .semibold))
                            .monospacedDigit()
                            .foregroundColor(CodepetTheme.primaryText)
                    }
                    ProgressView(value: progress)
                        .tint(CodepetTheme.accentPurple)
                }

                VStack(alignment: .leading, spacing: 8) {
                    ForEach(items.indices, id: \.self) { i in
                        Button {
                            items[i].done.toggle()
                        } label: {
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: items[i].done ? "checkmark.square.fill" : "square")
                                    .foregroundColor(items[i].done ? CodepetTheme.accentPurple : CodepetTheme.mutedText)
                                Text(items[i].t)
                                    .font(.pixelSystem(size: DeliverableStyle.body))
                                    .lineSpacing(DeliverableStyle.leading)
                                    .foregroundColor(items[i].done ? CodepetTheme.mutedText : CodepetTheme.bodyText)
                                    .strikethrough(items[i].done, color: CodepetTheme.mutedText)
                                    .fixedSize(horizontal: false, vertical: true)
                                Spacer(minLength: 0)
                            }
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                RoundedRectangle(cornerRadius: CodepetTheme.inputRadius, style: .continuous)
                                    .fill(CodepetTheme.surface)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: CodepetTheme.inputRadius, style: .continuous)
                                    .strokeBorder(CodepetTheme.hairline, lineWidth: 1)
                            )
                            .hoverAffordance(RoundedRectangle(cornerRadius: CodepetTheme.inputRadius,
                                                              style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .cursorOnHover(.pointingHand)
                    }
                }
            }
        }
    }
}

// MARK: - DocViewer

/// Renders a doc payload: a tinted call-out box for `call`, each section as a
/// bold heading + paragraph, then a "Next" bullet list.
struct DocViewer: View {
    let call: String
    let sections: [DocSection]
    let next: [String]
    @Environment(\.uiLanguage) private var lang

    /// A document, set to be read.
    ///
    /// It was 13pt lead, 12pt body, no `lineSpacing` at all, 4pt between a heading and its own
    /// paragraph and 16pt between unrelated sections — so a heading sat nearly as close to the
    /// section above it as to the text it introduces, and nothing had room to breathe (founder,
    /// Aug 7). This is the viewer EVERY deliverable in the app opens into, so the fix reaches the
    /// Library and the Tasks preview too.
    ///
    /// Three rules: prose gets a reading measure (~1.6em leading, capped column), a heading binds
    /// to what follows it and separates from what precedes it, and a rule between sections does the
    /// separating so the gap does not have to be huge to read as a break.
    ///
    /// Those three rules and their five numbers now live in `DeliverableStyle`, because they were
    /// never specific to a doc — the nine viewers that could not see this private enum are what
    /// this pass is about. The `Doc` alias is kept so the reasoning above still reads against the
    /// names it was written for.
    private typealias Doc = DeliverableStyle

    /// The document as pasteable prose. The lead, then each section under its own heading, then
    /// the next-steps as bullets — the same order the eye reads it in.
    private var copyText: String {
        var out = [call]
        for s in sections { out.append("\(s.h)\n\(s.p)") }
        if !next.isEmpty {
            out.append(((lang == .vi ? "Tiếp theo" : "Next")) + "\n"
                       + next.map { "• \($0)" }.joined(separator: "\n"))
        }
        return out.joined(separator: "\n\n")
    }

    var body: some View {
        DeliverableFrame(eyebrow: lang == .vi ? "Tài liệu" : "Document",
                         action: .copy(copyText)) {
            VStack(alignment: .leading, spacing: Doc.betweenSections) {
                Text(call)
                    .font(.pixelSystem(size: Doc.lead, weight: .medium))
                    .lineSpacing(Doc.leading)
                    .foregroundColor(CodepetTheme.primaryText)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(18)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: CodepetTheme.inputRadius, style: .continuous)
                            .fill(CodepetTheme.accentPurple.opacity(0.1))
                    )

                ForEach(Array(sections.enumerated()), id: \.offset) { idx, section in
                    VStack(alignment: .leading, spacing: Doc.headingToBody) {
                        // A rule, not just a gap: it separates without needing the space to grow.
                        if idx > 0 {
                            DeliverableRule()
                                .padding(.bottom, Doc.betweenSections - Doc.headingToBody - 8)
                        }
                        DeliverableHeading(text: section.h)
                        DeliverableProse(text: section.p)
                    }
                }

                if !next.isEmpty {
                    VStack(alignment: .leading, spacing: Doc.headingToBody) {
                        DeliverableRule()
                            .padding(.bottom, Doc.betweenSections - Doc.headingToBody - 8)
                        DeliverableHeading(text: lang == .vi ? "Tiếp theo" : "Next")
                        ForEach(Array(next.enumerated()), id: \.offset) { _, line in
                            HStack(alignment: .top, spacing: 9) {
                                Text("•").font(.pixelSystem(size: Doc.body))
                                    .foregroundColor(CodepetTheme.mutedText)
                                DeliverableProse(text: line)
                            }
                        }
                    }
                }
            }
        }
    }
}

// MARK: - PlanViewer

/// Renders a plan payload: Goal, numbered Steps, Changes (area → edit),
/// Verify, and Risks. Every field is optional — sections that are nil or
/// empty are skipped.
///
/// The worst-set surface of the nine: every one of its five sections ran at 12pt with no leading
/// and no measure, under a 12pt grey label that was the same size as the content it introduced —
/// so a heading did not read as a heading, and the whole plan read as one grey block. Steps and
/// changes are prose a founder has to follow, so they are now set like prose; the section names
/// become eyebrows, which is what they were always trying to be.
struct PlanViewer: View {
    let payload: DeliverablePayload
    @Environment(\.uiLanguage) private var lang

    /// A section name. An eyebrow, not a same-size grey label — the point of a heading is that
    /// it does not look like the body. The SECOND rank, so it does not compete with the card's
    /// own "PLAN".
    private func label(_ en: String, _ vi: String) -> some View {
        DeliverableEyebrow.section(lang == .vi ? vi : en)
    }

    /// The plan as pasteable prose, in the order it reads.
    private var copyText: String {
        var out: [String] = []
        if let goal = payload.goal, !goal.isEmpty {
            out.append((lang == .vi ? "Mục tiêu" : "Goal") + "\n" + goal)
        }
        if let steps = payload.steps, !steps.isEmpty {
            out.append((lang == .vi ? "Các bước" : "Steps") + "\n"
                       + steps.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n"))
        }
        if let changes = payload.changes, !changes.isEmpty {
            out.append((lang == .vi ? "Thay đổi" : "Changes") + "\n"
                       + changes.map { "\($0.area): \($0.edit)" }.joined(separator: "\n"))
        }
        if let verify = payload.verify, !verify.isEmpty {
            out.append((lang == .vi ? "Kiểm chứng" : "Verify") + "\n"
                       + verify.map { "• \($0)" }.joined(separator: "\n"))
        }
        if let risks = payload.risks, !risks.isEmpty {
            out.append((lang == .vi ? "Rủi ro" : "Risks") + "\n" + risks)
        }
        return out.joined(separator: "\n\n")
    }

    var body: some View {
        DeliverableFrame(eyebrow: lang == .vi ? "Kế hoạch" : "Plan",
                         action: .copy(copyText)) {
            VStack(alignment: .leading, spacing: DeliverableStyle.betweenSections) {
                if let goal = payload.goal, !goal.isEmpty {
                    VStack(alignment: .leading, spacing: DeliverableStyle.headingToBody) {
                        label("Goal", "Mục tiêu")
                        DeliverableProse(text: goal, color: CodepetTheme.primaryText)
                    }
                }

                if let steps = payload.steps, !steps.isEmpty {
                    VStack(alignment: .leading, spacing: DeliverableStyle.headingToBody) {
                        label("Steps", "Các bước")
                        ForEach(Array(steps.enumerated()), id: \.offset) { i, step in
                            HStack(alignment: .top, spacing: 9) {
                                Text("\(i + 1).")
                                    .font(.pixelSystem(size: DeliverableStyle.body, weight: .semibold))
                                    .monospacedDigit()
                                    .foregroundColor(CodepetTheme.accentPurple)
                                    .frame(width: 20, alignment: .leading)
                                DeliverableProse(text: step)
                            }
                        }
                    }
                }

                if let changes = payload.changes, !changes.isEmpty {
                    VStack(alignment: .leading, spacing: DeliverableStyle.headingToBody) {
                        label("Changes", "Thay đổi")
                        ForEach(Array(changes.enumerated()), id: \.offset) { _, change in
                            VStack(alignment: .leading, spacing: 3) {
                                Text(change.area)
                                    .font(.pixelSystem(size: DeliverableStyle.body, weight: .semibold))
                                    .foregroundColor(CodepetTheme.primaryText)
                                    .fixedSize(horizontal: false, vertical: true)
                                DeliverableProse(text: change.edit)
                            }
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                RoundedRectangle(cornerRadius: CodepetTheme.inputRadius, style: .continuous)
                                    .fill(CodepetTheme.surface)
                            )
                            // The edge the nested card never had — `surface` on `surface` is a ~3%
                            // step on the dark theme, which is no edge at all (Aug 6).
                            .overlay(
                                RoundedRectangle(cornerRadius: CodepetTheme.inputRadius, style: .continuous)
                                    .strokeBorder(CodepetTheme.hairline, lineWidth: 1)
                            )
                        }
                    }
                }

                if let verify = payload.verify, !verify.isEmpty {
                    VStack(alignment: .leading, spacing: DeliverableStyle.headingToBody) {
                        label("Verify", "Kiểm chứng")
                        ForEach(Array(verify.enumerated()), id: \.offset) { _, check in
                            HStack(alignment: .top, spacing: 9) {
                                Image(systemName: "checkmark.circle")
                                    .font(.system(size: 12))
                                    .foregroundColor(CodepetTheme.accentTeal)
                                    .padding(.top, 2)
                                DeliverableProse(text: check)
                            }
                        }
                    }
                }

                if let risks = payload.risks, !risks.isEmpty {
                    VStack(alignment: .leading, spacing: DeliverableStyle.headingToBody) {
                        label("Risks", "Rủi ro")
                        DeliverableProse(text: risks)
                    }
                }
            }
        }
    }
}

// MARK: - DmsViewer

/// Renders a dms payload as one message card per recipient: the name as the heading with its
/// `note` chip and Copy on the header row, the message at reading size with its blanks tinted,
/// then the blanks note and a local "Mark sent" toggle (view-only).
///
/// Shares `MessageDraftCard.swift` with `EmailViewer` so both kinds of "something you will send"
/// read the same — the founder's Aug 10 ask was to tell messages apart from documents, which
/// only works if the two message kinds agree with each other.
struct DmsViewer: View {
    let messages: [DmMessage]
    @State private var sent: Set<Int> = []
    @Environment(\.uiLanguage) private var lang

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(messages.enumerated()), id: \.offset) { i, message in
                card(index: i, message: message)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func card(index i: Int, message: DmMessage) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                DeliverableEyebrow(text: lang == .vi ? "Tin nhắn" : "Message")
                Spacer(minLength: 12)
                DeliverableCopyButton(text: message.msg)
            }

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(message.name)
                    .font(.pixelSystem(size: DeliverableStyle.heading, weight: .semibold))
                    .foregroundColor(CodepetTheme.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
                if !message.note.isEmpty {
                    Text(message.note)
                        .font(.pixelSystem(size: 10, weight: .medium))
                        .foregroundColor(CodepetTheme.accentPurple)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Capsule().fill(CodepetTheme.accentPurple.opacity(0.1)))
                }
                Spacer(minLength: 0)
            }
            .padding(.top, 8)

            DeliverableRule().padding(.vertical, 14)

            DeliverableProse(text: message.msg)

            DeliverableRule().padding(.vertical, 14)

            HStack(alignment: .firstTextBaseline, spacing: 12) {
                DeliverableBlanksNote(text: message.msg, verb: .send)
                Button {
                    if sent.contains(i) { sent.remove(i) } else { sent.insert(i) }
                } label: {
                    Label(sent.contains(i)
                          ? (lang == .vi ? "Đã gửi" : "Sent")
                          : (lang == .vi ? "Đánh dấu đã gửi" : "Mark sent"),
                          systemImage: sent.contains(i) ? "checkmark.circle.fill" : "circle")
                }
                .buttonStyle(CodepetPillButtonStyle(
                    fill: sent.contains(i) ? CodepetTheme.accentTeal.opacity(0.15) : CodepetTheme.surface,
                    foreground: sent.contains(i) ? CodepetTheme.accentTeal : CodepetTheme.mutedText,
                    paddingH: 11, paddingV: 5,
                    font: .pixelSystem(size: 11, weight: .semibold)))
            }
        }
        // FORCED on, unlike every other viewer: these are siblings, not one frame. A `.dms`
        // deliverable is several messages to several people, and in a sheet with no edges they
        // would run together into one wall with names in it.
        .deliverableCardChrome(forced: true)
    }
}

// MARK: - LegalViewer

/// Renders a `.legal` deliverable as a formal document: a "Legal draft" eyebrow with Copy, the
/// markdown `body` at reading size, and the not-legal-advice line as the card's footer. This kind
/// carries no structured payload — content comes straight from `title` + `body`.
///
/// Three things moved. **Copy came into the card**: it used to trail underneath as a loose pill,
/// which is the page furniture the Aug 10 message pass diagnosed and fixed — for messages only,
/// because the fix lived inside `MessageDraftCard`. **The disclaimer became the footer** instead of
/// a third loose line under the card, so the card ends where the document ends. **The "Draft"
/// subline is gone**: the eyebrow already says LEGAL DRAFT, and the footer says it again with the
/// part that matters.
struct LegalViewer: View {
    let deliverable: Deliverable
    @Environment(\.uiLanguage) private var lang

    var body: some View {
        DeliverableFrame(
            eyebrow: lang == .vi ? "Bản nháp pháp lý" : "Legal draft",
            action: .copy(deliverable.body),
            footer: lang == .vi ? "Bản nháp — không phải tư vấn pháp lý."
                                : "Draft — not legal advice."
        ) {
            MarkdownView(markdown: deliverable.body)
        }
    }
}

// MARK: - PostViewer

/// Renders a `.post` deliverable as something you are about to publish: a "Social post" eyebrow
/// with Copy, the `body` as post text at reading size, and a footer naming what is still to fill
/// in before it goes out.
///
/// TWO INVENTIONS REMOVED, both of which stated things the app does not know.
///
/// **The engagement counts.** The card printed "12 Replies · 8 Reposts · 46 Likes" — hardcoded
/// integers, on a post the founder has not published, for an account the app has no connection
/// to. The old doc-comment called them "purely visual flavor", which is the whole problem: they
/// are indistinguishable from data, and the founder cannot tell by looking that the app is
/// making them up. This is the same rule the Virtual Company holds as rule 8 — never render
/// invented progress — and it is not weaker here because the numbers are prettier.
///
/// **The avatar.** A purple circle holding the first letter of the deliverable's TITLE, which is
/// not a person, not the founder, and not the company — an initials badge for an identity that
/// does not exist. The room cards deleted their `"Fi"`/`"Pr"` badges for exactly this reason:
/// an abbreviation earns its place only when there is no room for the word.
///
/// What is left is the post itself, which is what the founder came to read and is going to paste.
struct PostViewer: View {
    let deliverable: Deliverable
    @Environment(\.uiLanguage) private var lang

    var body: some View {
        DeliverableFrame(
            eyebrow: lang == .vi ? "Bài đăng" : "Social post",
            action: .copy(deliverable.body),
            footer: deliverableBlanksFooter(deliverable.body, verb: .post, lang: lang)
        ) {
            MarkdownView(markdown: deliverable.body)
        }
    }
}

// MARK: - CalendarViewer

/// Renders a calendar payload: for each `week`, a section with the week's
/// `label`, then an adaptive grid of item cards — each showing `day`, a
/// `kind` chip (mirrors DmsViewer's note-chip idiom), and the `body` line.
/// Mirrors web's CalendarViewer (components/artifact/viewers.tsx) in spirit.
struct CalendarViewer: View {
    let payload: CalendarPayload
    @Environment(\.uiLanguage) private var lang

    /// Widened from 150. A post's `body` is a sentence, and at reading size a 150pt column broke
    /// it across four or five lines — the grid was sized for the 11pt setting it used to be in.
    private let columns = [GridItem(.adaptive(minimum: 210), spacing: 10, alignment: .top)]

    /// The calendar as pasteable prose — a founder schedules these somewhere else.
    private var copyText: String {
        payload.weeks.map { week in
            week.label + "\n"
            + week.items.map { "\($0.day) · \($0.kind) — \($0.body)" }.joined(separator: "\n")
        }.joined(separator: "\n\n")
    }

    var body: some View {
        DeliverableFrame(eyebrow: lang == .vi ? "Lịch nội dung" : "Content calendar",
                         action: payload.weeks.isEmpty ? .none : .copy(copyText),
                         measured: false) {
            if payload.weeks.isEmpty {
                // An empty state is a sentence addressed to the founder, not a caption. It was
                // 12pt muted, smaller than anything around it, in a card whose whole content it is.
                DeliverableProse(text: lang == .vi ? "Chưa có mục nào." : "No entries yet.",
                                 tintBlanks: false,
                                 color: CodepetTheme.mutedText)
            } else {
                weeksList
            }
        }
    }

    private var weeksList: some View {
        VStack(alignment: .leading, spacing: DeliverableStyle.betweenSections) {
            ForEach(Array(payload.weeks.enumerated()), id: \.offset) { idx, week in
                VStack(alignment: .leading, spacing: DeliverableStyle.headingToBody) {
                    if idx > 0 {
                        DeliverableRule()
                            .padding(.bottom, DeliverableStyle.betweenSections
                                              - DeliverableStyle.headingToBody - 8)
                    }
                    DeliverableHeading(text: week.label)

                    LazyVGrid(columns: columns, alignment: .leading, spacing: 10) {
                        ForEach(Array(week.items.enumerated()), id: \.offset) { _, item in
                            VStack(alignment: .leading, spacing: 7) {
                                HStack(spacing: 6) {
                                    Text(item.day)
                                        .font(.pixelSystem(size: DeliverableStyle.footnote,
                                                           weight: .semibold))
                                        .foregroundColor(CodepetTheme.mutedText)
                                    Spacer(minLength: 4)
                                    Text(item.kind)
                                        .font(.pixelSystem(size: 9, weight: .medium))
                                        .foregroundColor(CodepetTheme.accentPurple)
                                        .padding(.horizontal, 6).padding(.vertical, 2)
                                        .background(Capsule().fill(CodepetTheme.accentPurple.opacity(0.1)))
                                }
                                DeliverableProse(text: item.body)
                            }
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                RoundedRectangle(cornerRadius: CodepetTheme.inputRadius, style: .continuous)
                                    .fill(CodepetTheme.surface)
                            )
                            // `surface` inside `surface` had no edge to hold it (Aug 6).
                            .overlay(
                                RoundedRectangle(cornerRadius: CodepetTheme.inputRadius, style: .continuous)
                                    .strokeBorder(CodepetTheme.hairline, lineWidth: 1)
                            )
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - SheetViewer

/// Renders a sheet payload as a live financial model: 4 range sliders (price,
/// waitlist, conversion, churn) seeded from each `SheetInput.val`, ranged
/// `min...max` and stepped `step`, driving a live recompute via
/// `SheetModel.compute` — a Swift port of web's `computeSheetModel`
/// (lib/ai/sheetModel.ts). Sliders are local `@State` only: this is a
/// read-only deliverable, so nothing here is ever written back to the store.
/// Also renders the payload's `summary` and a disclaimer footer, matching
/// web's SheetViewer in spirit.
struct SheetViewer: View {
    @State private var price: Double
    @State private var waitlist: Double
    @State private var conversion: Double
    @State private var churn: Double

    private let priceRange: ClosedRange<Double>
    private let priceStep: Double
    private let waitlistRange: ClosedRange<Double>
    private let waitlistStep: Double
    private let conversionRange: ClosedRange<Double>
    private let conversionStep: Double
    private let churnRange: ClosedRange<Double>
    private let churnStep: Double

    private let summary: String?

    @Environment(\.uiLanguage) private var lang

    init(payload: SheetPayload) {
        _price = State(initialValue: payload.price.val)
        _waitlist = State(initialValue: payload.waitlist.val)
        _conversion = State(initialValue: payload.conversion.val)
        _churn = State(initialValue: payload.churn.val)
        priceRange = Self.safeRange(payload.price)
        priceStep = Swift.max(1, payload.price.step)
        waitlistRange = Self.safeRange(payload.waitlist)
        waitlistStep = Swift.max(1, payload.waitlist.step)
        conversionRange = Self.safeRange(payload.conversion)
        conversionStep = Swift.max(1, payload.conversion.step)
        churnRange = Self.safeRange(payload.churn)
        churnStep = Swift.max(1, payload.churn.step)
        summary = payload.summary
    }

    /// A degenerate range (max ≤ min, as could arrive from a malformed payload)
    /// would crash SwiftUI's `Slider`; fall back to a 1-wide range instead.
    private static func safeRange(_ input: SheetInput) -> ClosedRange<Double> {
        input.min < input.max ? input.min...input.max : input.min...(input.min + 1)
    }

    private var model: SheetModel {
        SheetModel.compute(price: price, waitlist: waitlist, conversion: conversion, churn: churn)
    }

    /// The model's OUTPUTS, pasteable. The sliders are the founder's to move; the six figures are
    /// what they take away, and there was no way to get them out of the app.
    private var copyText: String {
        var lines = [
            "\(lang == .vi ? "Người dùng trả phí" : "Paid users"): \(model.paid)",
            "\(lang == .vi ? "MRR khởi điểm" : "Seed MRR"): \(fmtCurrency(model.mrr))",
            "\(lang == .vi ? "ARR ước tính" : "Run-rate ARR"): \(fmtCurrency(model.arr))",
            "\(lang == .vi ? "LTV / người dùng" : "LTV / user"): \(fmtCurrency(Double(model.ltv)))",
            "\(lang == .vi ? "Tuổi thọ (theo rời bỏ)" : "Churn-adj. life"): \(model.life)mo",
            "\(lang == .vi ? "Hòa vốn (số người dùng)" : "Break-even users"): \(model.breakeven)",
        ]
        if let summary, !summary.isEmpty { lines.append("\n" + summary) }
        return lines.joined(separator: "\n")
    }

    /// Not financial advice — the card's footer, not a loose third line under it.
    private var disclaimer: String {
        lang == .vi
            ? "Dự báo do Codepet soạn từ dữ liệu bạn nhập — không phải tư vấn tài chính. Hãy kiểm chứng trước khi dựa vào."
            : "Projections Codepet drafted from your inputs — not financial advice. Verify the figures before you rely on them."
    }

    /// `measured: false` — the sliders and the six-cell grid lay themselves out, and a 620pt cap
    /// would squeeze an interactive model into a prose column it is not.
    var body: some View {
        DeliverableFrame(eyebrow: lang == .vi ? "Mô hình tài chính" : "Financial model",
                         action: .copy(copyText),
                         footer: disclaimer,
                         measured: false) {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 12) {
                    sliderRow(lang == .vi ? "Giá gói Pro / tháng" : "Pro price / mo",
                              value: $price, range: priceRange, step: priceStep,
                              display: "$\(Int(price.rounded()))")
                    sliderRow(lang == .vi ? "Danh sách chờ" : "Waitlist size",
                              value: $waitlist, range: waitlistRange, step: waitlistStep,
                              display: "\(Int(waitlist.rounded()))")
                    sliderRow(lang == .vi ? "Chờ → trả phí" : "Waitlist → paid",
                              value: $conversion, range: conversionRange, step: conversionStep,
                              display: "\(Int(conversion.rounded()))%")
                    sliderRow(lang == .vi ? "Rời bỏ hàng tháng" : "Monthly churn",
                              value: $churn, range: churnRange, step: churnStep,
                              display: "\(Int(churn.rounded()))%")
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: CodepetTheme.cardRadius, style: .continuous)
                        .fill(CodepetTheme.surface)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: CodepetTheme.cardRadius, style: .continuous)
                        .strokeBorder(CodepetTheme.hairline, lineWidth: 1)
                )

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: 8)], spacing: 8) {
                    outCell(lang == .vi ? "Người dùng trả phí" : "Paid users", value: "\(model.paid)")
                    outCell(lang == .vi ? "MRR khởi điểm" : "Seed MRR", value: fmtCurrency(model.mrr), hero: true)
                    outCell(lang == .vi ? "ARR ước tính" : "Run-rate ARR", value: fmtCurrency(model.arr))
                    outCell(lang == .vi ? "LTV / người dùng" : "LTV / user", value: fmtCurrency(Double(model.ltv)))
                    outCell(lang == .vi ? "Tuổi thọ (theo rời bỏ)" : "Churn-adj. life", value: "\(model.life)mo")
                    outCell(lang == .vi ? "Hòa vốn (số người dùng)" : "Break-even users", value: "\(model.breakeven)")
                }

                if let summary, !summary.isEmpty {
                    DeliverableProse(text: summary)
                }
            }
        }
    }

    private func sliderRow(_ label: String, value: Binding<Double>, range: ClosedRange<Double>,
                            step: Double, display: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                    .font(.pixelSystem(size: 12, weight: .semibold))
                    .foregroundColor(CodepetTheme.mutedText)
                Spacer()
                Text(display)
                    .font(.pixelSystem(size: 12, weight: .semibold))
                    .foregroundColor(CodepetTheme.primaryText)
            }
            Slider(value: value, in: range, step: step)
                .tint(CodepetTheme.accentPurple)
        }
    }

    private func outCell(_ label: String, value: String, hero: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.pixelSystem(size: 10, weight: .medium))
                .foregroundColor(CodepetTheme.mutedText)
            Text(value)
                .font(.pixelSystem(size: hero ? 16 : 14, weight: .bold))
                .foregroundColor(hero ? CodepetTheme.accentPurple : CodepetTheme.primaryText)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: CodepetTheme.inputRadius, style: .continuous)
                .fill(CodepetTheme.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: CodepetTheme.inputRadius, style: .continuous)
                .strokeBorder(CodepetTheme.hairline, lineWidth: 1)
        )
    }

    /// Ports web's `fmt` helper (lib/helpers.ts): `$1.4k` above 1000, plain
    /// dollars below — a bare integer when the rounded value has no fractional
    /// part (matching JS Number stringification dropping a trailing `.0`).
    private func fmtCurrency(_ n: Double) -> String {
        guard n >= 1000 else { return "$\(Int(n.rounded()))" }
        let k = (n / 100).rounded() / 10
        if k == k.rounded() {
            return "$\(Int(k))k"
        }
        return "$\(String(format: "%.1f", k))k"
    }
}

// MARK: - EmailViewer

/// Renders an `.email` deliverable as a message card: an "Email draft" eyebrow and Copy on
/// one row, the subject as a heading over a hairline, the body at reading size with its
/// blanks tinted, and a footer naming what is still to fill in. See `MessageDraftCard.swift` for
/// what was taken from the founder's Aug 10 reference and what was deliberately left out.
struct EmailViewer: View {
    let deliverable: Deliverable
    @Environment(\.uiLanguage) private var lang

    var body: some View {
        MessageDraftViewer(eyebrow: lang == .vi ? "Email nháp" : "Email draft",
                           heading: deliverable.title,
                           text: deliverable.body)
    }
}

// MARK: - SiteViewer

/// Renders a site payload as an actual landing page inside a `WKWebView`: an
/// HTML string is built from the `SitePayload` fields (hero, "how it works"
/// steps, feature cards, quote, final CTA, foot note), mirroring the
/// structure of web's fixed template (lib/ai/siteTemplate.ts) — code owns
/// every tag; the payload only supplies escaped text + a validated accent
/// hex. Read-only: the web view just displays the generated markup (no
/// navigation, no JS bridge). A Preview/Code toggle lets you inspect the raw
/// HTML, and a Copy-HTML button puts it on the pasteboard.
struct SiteViewer: View {
    let payload: SitePayload
    /// Names the temp file the browser opens, so the same page replaces itself rather than
    /// accumulating copies. Optional with a default so no other call site has to change.
    var deliverableId: String? = nil
    @State private var tab: Tab = .preview
    /// Set when the write fails, so the button says why instead of doing nothing.
    @State private var openFailed = false
    @Environment(\.uiLanguage) private var lang

    /// **"Open in browser", not "Open".** The chat draft card already carries an "Open the live
    /// page" cue routing to THIS viewer; a second, differently-destined "Open" on one path is
    /// the confusion this avoids. The file is `file://` — a real browser page, and NOT
    /// shareable with anyone. No Share affordance, no Copy link.
    static func openLabel(_ lang: AppLanguage) -> String {
        lang == .vi ? "Mở trong trình duyệt" : "Open in browser"
    }

    private enum Tab { case preview, code }

    private var html: String { SiteViewer.buildHTML(payload) }

    /// `measured: false` — a rendered landing page is laid out by its own CSS at 1080pt, and a
    /// 620pt prose cap would show it in a column narrower than any browser it will ever load in.
    ///
    /// Copy keeps its own label. This card's action puts MARKUP on the pasteboard, not words, and
    /// a bare "Copy" next to a rendered page reads as "copy the page's text" — the one thing it
    /// does not do.
    var body: some View {
        DeliverableFrame(
            eyebrow: lang == .vi ? "Trang giới thiệu" : "Landing page",
            action: .copyLabelled(html,
                                  label: lang == .vi ? "Sao chép HTML" : "Copy HTML",
                                  done: lang == .vi ? "Đã sao chép" : "Copied"),
            measured: false
        ) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    // In THIS viewer's own content rather than on `DeliverableFrame`'s single
                    // `action:` slot: that frame is shared by 9 viewers and 13 deliverable
                    // kinds, and widening a shared API to serve one kind is the wrong trade.
                    // Copy HTML keeps the frame's slot untouched.
                    Button {
                        do {
                            let url = SiteExport.fileURL(
                                forDeliverableId: deliverableId ?? "site")
                            try SiteExport.write(html: html, to: url)
                            NSWorkspace.shared.open(url)
                            openFailed = false
                        } catch {
                            // A button that sometimes does nothing is worse than one that says
                            // why. Fail-soft: no trap, nothing thrown into the view.
                            openFailed = true
                        }
                    } label: {
                        Text(SiteViewer.openLabel(lang))
                            .font(.pixelSystem(size: 11, weight: .semibold))
                            .foregroundColor(CodepetTheme.accentPurple)
                    }
                    .buttonStyle(.plain)
                    .cursorOnHover(.pointingHand)

                    if openFailed {
                        Text(lang == .vi ? "Không mở được" : "Couldn't open")
                            .font(.pixelSystem(size: 11))
                            .foregroundColor(CodepetTheme.mutedText)
                    }

                    Spacer()
                    Picker("", selection: $tab) {
                        Text(lang == .vi ? "Xem trước" : "Preview").tag(Tab.preview)
                        Text(lang == .vi ? "Mã" : "Code").tag(Tab.code)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 160)
                }

                Group {
                    if tab == .preview {
                        SiteHTMLWebView(html: html)
                    } else {
                        ScrollView {
                            Text(html)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(CodepetTheme.bodyText)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(10)
                        }
                        .background(CodepetTheme.surface)
                    }
                }
                .frame(minHeight: 420)
                .clipShape(RoundedRectangle(cornerRadius: CodepetTheme.cardRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: CodepetTheme.cardRadius, style: .continuous)
                        .stroke(CodepetTheme.hairline, lineWidth: 1)
                )
            }
        }
    }

    // MARK: HTML template

    /// Builds the full HTML document for a `SitePayload`, mirroring the
    /// section structure of web's `renderSiteHtml` (lib/ai/siteTemplate.ts):
    /// nav → hero → how-it-works → features → quote → final CTA → footer.
    /// Every text field is HTML-escaped; `accent` is validated to a strict
    /// hex before being interpolated into the `<style>` block. Uses the
    /// system sans instead of the web template's Google Fonts import so the
    /// preview renders identically offline with no network dependency.
    static func buildHTML(_ p: SitePayload) -> String {
        let accent = safeHex(p.accent)
        let accent2 = shade(accent, by: 0.16)

        func cell(_ s: SiteContent, number: Int?) -> String {
            let n = number.map { "<div class=\"n\">\($0)</div>" } ?? ""
            return "<div class=\"step\">\(n)<h3>\(esc(s.h))</h3><p>\(esc(s.p))</p></div>"
        }

        let hero = """
        <div class="wrap"><header>\
        \(p.kicker.isEmpty ? "" : "<div class=\"kicker\">\(esc(p.kicker))</div>")\
        <h1>\(esc(p.headline))\(p.headlineHi.isEmpty ? "" : " <span class=\"hl\">\(esc(p.headlineHi))</span>")</h1>\
        \(p.sub.isEmpty ? "" : "<p class=\"sub\">\(esc(p.sub))</p>")\
        <div class="cta"><a class="btn p" href="#">\(esc(p.ctaPrimary))</a>\
        \(p.ctaSecondary.isEmpty ? "" : "<a class=\"btn g\" href=\"#\">\(esc(p.ctaSecondary))</a>")\
        </div></header></div>
        """

        let how = p.steps.isEmpty ? "" : """
        <div class="wrap" id="how"><section>\
        <div class="eyebrow">\(esc(p.howEyebrow))</div><h2>\(esc(p.howTitle))</h2>\
        <div class="steps">\(p.steps.enumerated().map { cell($1, number: $0 + 1) }.joined())</div>\
        </section></div>
        """

        let feat = p.features.isEmpty ? "" : """
        <div class="wrap" id="features"><section>\
        <div class="eyebrow">\(esc(p.featEyebrow))</div><h2>\(esc(p.featTitle))</h2>\
        <div class="feat">\(p.features.map { cell($0, number: nil) }.joined())</div>\
        </section></div>
        """

        let quote = p.quote.isEmpty ? "" : """
        <div class="wrap"><section><p class="quote">\(esc(p.quote))\
        \(p.quoteBy.isEmpty ? "" : "<span>\(esc(p.quoteBy))</span>")\
        </p></section></div>
        """

        let final = """
        <div class="wrap"><div class="final"><h2>\(esc(p.finalTitle))</h2>\
        \(p.finalSub.isEmpty ? "" : "<p class=\"fsub\">\(esc(p.finalSub))</p>")\
        <a class="btn p" href="#">\(esc(p.finalCta))</a></div></div>
        """

        return """
        <!doctype html><html><head><meta charset="utf-8">\
        <meta name="viewport" content="width=device-width,initial-scale=1">
        <title>\(esc(p.title))</title>
        <style>
        :root{--page:#efece4;--ink:#2b2a26;--ink2:#5d5b53;--accent:\(accent);--accent2:\(accent2);--card:#fbf9f4;--line:#e3ddd0}
        *{box-sizing:border-box;margin:0;padding:0}
        body{font-family:-apple-system,BlinkMacSystemFont,"Helvetica Neue",sans-serif;background:var(--page);color:var(--ink);line-height:1.5;-webkit-font-smoothing:antialiased}
        .wrap{max-width:1080px;margin:0 auto;padding:0 28px}
        nav{display:flex;align-items:center;gap:26px;padding:22px 0}
        .logo{font-weight:700;font-size:20px;display:flex;align-items:center;gap:9px}
        .logo .b{width:26px;height:26px;border-radius:7px;background:var(--accent);display:inline-block;position:relative;flex:none}
        .logo .b:before{content:"";position:absolute;left:6px;top:9px;width:4px;height:4px;background:#fff;box-shadow:10px 0 #fff}
        nav .nl{margin-left:auto;display:flex;gap:24px;font-size:14px;color:var(--ink2)}
        nav a{color:inherit;text-decoration:none}
        .btn{font-size:14px;font-weight:600;padding:10px 18px;border-radius:10px;border:0;cursor:pointer;text-decoration:none;display:inline-block}
        .btn.p{background:var(--accent);color:#fff}
        .btn.g{background:transparent;color:var(--ink);border:1px solid var(--line)}
        header{text-align:center;padding:66px 0 24px}
        .kicker{font-size:12px;letter-spacing:.12em;text-transform:uppercase;color:var(--accent2);margin-bottom:20px}
        h1{font-size:48px;line-height:1.1;letter-spacing:-.5px;margin-bottom:22px}
        h1 .hl{color:var(--accent)}
        .sub{font-size:19px;color:var(--ink2);max-width:600px;margin:0 auto 30px}
        .cta{display:flex;gap:12px;justify-content:center;flex-wrap:wrap}
        section{padding:56px 0}
        .eyebrow{font-size:12px;letter-spacing:.12em;text-transform:uppercase;color:var(--accent2);text-align:center;margin-bottom:12px}
        h2{font-size:30px;text-align:center;margin-bottom:44px}
        .steps,.feat{display:grid;grid-template-columns:repeat(3,1fr);gap:22px}
        .step{background:var(--card);border:1px solid var(--line);border-radius:14px;padding:26px}
        .step .n{font-size:13px;color:#fff;background:var(--accent);width:30px;height:30px;border-radius:8px;display:grid;place-items:center;margin-bottom:16px}
        .step h3{font-size:18px;margin-bottom:8px}
        .step p{font-size:14px;color:var(--ink2)}
        .quote{text-align:center;max-width:720px;margin:0 auto;font-size:22px;line-height:1.4}
        .quote span{color:var(--ink2);font-size:14px;display:block;margin-top:18px}
        .final{background:var(--accent);color:#fff;border-radius:20px;text-align:center;padding:58px 28px;margin:24px 0 64px}
        .final h2{color:#fff;margin-bottom:14px}
        .final .fsub{opacity:.9;margin-bottom:24px;font-size:17px}
        .final .btn.p{background:#fff;color:\(accent2)}
        footer{border-top:1px solid var(--line);padding:26px 0;display:flex;align-items:center;gap:16px;font-size:13px;color:var(--ink2);flex-wrap:wrap}
        footer .logo{font-size:16px}
        @media(max-width:760px){h1{font-size:36px}.steps,.feat{grid-template-columns:1fr}nav .nl{display:none}}
        </style></head><body>
        <div class="wrap"><nav>
          <div class="logo"><span class="b"></span>\(esc(p.brand))</div>
          <div class="nl">\(p.steps.isEmpty ? "" : "<a href=\"#how\">How it works</a>")\(p.features.isEmpty ? "" : "<a href=\"#features\">Features</a>")</div>
          <a class="btn p" href="#">\(esc(p.ctaPrimary))</a>
        </nav></div>
        \(hero)
        \(how)
        \(feat)
        \(quote)
        \(final)
        <div class="wrap"><footer>
          <div class="logo"><span class="b"></span>\(esc(p.brand))</div>
          <span style="margin-left:auto">\(esc(p.footNote))</span>
        </footer></div>
        </body></html>
        """
    }

    /// HTML-escape a text field before it goes anywhere near the template
    /// (ports web's `esc` in lib/ai/siteTemplate.ts).
    private static func esc(_ v: String) -> String {
        v.replacingOccurrences(of: "&", with: "&amp;")
         .replacingOccurrences(of: "<", with: "&lt;")
         .replacingOccurrences(of: ">", with: "&gt;")
         .replacingOccurrences(of: "\"", with: "&quot;")
         .replacingOccurrences(of: "'", with: "&#39;")
    }

    /// Only accept a plain `#rrggbb` (or `#rgb`) hex; anything else falls
    /// back to the brand purple. The accent is interpolated into a `<style>`
    /// block, so this guards against CSS injection via the one non-escaped
    /// field (ports web's `safeHex`).
    private static func safeHex(_ v: String) -> String {
        let fallback = "#7c3aed"
        let s = v.trimmingCharacters(in: .whitespacesAndNewlines)
        guard s.hasPrefix("#") else { return fallback }
        let hexPart = s.dropFirst()
        guard !hexPart.isEmpty, hexPart.allSatisfy(\.isHexDigit) else { return fallback }
        if hexPart.count == 6 { return "#" + hexPart.lowercased() }
        if hexPart.count == 3 {
            let expanded = hexPart.flatMap { [$0, $0] }
            return "#" + String(expanded).lowercased()
        }
        return fallback
    }

    /// Darken a validated hex by `f` (0–1) for the deeper accent shade
    /// (ports web's `shade`).
    private static func shade(_ hex: String, by f: Double) -> String {
        let digits = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        guard let n = UInt32(digits, radix: 16) else { return hex }
        let r = Int((Double((n >> 16) & 0xFF) * (1 - f)).rounded())
        let g = Int((Double((n >> 8) & 0xFF) * (1 - f)).rounded())
        let b = Int((Double(n & 0xFF) * (1 - f)).rounded())
        return String(format: "#%02x%02x%02x", r, g, b)
    }
}

/// `NSViewRepresentable` wrapping a `WKWebView` that loads a fixed HTML
/// string. Read-only preview surface — `loadHTMLString` with a `nil` base URL
/// so the generated markup can't reach out to the filesystem; no navigation
/// delegate is installed because the template never links anywhere real.
struct SiteHTMLWebView: NSViewRepresentable {
    let html: String

    func makeNSView(context: Context) -> WKWebView {
        let webView = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
        webView.loadHTMLString(html, baseURL: nil)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        webView.loadHTMLString(html, baseURL: nil)
    }
}

// MARK: - ScreensViewer

/// Renders a screens payload as a phone-mockup tap-through: one `Screen` at a
/// time inside a rounded phone frame (name · time header, `kick` label,
/// `title`/`sub`, an illustration keyed on `art`, the `cta` button, and
/// `note`), with back/next buttons and a dot page-indicator. Local `@State`
/// nav only — read-only, nothing here is written back to the store. The
/// illustration is a native SF Symbol stand-in per `art` value rather than a
/// pixel-match of web's SVGs (components/artifact/viewers.tsx).
struct ScreensViewer: View {
    let payload: ScreensPayload
    @State private var idx: Int = 0
    @Environment(\.uiLanguage) private var lang

    private var screens: [Screen] { payload.screens }

    /// `measured: false`, and the phone's own internals are left ALONE.
    ///
    /// Everything inside the 220×440 frame is a simulated phone UI: 9pt kickers, an 11pt subtitle,
    /// a 12pt CTA. Those sizes are not the app failing to set type for reading — they are the
    /// mockup being a mockup, and raising them to `DeliverableStyle.body` would make the phone
    /// stop looking like a phone. The reading standard governs what the founder READS; this card's
    /// content is a picture of something else. Only the card's own chrome and the caption below
    /// the mockup are brought into line.
    var body: some View {
        DeliverableFrame(eyebrow: lang == .vi ? "Màn hình" : "Screens",
                         measured: false) {
            if screens.isEmpty {
                DeliverableProse(text: lang == .vi ? "Không có màn hình nào" : "No screens",
                                 tintBlanks: false,
                                 color: CodepetTheme.mutedText)
            } else {
                VStack(spacing: 16) {
                    phoneFrame(screens[idx])

                    HStack(spacing: 16) {
                        Button {
                            idx = max(0, idx - 1)
                        } label: {
                            Image(systemName: "chevron.left")
                        }
                        .buttonStyle(CodepetIconButtonStyle(fill: CodepetTheme.surface))
                        .disabled(idx == 0)

                        HStack(spacing: 6) {
                            ForEach(screens.indices, id: \.self) { i in
                                Circle()
                                    .fill(i == idx ? CodepetTheme.accentPurple : CodepetTheme.hairline)
                                    .frame(width: 6, height: 6)
                            }
                        }

                        Button {
                            idx = min(screens.count - 1, idx + 1)
                        } label: {
                            Image(systemName: "chevron.right")
                        }
                        .buttonStyle(CodepetIconButtonStyle(fill: CodepetTheme.surface))
                        .disabled(idx == screens.count - 1)
                    }

                    Text(lang == .vi
                         ? "Chạm mũi tên để xem từng màn hình (\(idx + 1)/\(screens.count))"
                         : "Tap through the screens (\(idx + 1)/\(screens.count))")
                        .font(.pixelSystem(size: 11))
                        .foregroundColor(CodepetTheme.mutedText)
                }
                .frame(maxWidth: .infinity)
                .onAppear { idx = min(max(idx, 0), screens.count - 1) }
            }
        }
    }

    @ViewBuilder
    private func phoneFrame(_ screen: Screen) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(screen.name)
                    .font(.pixelSystem(size: 11, weight: .semibold))
                    .foregroundColor(CodepetTheme.primaryText)
                Spacer()
                Text(screen.time)
                    .font(.pixelSystem(size: 10))
                    .foregroundColor(CodepetTheme.mutedText)
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 10)

            VStack(alignment: .leading, spacing: 6) {
                Text(screen.kick.uppercased())
                    .font(.pixelSystem(size: 9, weight: .bold))
                    .foregroundColor(CodepetTheme.accentPurple)
                Text(screen.title)
                    .font(.pixelSystem(size: 16, weight: .bold))
                    .foregroundColor(CodepetTheme.primaryText)
                Text(screen.sub)
                    .font(.pixelSystem(size: 11))
                    .foregroundColor(CodepetTheme.bodyText)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)

            artStandIn(for: screen.art)
                .frame(maxWidth: .infinity, minHeight: 120, maxHeight: .infinity)
                .padding(16)

            VStack(spacing: 6) {
                Text(screen.cta)
                    .font(.pixelSystem(size: 12, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.vertical, 9)
                    .frame(maxWidth: .infinity)
                    .background(Capsule().fill(CodepetTheme.accentPurple))
                Text(screen.note)
                    .font(.pixelSystem(size: 9))
                    .foregroundColor(CodepetTheme.mutedText)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
        .frame(width: 220, height: 440)
        .background(
            RoundedRectangle(cornerRadius: 34, style: .continuous)
                .fill(CodepetTheme.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 34, style: .continuous)
                .stroke(CodepetTheme.hairline, lineWidth: 6)
        )
        .codepetShadow(CodepetTheme.floatingShadow)
    }

    /// Native stand-in illustration per `art` value — deliberately not a
    /// pixel-match of web's bespoke SVGs (connect/session/recap), just a
    /// tasteful SF Symbol pairing tinted with the accent purple.
    @ViewBuilder
    private func artStandIn(for art: String) -> some View {
        switch art {
        case "connect":
            artBox(primary: "link", secondary: "person.2")
        case "session":
            artBox(primary: "bubble.left.and.bubble.right", secondary: "sparkles")
        case "recap":
            artBox(primary: "checkmark.seal", secondary: "chart.bar")
        default:
            artBox(primary: "rectangle.dashed", secondary: "questionmark")
        }
    }

    private func artBox(primary: String, secondary: String) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: CodepetTheme.inputRadius, style: .continuous)
                .fill(CodepetTheme.accentPurple.opacity(0.08))
            VStack(spacing: 10) {
                Image(systemName: primary)
                    .font(.system(size: 30))
                    .foregroundColor(CodepetTheme.accentPurple)
                Image(systemName: secondary)
                    .font(.system(size: 15))
                    .foregroundColor(CodepetTheme.accentPurple.opacity(0.6))
            }
        }
    }
}

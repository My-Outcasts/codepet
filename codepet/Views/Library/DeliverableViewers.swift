// codepet/Views/Library/DeliverableViewers.swift
import SwiftUI
import AppKit
import WebKit

/// Eleven typed deliverable viewers, one per (mostly) structured
/// `DeliverableKind`. The first several read their slice of `DeliverablePayload`
/// and render it natively — no markdown parsing. `.legal`/`.post`/`.email`
/// carry no structured payload from the backend; they render `title` + `body`
/// (via `MarkdownView` for the body) inside kind-appropriate chrome instead.
/// All match the CodepetTheme house style used elsewhere in the Library.
/// Callers wrap these in a `ScrollView` (see `DeliverableDetailView`);
/// view-only interactions (toggling a checkbox, marking a DM "sent",
/// tapping through screens, previewing a site) live in local `@State` and are
/// never persisted.

// MARK: - ChecklistViewer

/// Renders a checklist payload: a progress bar over done/total, then one row
/// per item. Rows are tappable to toggle `done` — purely a local visual
/// state, not written back to the store.
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

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(lang == .vi ? "Tiến độ" : "Progress")
                        .font(.pixelSystem(size: 12, weight: .semibold))
                        .foregroundColor(CodepetTheme.mutedText)
                    Spacer()
                    Text("\(doneCount)/\(items.count)")
                        .font(.pixelSystem(size: 12, weight: .semibold))
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
                                .font(.pixelSystem(size: 13))
                                .foregroundColor(items[i].done ? CodepetTheme.mutedText : CodepetTheme.bodyText)
                                .strikethrough(items[i].done, color: CodepetTheme.mutedText)
                            Spacer(minLength: 0)
                        }
                        .padding(10)
                        .background(
                            RoundedRectangle(cornerRadius: CodepetTheme.inputRadius, style: .continuous)
                                .fill(CodepetTheme.surface)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(call)
                .font(.pixelSystem(size: 13, weight: .medium))
                .foregroundColor(CodepetTheme.primaryText)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: CodepetTheme.inputRadius, style: .continuous)
                        .fill(CodepetTheme.accentPurple.opacity(0.1))
                )

            ForEach(Array(sections.enumerated()), id: \.offset) { _, section in
                VStack(alignment: .leading, spacing: 4) {
                    Text(section.h)
                        .font(.pixelSystem(size: 14, weight: .bold))
                        .foregroundColor(CodepetTheme.primaryText)
                    Text(section.p)
                        .font(.pixelSystem(size: 12))
                        .foregroundColor(CodepetTheme.bodyText)
                }
            }

            if !next.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text(lang == .vi ? "Tiếp theo" : "Next")
                        .font(.pixelSystem(size: 12, weight: .semibold))
                        .foregroundColor(CodepetTheme.mutedText)
                    ForEach(Array(next.enumerated()), id: \.offset) { _, line in
                        HStack(alignment: .top, spacing: 8) {
                            Text("•").foregroundColor(CodepetTheme.mutedText)
                            Text(line)
                                .font(.pixelSystem(size: 12))
                                .foregroundColor(CodepetTheme.bodyText)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - PlanViewer

/// Renders a plan payload: Goal, numbered Steps, Changes (area → edit),
/// Verify, and Risks. Every field is optional — sections that are nil or
/// empty are skipped.
struct PlanViewer: View {
    let payload: DeliverablePayload
    @Environment(\.uiLanguage) private var lang

    private func label(_ en: String, _ vi: String) -> some View {
        Text(lang == .vi ? vi : en)
            .font(.pixelSystem(size: 12, weight: .semibold))
            .foregroundColor(CodepetTheme.mutedText)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let goal = payload.goal, !goal.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    label("Goal", "Mục tiêu")
                    Text(goal)
                        .font(.pixelSystem(size: 13))
                        .foregroundColor(CodepetTheme.primaryText)
                }
            }

            if let steps = payload.steps, !steps.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    label("Steps", "Các bước")
                    ForEach(Array(steps.enumerated()), id: \.offset) { i, step in
                        HStack(alignment: .top, spacing: 8) {
                            Text("\(i + 1).")
                                .font(.pixelSystem(size: 12, weight: .semibold))
                                .foregroundColor(CodepetTheme.accentPurple)
                                .frame(width: 18, alignment: .leading)
                            Text(step)
                                .font(.pixelSystem(size: 12))
                                .foregroundColor(CodepetTheme.bodyText)
                        }
                    }
                }
            }

            if let changes = payload.changes, !changes.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    label("Changes", "Thay đổi")
                    ForEach(Array(changes.enumerated()), id: \.offset) { _, change in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(change.area)
                                .font(.pixelSystem(size: 12, weight: .semibold))
                                .foregroundColor(CodepetTheme.primaryText)
                            Text(change.edit)
                                .font(.pixelSystem(size: 12))
                                .foregroundColor(CodepetTheme.bodyText)
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: CodepetTheme.inputRadius, style: .continuous)
                                .fill(CodepetTheme.surface)
                        )
                    }
                }
            }

            if let verify = payload.verify, !verify.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    label("Verify", "Kiểm chứng")
                    ForEach(Array(verify.enumerated()), id: \.offset) { _, check in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "checkmark.circle").foregroundColor(CodepetTheme.accentTeal)
                            Text(check)
                                .font(.pixelSystem(size: 12))
                                .foregroundColor(CodepetTheme.bodyText)
                        }
                    }
                }
            }

            if let risks = payload.risks, !risks.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    label("Risks", "Rủi ro")
                    Text(risks)
                        .font(.pixelSystem(size: 12))
                        .foregroundColor(CodepetTheme.bodyText)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - DmsViewer

/// Renders a dms payload: one card per message with a sender name, a `note`
/// chip, the message body, a Copy-to-clipboard button, and a local
/// "Mark sent" toggle (view-only).
struct DmsViewer: View {
    let messages: [DmMessage]
    @State private var sent: Set<Int> = []
    @Environment(\.uiLanguage) private var lang

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(messages.enumerated()), id: \.offset) { i, message in
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Text(message.name)
                            .font(.pixelSystem(size: 13, weight: .semibold))
                            .foregroundColor(CodepetTheme.primaryText)
                        Text(message.note)
                            .font(.pixelSystem(size: 10, weight: .medium))
                            .foregroundColor(CodepetTheme.accentPurple)
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(Capsule().fill(CodepetTheme.accentPurple.opacity(0.1)))
                        Spacer()
                    }
                    Text(message.msg)
                        .font(.pixelSystem(size: 12))
                        .foregroundColor(CodepetTheme.bodyText)

                    HStack(spacing: 10) {
                        Button {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(message.msg, forType: .string)
                        } label: {
                            Label(lang == .vi ? "Sao chép" : "Copy", systemImage: "doc.on.doc")
                        }
                        .buttonStyle(CodepetPillButtonStyle(
                            fill: CodepetTheme.surface,
                            foreground: CodepetTheme.primaryText,
                            paddingH: 12, paddingV: 6,
                            font: .pixelSystem(size: 11, weight: .semibold)))

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
                            foreground: sent.contains(i) ? CodepetTheme.accentTeal : CodepetTheme.primaryText,
                            paddingH: 12, paddingV: 6,
                            font: .pixelSystem(size: 11, weight: .semibold)))

                        Spacer()
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: CodepetTheme.cardRadius, style: .continuous)
                        .fill(CodepetTheme.surface)
                )
                .codepetShadow(CodepetTheme.cardShadow)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - LegalViewer

/// Renders a `.legal` deliverable as a formal document "sheet": a heading, a
/// static "Draft" subline, the markdown `body`, and a disclaimer footer. This
/// kind carries no structured payload — content comes straight from `title` +
/// `body`.
struct LegalViewer: View {
    let deliverable: Deliverable
    @Environment(\.uiLanguage) private var lang

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(deliverable.title)
                        .font(.pixelSystem(size: 15, weight: .bold))
                        .foregroundColor(CodepetTheme.primaryText)
                    Text(lang == .vi ? "Bản nháp" : "Draft")
                        .font(.pixelSystem(size: 11, weight: .medium))
                        .foregroundColor(CodepetTheme.mutedText)
                }

                Divider()

                MarkdownView(markdown: deliverable.body)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: CodepetTheme.cardRadius, style: .continuous)
                    .fill(CodepetTheme.surface)
            )
            .codepetShadow(CodepetTheme.cardShadow)

            Text(lang == .vi
                 ? "Bản nháp — không phải tư vấn pháp lý."
                 : "Draft — not legal advice.")
                .font(.pixelSystem(size: 11))
                .foregroundColor(CodepetTheme.mutedText)

            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(deliverable.body, forType: .string)
            } label: {
                Label(lang == .vi ? "Sao chép" : "Copy", systemImage: "doc.on.doc")
            }
            .buttonStyle(CodepetPillButtonStyle(
                fill: CodepetTheme.surface,
                foreground: CodepetTheme.primaryText,
                paddingH: 12, paddingV: 6,
                font: .pixelSystem(size: 11, weight: .semibold)))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - PostViewer

/// Renders a `.post` deliverable as a social-post card: a round avatar with
/// the title's initial, the `body` as post text, and a muted, clearly
/// decorative stats row (no live counts are tracked natively).
struct PostViewer: View {
    let deliverable: Deliverable
    @Environment(\.uiLanguage) private var lang

    private var initial: String {
        String(deliverable.title.trimmingCharacters(in: .whitespaces).first ?? "C").uppercased()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Text(initial)
                        .font(.pixelSystem(size: 14, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 32, height: 32)
                        .background(Circle().fill(CodepetTheme.accentPurple))
                    VStack(alignment: .leading, spacing: 1) {
                        Text(deliverable.title)
                            .font(.pixelSystem(size: 13, weight: .semibold))
                            .foregroundColor(CodepetTheme.primaryText)
                        Text(lang == .vi ? "vừa xong" : "now")
                            .font(.pixelSystem(size: 11))
                            .foregroundColor(CodepetTheme.mutedText)
                    }
                    Spacer()
                }

                MarkdownView(markdown: deliverable.body)

                HStack(spacing: 18) {
                    statItem(icon: "bubble.right", count: 12, label: lang == .vi ? "Trả lời" : "Replies")
                    statItem(icon: "arrow.2.squarepath", count: 8, label: lang == .vi ? "Chia sẻ lại" : "Reposts")
                    statItem(icon: "heart", count: 46, label: lang == .vi ? "Thích" : "Likes")
                    Spacer()
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: CodepetTheme.cardRadius, style: .continuous)
                    .fill(CodepetTheme.surface)
            )
            .codepetShadow(CodepetTheme.cardShadow)

            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(deliverable.body, forType: .string)
            } label: {
                Label(lang == .vi ? "Sao chép" : "Copy", systemImage: "doc.on.doc")
            }
            .buttonStyle(CodepetPillButtonStyle(
                fill: CodepetTheme.surface,
                foreground: CodepetTheme.primaryText,
                paddingH: 12, paddingV: 6,
                font: .pixelSystem(size: 11, weight: .semibold)))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Decorative stat chip — icon + placeholder count + label. Purely
    /// visual flavor; no real engagement data is tracked natively.
    private func statItem(icon: String, count: Int, label: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
            Text("\(count)")
                .font(.pixelSystem(size: 11, weight: .semibold))
            Text(label)
        }
        .font(.pixelSystem(size: 11))
        .foregroundColor(CodepetTheme.mutedText)
    }
}

// MARK: - CalendarViewer

/// Renders a calendar payload: for each `week`, a section with the week's
/// `label`, then an adaptive grid of item cards — each showing `day`, a
/// `kind` chip (mirrors DmsViewer's note-chip idiom), and the `body` line.
/// Mirrors web's CalendarViewer (components/artifact/viewers.tsx) in spirit.
struct CalendarViewer: View {
    let payload: CalendarPayload

    private let columns = [GridItem(.adaptive(minimum: 150), spacing: 8, alignment: .top)]

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            ForEach(Array(payload.weeks.enumerated()), id: \.offset) { _, week in
                VStack(alignment: .leading, spacing: 8) {
                    Text(week.label)
                        .font(.pixelSystem(size: 13, weight: .bold))
                        .foregroundColor(CodepetTheme.primaryText)

                    LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
                        ForEach(Array(week.items.enumerated()), id: \.offset) { _, item in
                            VStack(alignment: .leading, spacing: 6) {
                                HStack(spacing: 6) {
                                    Text(item.day)
                                        .font(.pixelSystem(size: 11, weight: .semibold))
                                        .foregroundColor(CodepetTheme.mutedText)
                                    Spacer()
                                    Text(item.kind)
                                        .font(.pixelSystem(size: 9, weight: .medium))
                                        .foregroundColor(CodepetTheme.accentPurple)
                                        .padding(.horizontal, 6).padding(.vertical, 2)
                                        .background(Capsule().fill(CodepetTheme.accentPurple.opacity(0.1)))
                                }
                                Text(item.body)
                                    .font(.pixelSystem(size: 11))
                                    .foregroundColor(CodepetTheme.bodyText)
                            }
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                RoundedRectangle(cornerRadius: CodepetTheme.inputRadius, style: .continuous)
                                    .fill(CodepetTheme.surface)
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

    var body: some View {
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
            .codepetShadow(CodepetTheme.cardShadow)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: 8)], spacing: 8) {
                outCell(lang == .vi ? "Người dùng trả phí" : "Paid users", value: "\(model.paid)")
                outCell(lang == .vi ? "MRR khởi điểm" : "Seed MRR", value: fmtCurrency(model.mrr), hero: true)
                outCell(lang == .vi ? "ARR ước tính" : "Run-rate ARR", value: fmtCurrency(model.arr))
                outCell(lang == .vi ? "LTV / người dùng" : "LTV / user", value: fmtCurrency(Double(model.ltv)))
                outCell(lang == .vi ? "Tuổi thọ (theo rời bỏ)" : "Churn-adj. life", value: "\(model.life)mo")
                outCell(lang == .vi ? "Hòa vốn (số người dùng)" : "Break-even users", value: "\(model.breakeven)")
            }

            if let summary, !summary.isEmpty {
                Text(summary)
                    .font(.pixelSystem(size: 12))
                    .foregroundColor(CodepetTheme.bodyText)
            }

            Text(lang == .vi
                 ? "Dự báo do Codepet soạn từ dữ liệu bạn nhập — không phải tư vấn tài chính. Hãy kiểm chứng trước khi dựa vào."
                 : "Projections Codepet drafted from your inputs — not financial advice. Verify the figures before you rely on them.")
                .font(.pixelSystem(size: 11))
                .foregroundColor(CodepetTheme.mutedText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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

/// Renders an `.email` deliverable as an email-client chrome: a header bar
/// (Subject/From/preheader) over the markdown `body` rendered as the email
/// content.
struct EmailViewer: View {
    let deliverable: Deliverable
    @Environment(\.uiLanguage) private var lang

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .top, spacing: 6) {
                        Text(lang == .vi ? "Chủ đề:" : "Subject:")
                            .font(.pixelSystem(size: 11, weight: .semibold))
                            .foregroundColor(CodepetTheme.mutedText)
                        Text(deliverable.title)
                            .font(.pixelSystem(size: 13, weight: .bold))
                            .foregroundColor(CodepetTheme.primaryText)
                    }
                    HStack(spacing: 6) {
                        Text(lang == .vi ? "Từ:" : "From:")
                            .font(.pixelSystem(size: 11, weight: .semibold))
                            .foregroundColor(CodepetTheme.mutedText)
                        Text("Codepet")
                            .font(.pixelSystem(size: 11))
                            .foregroundColor(CodepetTheme.bodyText)
                    }
                    Text(lang == .vi ? "Email nháp do Codepet tạo" : "Draft email generated by Codepet")
                        .font(.pixelSystem(size: 11))
                        .foregroundColor(CodepetTheme.mutedText)
                        .padding(.top, 2)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(CodepetTheme.accentPurple.opacity(0.06))

                Divider()

                MarkdownView(markdown: deliverable.body)
                    .padding(12)
            }
            .background(
                RoundedRectangle(cornerRadius: CodepetTheme.cardRadius, style: .continuous)
                    .fill(CodepetTheme.surface)
            )
            .clipShape(RoundedRectangle(cornerRadius: CodepetTheme.cardRadius, style: .continuous))
            .codepetShadow(CodepetTheme.cardShadow)

            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(deliverable.body, forType: .string)
            } label: {
                Label(lang == .vi ? "Sao chép" : "Copy", systemImage: "doc.on.doc")
            }
            .buttonStyle(CodepetPillButtonStyle(
                fill: CodepetTheme.surface,
                foreground: CodepetTheme.primaryText,
                paddingH: 12, paddingV: 6,
                font: .pixelSystem(size: 11, weight: .semibold)))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
    @State private var tab: Tab = .preview
    @Environment(\.uiLanguage) private var lang

    private enum Tab { case preview, code }

    private var html: String { SiteViewer.buildHTML(payload) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(lang == .vi ? "Xem trước trang web" : "Landing page preview")
                    .font(.pixelSystem(size: 12, weight: .semibold))
                    .foregroundColor(CodepetTheme.mutedText)
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
            .codepetShadow(CodepetTheme.cardShadow)

            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(html, forType: .string)
            } label: {
                Label(lang == .vi ? "Sao chép HTML" : "Copy HTML", systemImage: "doc.on.doc")
            }
            .buttonStyle(CodepetPillButtonStyle(
                fill: CodepetTheme.surface,
                foreground: CodepetTheme.primaryText,
                paddingH: 12, paddingV: 6,
                font: .pixelSystem(size: 11, weight: .semibold)))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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

    var body: some View {
        Group {
            if screens.isEmpty {
                Text(lang == .vi ? "Không có màn hình nào" : "No screens")
                    .font(.pixelSystem(size: 12))
                    .foregroundColor(CodepetTheme.mutedText)
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
        .frame(maxWidth: .infinity, alignment: .leading)
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

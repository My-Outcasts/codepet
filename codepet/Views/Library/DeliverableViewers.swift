// codepet/Views/Library/DeliverableViewers.swift
import SwiftUI
import AppKit

/// Seven typed deliverable viewers, one per (mostly) structured
/// `DeliverableKind`. The first four read their slice of `DeliverablePayload`
/// and render it natively — no markdown parsing. `.legal`/`.post`/`.email`
/// carry no structured payload from the backend; they render `title` + `body`
/// (via `MarkdownView` for the body) inside kind-appropriate chrome instead.
/// All match the CodepetTheme house style used elsewhere in the Library.
/// Callers wrap these in a `ScrollView` (see `DeliverableDetailView`);
/// view-only interactions (toggling a checkbox, marking a DM "sent") live in
/// local `@State` and are never persisted.

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

// codepet/Views/Library/DeliverableViewers.swift
import SwiftUI
import AppKit

/// Four typed deliverable viewers, one per structured `DeliverableKind`. Each
/// reads its slice of `DeliverablePayload` and renders it natively — no
/// markdown parsing — matching the CodepetTheme house style used elsewhere in
/// the Library. Callers wrap these in a `ScrollView` (see
/// `DeliverableDetailView`); view-only interactions (toggling a checkbox,
/// marking a DM "sent") live in local `@State` and are never persisted.

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

            ForEach(sections, id: \.h) { section in
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
                    ForEach(next, id: \.self) { line in
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
                    ForEach(changes, id: \.area) { change in
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
                    ForEach(verify, id: \.self) { check in
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

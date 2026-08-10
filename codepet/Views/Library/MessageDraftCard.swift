// codepet/Views/Library/MessageDraftCard.swift
import SwiftUI
import AppKit

/// The shared chrome for deliverables you are meant to SEND — `.email` and `.dms`.
///
/// Founder call, Aug 10: a drafted message should be distinguishable at a glance from a
/// document, the way ChatGPT's email card is. Three things do that work, and they are the
/// three borrowed from the reference:
///
/// 1. **Copy sits in the card**, at the top-right, because copying is the whole point of a
///    message. It used to sit below the card in `EmailViewer`, reading as page furniture.
/// 2. **The subject is a heading**, over a hairline, instead of a `Subject:` label row.
/// 3. **The blanks are tinted** — `[name]`, `$[X]` — and counted in a footer line, so the
///    card says out loud that it is not ready to send yet.
///
/// Not borrowed: **Send**. There is no mail integration behind it, and a `mailto:` that drops
/// the formatting is worse than the Copy that already works. **Edit** is likewise absent —
/// nothing in the app persists an edited deliverable body, so the pill would lie.
///
/// Typography follows `DocViewer`'s Aug 7 pass (14pt body, ~1.6em leading, capped measure).
/// Messages were left behind at 11–12pt with no leading, which is the same cramped setting
/// the founder rejected for documents.
enum MessageDraftStyle {
    static let eyebrow: CGFloat = 10
    static let subject: CGFloat = 15
    static let body: CGFloat = 14
    static let leading: CGFloat = 7      // ~1.6em on 14pt
    static let footnote: CGFloat = 11
    /// ~68 characters, matching `DocViewer.Doc.measure`.
    static let measure: CGFloat = 620
    static let padding: CGFloat = 16

    static var blankTint: Color { CodepetTheme.accentGold.opacity(0.28) }
    static var blankInk: Color { CodepetTheme.primaryText }
}

// MARK: - The card

/// One drafted message, whole: eyebrow + Copy, a heading over a hairline, the prose, and the
/// blanks footer when there is one.
///
/// Shared rather than written per viewer because `.email` and a payload-less `.dms` are the
/// same object to the founder — something written for a person, to be pasted and sent. Before
/// this, `.dms` without its structured payload fell through to raw `MarkdownView`, which is
/// precisely the undifferentiated prose the Aug 10 report was about.
struct MessageDraftViewer: View {
    let eyebrow: String
    let heading: String
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                MessageDraftEyebrow(text: eyebrow)
                Spacer(minLength: 12)
                MessageDraftCopyButton(text: text)
            }

            if !heading.isEmpty {
                Text(heading)
                    .font(.pixelSystem(size: MessageDraftStyle.subject, weight: .semibold))
                    .foregroundColor(CodepetTheme.primaryText)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 8)
            }

            Rectangle().fill(CodepetTheme.hairline).frame(height: 1)
                .padding(.vertical, 14)

            MessageDraftBody(text: text)

            // The footer earns its rule only when there is something to say — a message with
            // no blanks in it is finished, and should end on the words, not on a status line.
            if !MessagePlaceholders.labels(in: text).isEmpty {
                Rectangle().fill(CodepetTheme.hairline).frame(height: 1)
                    .padding(.vertical, 14)
                MessageDraftBlanksNote(text: text)
            }
        }
        .messageDraftCardChrome()
    }
}

extension View {
    /// The card itself — a hairline border rather than a shadow, so a column of messages reads
    /// as a stack of documents instead of a pile of floating chips.
    func messageDraftCardChrome() -> some View {
        self
            .padding(MessageDraftStyle.padding)
            .frame(maxWidth: MessageDraftStyle.measure, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: CodepetTheme.cardRadius, style: .continuous)
                    .fill(CodepetTheme.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: CodepetTheme.cardRadius, style: .continuous)
                    .strokeBorder(CodepetTheme.hairline, lineWidth: 1)
            )
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Body

/// Message prose: inline markdown, reading typography, blanks tinted.
struct MessageDraftBody: View {
    let text: String

    var body: some View {
        Text(MessagePlaceholders.attributed(text,
                                            tint: MessageDraftStyle.blankTint,
                                            ink: MessageDraftStyle.blankInk))
            .font(.pixelSystem(size: MessageDraftStyle.body))
            .lineSpacing(MessageDraftStyle.leading)
            .foregroundColor(CodepetTheme.bodyText)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Copy

/// Copy, with the confirmation the old button lacked — you could not tell it had fired.
struct MessageDraftCopyButton: View {
    let text: String
    @State private var copied = false
    @Environment(\.uiLanguage) private var lang

    var body: some View {
        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            withAnimation(.easeOut(duration: 0.15)) { copied = true }
            Task {
                try? await Task.sleep(for: .seconds(2))
                withAnimation(.easeOut(duration: 0.15)) { copied = false }
            }
        } label: {
            Label(copied ? (lang == .vi ? "Đã sao chép" : "Copied")
                         : (lang == .vi ? "Sao chép" : "Copy"),
                  systemImage: copied ? "checkmark" : "doc.on.doc")
        }
        .buttonStyle(CodepetPillButtonStyle(
            fill: copied ? CodepetTheme.accentGreen.opacity(0.14) : CodepetTheme.surface,
            foreground: copied ? CodepetTheme.accentGreen : CodepetTheme.mutedText,
            paddingH: 11, paddingV: 5,
            font: .pixelSystem(size: 11, weight: .semibold)))
        .accessibilityLabel(lang == .vi ? "Sao chép tin nhắn" : "Copy message")
    }
}

// MARK: - Blanks note

/// The line that says the draft is not sendable yet. Absent when there is nothing to fill in —
/// a card that always carries a status line teaches you to stop reading it.
struct MessageDraftBlanksNote: View {
    let text: String
    @Environment(\.uiLanguage) private var lang

    private var blanks: [String] { MessagePlaceholders.labels(in: text) }

    var body: some View {
        if !blanks.isEmpty {
            HStack(alignment: .firstTextBaseline, spacing: 7) {
                Circle()
                    .fill(CodepetTheme.accentGold)
                    .frame(width: 6, height: 6)
                Text(label)
                    .font(.pixelSystem(size: MessageDraftStyle.footnote, weight: .medium))
                    .foregroundColor(CodepetTheme.mutedText)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
        }
    }

    private var label: String {
        let joined = blanks.prefix(3).joined(separator: " ")
        let more = blanks.count > 3 ? " +\(blanks.count - 3)" : ""
        if lang == .vi {
            return "Cần điền trước khi gửi: \(joined)\(more)"
        }
        return blanks.count == 1
            ? "Fill in \(joined) before you send this"
            : "Fill in \(blanks.count) blanks before you send this — \(joined)\(more)"
    }
}

// MARK: - Eyebrow

/// The small uppercase kind label that makes a message readable as a message from across
/// the pane, before any of the words are.
struct MessageDraftEyebrow: View {
    let text: String

    var body: some View {
        Text(text.uppercased())
            .font(.pixelSystem(size: MessageDraftStyle.eyebrow, weight: .semibold))
            .tracking(0.8)
            .foregroundColor(CodepetTheme.accentPurple)
    }
}

// codepet/Views/Library/MessageDraftCard.swift
import SwiftUI

/// The chrome for deliverables you are meant to SEND — `.email` and `.dms`.
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
/// WHAT CHANGED SINCE: all three of those are now `DeliverableFrame`'s job, not this file's.
/// The eyebrow, the in-card action, the heading-over-a-hairline and the footer note were the
/// right answer for every deliverable, not just the two message kinds — and holding them here,
/// privately, is exactly why nine other viewers never got them. `MessageDraftStyle`'s numbers
/// were identical to `DocViewer.Doc`'s; both now live in `DeliverableStyle`. What remains here
/// is only what is genuinely specific to a message: the send verb on its blanks note.
enum MessageDraftStyle {
    /// Kept as the name the chat transcript reaches for when it tints blanks in loose prose.
    /// One standard, one set of numbers — see `DeliverableStyle`.
    static var blankTint: Color { DeliverableStyle.blankTint }
    static var blankInk: Color { DeliverableStyle.blankInk }
    static var subject: CGFloat { DeliverableStyle.heading }
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
    @Environment(\.uiLanguage) private var lang

    var body: some View {
        DeliverableFrame(
            eyebrow: eyebrow,
            heading: heading,
            action: .copy(text),
            footer: deliverableBlanksFooter(text, verb: .send, lang: lang)
        ) {
            DeliverableProse(text: text)
        }
    }
}

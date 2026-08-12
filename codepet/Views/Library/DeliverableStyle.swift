// codepet/Views/Library/DeliverableStyle.swift
import SwiftUI
import AppKit

/// The reading standard every deliverable is set in, and the primitives that carry it.
///
/// It already existed twice. `DocViewer.Doc` (Aug 7) and `MessageDraftStyle` (Aug 10) hold the
/// SAME four numbers — body 14, leading 7, measure 620, heading 15 — each declared privately
/// inside the one viewer that needed it, reachable by nothing else. So the nine viewers written
/// before those passes, and the ones written after, all re-decided typography from scratch and
/// all landed on the 11–13pt / zero-leading / uncapped setting the founder rejected for documents.
///
/// That is not nine oversights. It is one missing type. Restyling the viewers in place would fix
/// today's nine and leave the tenth to diverge again, so the standard is extracted here FIRST and
/// the viewers adopt it — including the two that already agreed with it, which now agree by
/// construction instead of by coincidence.
///
/// Three rules, inherited verbatim from the Aug 7 pass:
/// 1. Prose gets a reading measure — ~1.6em leading, and a column capped near 68 characters.
/// 2. A heading binds to what follows it and separates from what precedes it.
/// 3. A rule does the separating, so the gap between sections need not be huge to read as a break.
enum DeliverableStyle {
    /// The small uppercase kind label. Names what you are looking at before any of it is read.
    static let eyebrow: CGFloat = 10
    /// A section heading, and the message subject.
    static let heading: CGFloat = 15
    /// The lead paragraph of a document — the `call`.
    static let lead: CGFloat = 15
    /// Reading size. Everything a founder is meant to READ is set here, not smaller.
    static let body: CGFloat = 14
    /// ~1.6em on 14pt.
    static let leading: CGFloat = 7
    /// Footnotes, disclaimers, the blanks line. Quiet, but still legible.
    static let footnote: CGFloat = 11
    /// ~68 characters at `body`. Longer lines lose the eye on the return sweep, and these
    /// sheets can be dragged much wider than their 460pt minimum.
    static let measure: CGFloat = 620
    static let padding: CGFloat = 16

    static let headingToBody: CGFloat = 7
    static let betweenSections: CGFloat = 26

    /// The tint on `[name]`-style blanks — a founder cannot send a draft with these still in it,
    /// so they are the one thing in a body that must be visible without reading.
    static var blankTint: Color { CodepetTheme.accentGold.opacity(0.28) }
    static var blankInk: Color { CodepetTheme.primaryText }
}

// MARK: - Frame

/// What a deliverable needs the founder to act on: the primary action, in the card.
///
/// Copy used to sit BELOW the card in `EmailViewer`, where the Aug 10 note called it page
/// furniture and moved it in. `LegalViewer` and `PostViewer` were never brought along and still
/// trail a loose pill under a floating card. The frame settles it once: whatever the card's
/// primary action is, it sits on the eyebrow row, at the top-right, inside the edges.
enum DeliverableAction {
    /// No action — the content is the whole card (`.screens`).
    case none
    /// Copy this text to the pasteboard.
    case copy(String)
    /// Copy, relabelled — `.site` copies HTML, not prose, and saying so avoids the founder
    /// pasting markup where they wanted words.
    case copyLabelled(String, label: String, done: String)
}

/// The shared chrome for a deliverable: eyebrow + action, an optional heading over a hairline,
/// the content, and an optional footer note under a second hairline.
///
/// `heading` is optional because the two hosts differ. `DeliverableDetailView` already prints the
/// title in its own header bar, so a heading here would say it twice; the chat has no such bar,
/// which is why `MessageDraftViewer` passes one. The eyebrow is NOT optional — it is what makes a
/// plan readable as a plan from across the pane, and it is the whole point of the exercise.
///
/// `measured` is opt-out rather than opt-in: prose wants the 620pt cap, but a `WKWebView` landing
/// page, a screens grid and the sheet's slider model are laid out by their own internals and get
/// squeezed by it. They keep the type scale and the chrome and skip the cap.
struct DeliverableFrame<Content: View>: View {
    let eyebrow: String
    var heading: String = ""
    var action: DeliverableAction = .none
    var footer: String? = nil
    var measured: Bool = true
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                DeliverableEyebrow(text: eyebrow)
                Spacer(minLength: 12)
                actionButton
            }

            if !heading.isEmpty {
                Text(heading)
                    .font(.pixelSystem(size: DeliverableStyle.heading, weight: .semibold))
                    .foregroundColor(CodepetTheme.primaryText)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 8)
            }

            DeliverableRule().padding(.vertical, 14)

            content

            // The footer earns its rule only when there is something to say. A card that always
            // carries a status line teaches you to stop reading it — the Aug 10 rule, kept.
            if let footer, !footer.isEmpty {
                DeliverableRule().padding(.vertical, 14)
                DeliverableFootnote(text: footer)
            }
        }
        .deliverableCardChrome(measured: measured)
    }

    @ViewBuilder private var actionButton: some View {
        switch action {
        case .none:
            EmptyView()
        case let .copy(text):
            DeliverableCopyButton(text: text)
        case let .copyLabelled(text, label, done):
            DeliverableCopyButton(text: text, label: label, doneLabel: done)
        }
    }
}

// MARK: - Where the card is, and is not

/// False when something ELSE already frames this deliverable — set by `DeliverableBodyView`,
/// which only ever renders inside a sheet.
///
/// Founder call, Aug 5, already written down in `CopilotChatView`: *"A container earns its edges
/// when it bounds an OBJECT (a draft, a room, an exec log); prose is not an object, and the name
/// row above it already says where it came from."*
///
/// The card is RIGHT in the chat dock — a draft floats on a backdrop with loose prose around it,
/// and without edges it is the undifferentiated prose the Aug 10 report was about. It is WRONG in
/// the detail sheet, where the sheet is the container and its header bar already names the thing:
/// there the card is a second frame around content that is already framed (founder screenshot,
/// Aug 11 — sheet, then the PLAN card, then the Changes cards, three deep).
///
/// One component, two hosts, two answers. The first pass applied the chat answer to both.
private struct DeliverableCardChromeKey: EnvironmentKey {
    static let defaultValue = true
}

extension EnvironmentValues {
    var deliverableCardChrome: Bool {
        get { self[DeliverableCardChromeKey.self] }
        set { self[DeliverableCardChromeKey.self] = newValue }
    }
}

private struct DeliverableCardChrome: ViewModifier {
    let measured: Bool
    /// Non-nil forces the answer regardless of host — see `DmsViewer`.
    let forced: Bool?
    @Environment(\.deliverableCardChrome) private var fromHost

    private var carded: Bool { forced ?? fromHost }

    func body(content: Content) -> some View {
        content
            // Bare content takes the host's own page margins; only a card pads itself.
            .padding(carded ? DeliverableStyle.padding : 0)
            .frame(maxWidth: measured ? DeliverableStyle.measure : .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: CodepetTheme.cardRadius, style: .continuous)
                    .fill(carded ? CodepetTheme.surface : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: CodepetTheme.cardRadius, style: .continuous)
                    .strokeBorder(carded ? CodepetTheme.hairline : Color.clear, lineWidth: 1)
            )
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

extension View {
    /// The card itself — a hairline border rather than a shadow, so a column of deliverables
    /// reads as a stack of documents instead of a pile of floating chips.
    ///
    /// Drawn only where a container is not already doing the job; see `deliverableCardChrome`
    /// in the environment. `forced: true` overrides that for the one case where the cards are
    /// SIBLINGS rather than a single frame — `DmsViewer` draws one per recipient, and several
    /// messages stacked in a sheet need edges to say where one ends and the next begins.
    func deliverableCardChrome(measured: Bool = true, forced: Bool? = nil) -> some View {
        modifier(DeliverableCardChrome(measured: measured, forced: forced))
    }
}

// MARK: - Primitives

/// The small uppercase kind label that makes a deliverable readable as its kind before any of
/// the words are.
///
/// TWO RANKS, and they must not be the same colour. The card's kind eyebrow is accent; a SECTION
/// eyebrow inside the card is muted. Rendered with both in accent, a plan's "PLAN" and its
/// "GOAL"/"STEPS"/"CHANGES" were identical in size, weight, tracking and hue — so the label
/// naming the whole document did not outrank the labels dividing it, and the eye had no way to
/// tell the outer structure from the inner. Muting the inner rank costs nothing: inside the card
/// there is only one thing a small tracked uppercase line can be.
struct DeliverableEyebrow: View {
    let text: String
    var color: Color = CodepetTheme.accentPurple

    /// A section label inside a card — the second rank.
    static func section(_ text: String) -> DeliverableEyebrow {
        DeliverableEyebrow(text: text, color: CodepetTheme.mutedText)
    }

    var body: some View {
        Text(text.uppercased())
            .font(.pixelSystem(size: DeliverableStyle.eyebrow, weight: .semibold))
            .tracking(0.8)
            .foregroundColor(color)
    }
}

/// A hairline. Rule 3 of the reading standard: the rule separates, so the gap does not have to.
struct DeliverableRule: View {
    var body: some View {
        Rectangle().fill(CodepetTheme.hairline).frame(height: 1)
    }
}

/// A section heading inside a deliverable. Binds down to its own paragraph, separates from what
/// came before — which is why callers put the gap ABOVE it, never below.
struct DeliverableHeading: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.pixelSystem(size: DeliverableStyle.heading, weight: .semibold))
            .foregroundColor(CodepetTheme.primaryText)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// Prose, set to be read: reading size, ~1.6em leading, selectable, blanks tinted.
///
/// `tintBlanks` is on by default. A `[name]` buried mid-sentence is the one thing in a body the
/// founder must act on before the draft is usable, and that is as true of a post or a doc as it
/// is of an email — the Aug 10 pass just happened to reach messages first.
struct DeliverableProse: View {
    let text: String
    var tintBlanks: Bool = true
    var color: Color = CodepetTheme.bodyText

    var body: some View {
        Text(tintBlanks
             ? MessagePlaceholders.attributed(text,
                                              tint: DeliverableStyle.blankTint,
                                              ink: DeliverableStyle.blankInk)
             : AttributedString(text))
            .font(.pixelSystem(size: DeliverableStyle.body))
            .lineSpacing(DeliverableStyle.leading)
            .foregroundColor(color)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A quiet line under the final rule — a disclaimer, or what is still to fill in. Carries a dot
/// so it reads as a note about the card rather than the last sentence of it.
struct DeliverableFootnote: View {
    let text: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 7) {
            Circle()
                .fill(CodepetTheme.accentGold)
                .frame(width: 6, height: 6)
            Text(text)
                .font(.pixelSystem(size: DeliverableStyle.footnote, weight: .medium))
                .foregroundColor(CodepetTheme.mutedText)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Copy

/// Copy, with the confirmation the old buttons lacked — you could not tell they had fired.
struct DeliverableCopyButton: View {
    let text: String
    var label: String? = nil
    var doneLabel: String? = nil
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
            Label(copied ? (doneLabel ?? (lang == .vi ? "Đã sao chép" : "Copied"))
                         : (label ?? (lang == .vi ? "Sao chép" : "Copy")),
                  systemImage: copied ? "checkmark" : "doc.on.doc")
        }
        .buttonStyle(CodepetPillButtonStyle(
            fill: copied ? CodepetTheme.accentGreen.opacity(0.14) : CodepetTheme.surface,
            foreground: copied ? CodepetTheme.accentGreen : CodepetTheme.mutedText,
            paddingH: 11, paddingV: 5,
            font: .pixelSystem(size: 11, weight: .semibold)))
        .accessibilityLabel(label ?? (lang == .vi ? "Sao chép" : "Copy"))
    }
}

// MARK: - Blanks

/// What is still to fill in, and the verb for doing it.
///
/// The Aug 10 line was hardcoded to "before you send this", which is right for an email and wrong
/// for a post or a doc. The verb is the caller's, so the sentence stays true wherever the note is
/// reused — a post is published, a document is used.
enum BlankVerb {
    case send, post, use

    func line(_ blanks: [String], _ lang: AppLanguage) -> String {
        let joined = blanks.prefix(3).joined(separator: " ")
        let more = blanks.count > 3 ? " +\(blanks.count - 3)" : ""
        if lang == .vi {
            switch self {
            case .send: return "Cần điền trước khi gửi: \(joined)\(more)"
            case .post: return "Cần điền trước khi đăng: \(joined)\(more)"
            case .use:  return "Cần điền trước khi dùng: \(joined)\(more)"
            }
        }
        let tail: String
        switch self {
        case .send: tail = "you send this"
        case .post: tail = "you post this"
        case .use:  tail = "you use this"
        }
        return blanks.count == 1
            ? "Fill in \(joined) before \(tail)"
            : "Fill in \(blanks.count) blanks before \(tail) — \(joined)\(more)"
    }
}

/// The line that says a draft is not ready yet. Absent when there is nothing to fill in.
struct DeliverableBlanksNote: View {
    let text: String
    var verb: BlankVerb = .send
    @Environment(\.uiLanguage) private var lang

    private var blanks: [String] { MessagePlaceholders.labels(in: text) }

    var body: some View {
        if !blanks.isEmpty {
            DeliverableFootnote(text: verb.line(blanks, lang))
        }
    }
}

/// The blanks line as a plain string, for callers that hand a footer to `DeliverableFrame`
/// rather than composing the note themselves. `nil` when the draft has no blanks left.
func deliverableBlanksFooter(_ text: String, verb: BlankVerb, lang: AppLanguage) -> String? {
    let blanks = MessagePlaceholders.labels(in: text)
    guard !blanks.isEmpty else { return nil }
    return verb.line(blanks, lang)
}

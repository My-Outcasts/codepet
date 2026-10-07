import Foundation

/// What one past chat turn says when it is sent back to the model as history (CP-059).
///
/// A finished run lands in chat as a draft card: a companion message whose `text` is "" and
/// whose `draft` carries the deliverable. History went out as `text` alone, and the backend
/// drops blank turns (`buildMessages` in `companyChatCore.ts`), so the model saw its own
/// "Running X now — back here for approval" followed by nothing at all. Add the runnable gate's
/// "do not imply anything is being produced" on the next turn, and it concluded its run had
/// never happened: "a correction — I wasn't running it". Eight times in one chat on 5 Oct.
///
/// The note is in English whatever the founder's language: it is read by the model, never shown.
/// Client-only on purpose — the backend already replays any non-blank text, so no deploy.
///
/// Message cards (`draft_message`: an email, DM or text) ride along the same way, with their
/// words (7 Oct). Without them the model's "both versions are in the cards" was followed by no
/// cards, and "make the email shorter" had nothing to revise. Each body is capped so one long
/// email does not travel in full on every later turn.
enum ChatHistoryWire {
    static let cardBodyCap = 1_200

    static func text(for message: CopilotMessage) -> String {
        var notes: [String] = []
        if let draft = message.draft {
            let state = message.draftApproved
                ? "the founder approved it and it is filed in the Library"
                : "it is waiting for the founder's approval"
            notes.append("[You produced a \(draft.kind.rawValue) draft here: \"\(draft.title)\" — \(state).]")
        }
        notes += message.drafts.map(cardNote)
        guard !notes.isEmpty else { return message.text }
        let text = message.text.trimmingCharacters(in: .whitespacesAndNewlines)
        return ([text].filter { !$0.isEmpty } + notes).joined(separator: "\n\n")
    }

    /// "[You drafted an email card here, to Building manager, subject "…":\n<body>]"
    private static func cardNote(_ d: MessageDraftDTO) -> String {
        let channel = ["email": "an email", "text": "a text message"][d.channel] ?? "a message"
        var head = "You drafted \(channel) card here"
        if let to = d.to?.trimmingCharacters(in: .whitespacesAndNewlines), !to.isEmpty { head += ", to \(to)" }
        if let subject = d.subject?.trimmingCharacters(in: .whitespacesAndNewlines), !subject.isEmpty {
            head += ", subject \"\(subject)\""
        }
        let body = d.body.count > cardBodyCap ? String(d.body.prefix(cardBodyCap)) + "…" : d.body
        return "[\(head):\n\(body)]"
    }
}

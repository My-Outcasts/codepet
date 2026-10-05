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
enum ChatHistoryWire {
    static func text(for message: CopilotMessage) -> String {
        guard let draft = message.draft else { return message.text }
        let state = message.draftApproved
            ? "the founder approved it and it is filed in the Library"
            : "it is waiting for the founder's approval"
        let note = "[You produced a \(draft.kind.rawValue) draft here: \"\(draft.title)\" — \(state).]"
        let text = message.text.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? note : text + "\n\n" + note
    }
}

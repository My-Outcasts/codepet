// codepet/Views/Copilot/WalkthroughAsk.swift
import Foundation

/// The message text for "walk me through this task" and the task it is about, bound together.
///
/// **Why this exists.** The two facts have to travel together — `speakerFor(task:text:department:)`
/// tries the task's own department before falling back to keyword inference over the text, and
/// "Walk me through: <title>" names no department in either language. Drop the task and the
/// reply gets signed with the product name, or an unrelated department's pet, instead of the
/// task's own. That exact mistake shipped twice, once per call site — `MockFlowPlayer`'s
/// `.walkthroughFounderTask` beat (`329891a`) and `CopilotChatView.runBeacon`'s `.walkthrough`
/// case (`a4b7a16`) — because each site composed the string and forwarded `aboutTask` as two
/// separate statements, and nothing enforced that they stayed in sync.
///
/// `compose` is the one place this string is built. Before this type, `CopilotChatView` and
/// `MockFlowPlayer` each wrote `"Walk me through: \(task.title)"` / `"Hướng dẫn tôi làm:
/// \(task.title)"` independently — identical wording, verified against both call sites, now
/// unified so the two paths cannot diverge in it either.
///
/// A pure static value, the sibling of `DraftCardCopy.shouldShowNotFiledNote` and
/// `DraftPayloadPreview.hasStructuredPreview`: the decision (here, the pairing) is where a bug
/// would live, and it is testable without a view.
struct WalkthroughAsk {
    /// The composed message, in the founder's language — what lands in `chatDraft` and is sent
    /// as the chat turn's text.
    let text: String
    /// The task the message is about — carried alongside `text` so a caller cannot forward one
    /// without the other. This is what `sendChat`'s `aboutTask:` needs to resolve the reply's
    /// speaker from a recorded fact instead of a keyword guess.
    let task: RoadmapTask

    static func compose(for task: RoadmapTask, language: AppLanguage) -> WalkthroughAsk {
        let text = language == .vi
            ? "Hướng dẫn tôi làm: \(task.title)"
            : "Walk me through: \(task.title)"
        return WalkthroughAsk(text: text, task: task)
    }
}

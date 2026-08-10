// codepet/Models/RoadmapProposal.swift
import Foundation

/// A change to the roadmap that Codepet is offering to make, awaiting the founder's press.
///
/// Founder, Aug 8: the chat should be the central brain, and the roadmap should follow it. Before
/// this the chat had four verbs — run an existing task, navigate, enable a toolkit item, remember a
/// fact — and none of them touched the roadmap. It could DO a task that existed and point at the
/// board; it could not create one or complete one. That is why the companion said "you can consider
/// this step done" and then handed over a navigation chip: the capability was missing, so the
/// honest grounding had to forbid the sentence rather than the sentence being true.
///
/// Nothing here applies itself. A model that can silently rewrite a roadmap is worse than one that
/// cannot touch it — one wrong completion and the founder's progress is fiction — so both verbs
/// land as a proposal the founder confirms, the same bargain `RunProposal` makes before spending
/// credits.
enum RoadmapProposal: Equatable {
    /// Mark a task the founder says they finished as done.
    case complete(taskId: String, title: String)
    /// Add a task that is not on the roadmap yet. Always a LEAF in the current phase — founder's
    /// call, Aug 8, when asked whether chat-created tasks should be able to express dependencies:
    /// "start with no". A model guessing at a dependency graph is how a roadmap becomes unusable.
    case add(NewTask)

    struct NewTask: Equatable {
        let title: String
        let detail: String
        /// A `DepartmentCatalog` key, or nil when the model could not place it.
        let dept: String?
        /// True when Codepet could draft it; false when only the founder can do it.
        let codepetOwned: Bool
    }

    /// The sentence Codepet says above the button.
    func line(_ lang: AppLanguage) -> String {
        switch self {
        case .complete(_, let title):
            return lang == .vi
                ? "Mình đánh dấu \"\(title)\" là xong nhé?"
                : "Want me to mark \"\(title)\" done?"
        case .add(let task):
            return lang == .vi
                ? "Mình thêm \"\(task.title)\" vào lộ trình nhé?"
                : "Want me to add \"\(task.title)\" to the roadmap?"
        }
    }

    /// The confirm button. Names the act and the subject, so it still reads correctly once the
    /// sentence above it has scrolled away.
    func buttonLabel(_ lang: AppLanguage) -> String {
        switch self {
        case .complete(_, let title):
            return (lang == .vi ? "Đánh dấu xong: " : "Mark done: ") + title
        case .add(let task):
            return (lang == .vi ? "Thêm: " : "Add: ") + task.title
        }
    }

    /// What the transcript says once it has been applied — kept rather than removed, so the
    /// conversation records that the roadmap changed and on whose say-so.
    func doneLabel(_ lang: AppLanguage) -> String {
        switch self {
        case .complete:
            return lang == .vi ? "Đã đánh dấu xong" : "Marked done"
        case .add:
            return lang == .vi ? "Đã thêm vào lộ trình" : "Added to the roadmap"
        }
    }
}

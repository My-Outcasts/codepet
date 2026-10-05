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
    /// Several new tasks from one message, confirmed with ONE press (CP-060). 5 Oct, build 7:
    /// asked for eight tasks, the reply promised "all eight are queued as buttons" and showed one
    /// "Yes, add it", which added the first. Founder's pick, 5 Oct: one list and an "Add all N"
    /// button. Always 2+ tasks — a single task stays `.add`, word for word.
    case addAll([NewTask])
    /// Make a new version of work the founder already approved (CP-025). Not a roadmap change at
    /// all — it re-runs the item's own task with the founder's note, and approving the result
    /// replaces the Library item in place. It rides this enum so it gets the same card, the same
    /// one-offer guard and the same consume-before-run confirm, rather than a parallel copy of
    /// each; before it existed, a revision could only arrive as `add`, which is the bug.
    case revise(libraryId: String, title: String, note: String)

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
        case .addAll(let tasks):
            return lang == .vi
                ? "Mình thêm \(tasks.count) việc này vào lộ trình nhé?"
                : "Want me to add these \(tasks.count) tasks to the roadmap?"
        case .revise(_, let title, _):
            return lang == .vi
                ? "Mình làm phiên bản mới cho \"\(title)\" nhé?"
                : "Want me to make a new version of \"\(title)\"?"
        }
    }

    /// The confirm button.
    ///
    /// Short, and deliberately NOT repeating the task name. The sentence directly above it already
    /// names the task, and printing it again on the button put the same words on two adjacent
    /// lines — half of what read as disjointed (founder, Aug 10). The button sits under its own
    /// question, so "Yes, mark it done" is unambiguous where it lives.
    func buttonLabel(_ lang: AppLanguage) -> String {
        switch self {
        case .complete:
            return lang == .vi ? "Ừ, đánh dấu xong" : "Yes, mark it done"
        case .add:
            return lang == .vi ? "Ừ, thêm vào" : "Yes, add it"
        case .addAll(let tasks):
            return lang == .vi ? "Thêm cả \(tasks.count)" : "Add all \(tasks.count)"
        case .revise:
            return lang == .vi ? "Ừ, làm bản mới" : "Yes, make a new version"
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
        case .addAll(let tasks):
            return lang == .vi ? "Đã thêm \(tasks.count) việc vào lộ trình" : "Added \(tasks.count) tasks to the roadmap"
        case .revise:
            return lang == .vi ? "Đang làm bản mới" : "Making a new version"
        }
    }
}

/// How much of an "Add all N" list the card shows (CP-060). The founder approved the version that
/// shows three and counts the rest, so the card stays one glance however long the list is.
enum AddAllListLayout {
    static let visible = 3

    static func shown(_ tasks: [RoadmapProposal.NewTask]) -> [RoadmapProposal.NewTask] {
        Array(tasks.prefix(visible))
    }

    static func moreLabel(_ tasks: [RoadmapProposal.NewTask], _ lang: AppLanguage) -> String? {
        let rest = tasks.count - visible
        guard rest > 0 else { return nil }
        return lang == .vi ? "…và \(rest) việc nữa" : "…\(rest) more"
    }
}

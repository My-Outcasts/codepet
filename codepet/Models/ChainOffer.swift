// codepet/Models/ChainOffer.swift
import Foundation

/// A run whose dependency has produced nothing yet, offered as a choice before it happens.
///
/// **When this appears.** Only for a task that is already runnable — `RoadmapEngine.status`
/// still refuses a genuinely blocked one — but whose `dependsOn` points at a task with no
/// deliverable behind it. In practice that is a prerequisite the founder marked done
/// themselves: the arrow is on the roadmap and there is nothing at the end of it, so the
/// downstream department would write in the dark and never say so.
///
/// **Why it is a choice and not automatic.** Running the upstream task spends credits on work
/// the founder did not ask for. Doing that silently is worse than asking, and asking is cheap
/// here because the alternative — running alone — is still a perfectly good answer.
///
/// The two labels are deliberately not "Yes"/"No": both options run something, and a founder
/// reading fast needs to see WHICH work each one does.
struct ChainOffer: Equatable {
    let taskId: String
    let taskTitle: String
    let upstreamTaskId: String
    let upstreamTaskTitle: String
    /// The upstream department and its pet — nil for a dept-less task.
    let upstreamDeptName: String?
    let upstreamPetName: String?

    /// The sentence. Names what is missing and what it would be used for, because the founder
    /// has not been looking at the dependency graph and should not have to.
    func line(_ lang: AppLanguage) -> String {
        let who = [upstreamPetName, upstreamDeptName].compactMap { $0 }
            .first { !$0.isEmpty }
        if lang == .vi {
            let owner = who.map { "\($0) " } ?? ""
            return "\"\(taskTitle)\" dựa trên \"\(upstreamTaskTitle)\", mà \(owner)chưa làm xong. "
                + "Mình có thể làm cái đó trước rồi dùng nó, hoặc làm thẳng cái bạn hỏi."
        }
        // Lower-case: it lands mid-sentence, after "and".
        let owner = who.map { "\($0) hasn't" } ?? "nobody has"
        return "\"\(taskTitle)\" builds on \"\(upstreamTaskTitle)\", and \(owner) produced it yet. "
            + "I can do that first and build on it, or go straight at what you asked for."
    }

    func bothLabel(_ lang: AppLanguage) -> String {
        lang == .vi ? "Làm cả hai" : "Run both"
    }

    func aloneLabel(_ lang: AppLanguage) -> String {
        lang == .vi ? "Chỉ cái này" : "Just mine"
    }

    /// What replaces the buttons once one is pressed — the transcript keeps the record of
    /// which way the founder went, the way `runProposalCard` does.
    func doneLabel(_ lang: AppLanguage, chained: Bool) -> String {
        if chained { return lang == .vi ? "Đang làm cả hai" : "Running both" }
        return lang == .vi ? "Chỉ làm cái này" : "Running just this one"
    }
}

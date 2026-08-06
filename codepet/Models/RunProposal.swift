// codepet/Models/RunProposal.swift
import Foundation

/// A run the founder started from a surface, offered in chat before it happens.
///
/// The web does this and the native port skipped it (verified live on
/// codepet-ver-1-2.vercel.app, Aug 6): clicking `Start` on a roadmap card does not run
/// anything — the copilot opens and says *"Let's do "Stand up help center" in Support — ready
/// when you are"* with a `Start: <task>` button, and only that button runs the task.
///
/// Two things that step buys, which running-on-click cannot:
///
/// 1. **A click is not a request.** A tap on a card the founder was reading — or a mis-aimed
///    tap, which the hit-area work made more likely to land — spent credits and produced a
///    deliverable with no way back. The confirmation is where "review before it runs" lives.
/// 2. **It names who will do it before they do it.** The proposal carries the department and its
///    specialist, so the handoff is legible before the work starts rather than only in the log.
///
/// Chat-initiated runs are deliberately NOT proposed: typing "draft the pricing plan" already
/// IS the request, and asking a second time would read as not listening.
struct RunProposal: Equatable {
    let taskId: String
    let title: String
    /// The department that will do the work — nil for a task with no department.
    let deptName: String?
    /// The department specialist's `PetCharacter` id, paired with `deptName`.
    let companionId: String?

    /// The proposal sentence, matching the web's phrasing.
    func line(_ lang: AppLanguage) -> String {
        if let deptName {
            return lang == .vi
                ? "Cùng làm \"\(title)\" ở \(deptName) nhé — sẵn sàng khi bạn muốn."
                : "Let's do \"\(title)\" in \(deptName) — ready when you are."
        }
        return lang == .vi
            ? "Cùng làm \"\(title)\" nhé — sẵn sàng khi bạn muốn."
            : "Let's do \"\(title)\" — ready when you are."
    }

    /// The confirm button's label — the verb plus the task, so the button says what it does even
    /// when the sentence above it has scrolled away.
    func buttonLabel(_ lang: AppLanguage) -> String {
        (lang == .vi ? "Bắt đầu: " : "Start: ") + title
    }
}

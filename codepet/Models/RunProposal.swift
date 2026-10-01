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
    /// Offered after a failed run (CP-002 F): the same task again, labelled "Try again".
    var retry: Bool = false

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

    /// The confirm button.
    ///
    /// Short, matching `RoadmapProposal`: the sentence above already names the task, and repeating
    /// it on the button put the same words on two adjacent lines. Aligned on Aug 10 rather than
    /// left as a second pattern — the founder flagged the shape on the roadmap card, and this card
    /// had exactly the same one.
    func buttonLabel(_ lang: AppLanguage) -> String {
        if retry { return lang == .vi ? "Thử lại" : "Try again" }
        return lang == .vi ? "Ừ, bắt đầu đi" : "Yes, start it"
    }
}

/// What the chat says when a run fails the Failed rule (CP-002 F, copy approved 1 Oct): who did
/// not make what, and that nothing was saved. It does NOT say nothing was spent — the run used
/// the founder's Claude plan, and a sentence claiming otherwise would be the app inventing a fact.
enum RunFailureCopy {
    static func line(kind: String, deptName: String?, lang: AppLanguage) -> String {
        let (noun, part): (String, String) = {
            switch (kind, lang) {
            case ("sheet", .vi):    return ("mô hình tài chính", "phần mô hình")
            case ("sheet", _):      return ("financial model", "the model itself")
            case ("site", .vi):     return ("trang đích", "phần trang")
            case ("site", _):       return ("landing page", "the page itself")
            case ("calendar", .vi): return ("kế hoạch", "phần kế hoạch")
            case ("calendar", _):   return ("plan", "the plan itself")
            case ("screens", .vi):  return ("các màn hình", "phần màn hình")
            case ("screens", _):    return ("onboarding screens", "the screens themselves")
            case (_, .vi):          return ("bản nháp", "nội dung")
            default:                return ("draft", "its content")
            }
        }()
        if lang == .vi {
            return "\(deptName ?? "Codepet") chưa hoàn thành được \(noun): câu trả lời thiếu \(part), nên chưa có gì được lưu vào Thư viện."
        }
        return "\(deptName ?? "Codepet") couldn't finish the \(noun): its answer was missing \(part), so nothing was saved to your Library."
    }
}

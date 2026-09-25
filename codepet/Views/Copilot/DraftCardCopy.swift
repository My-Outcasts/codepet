// codepet/Views/Copilot/DraftCardCopy.swift
import Foundation

/// Copy and one decision for the draft card, kept out of the view so the suite can pin them.
///
/// **Why the note exists.** "Nothing is committed until you approve it" is the product's
/// governing promise, and the app stated it BEFORE a run (`BeaconOffer`: "you approve before it
/// is filed") and confirmed it AFTER ("Added to Library") — with nothing in between. So at the
/// one moment it becomes concrete, the founder was looking at a finished-LOOKING deliverable
/// beside a button marked Approve, with no indication it was unsaved.
enum DraftCardCopy {

    /// Whether to tell the founder this draft is not filed yet.
    ///
    /// **A pure static, not a condition in `draftCard`'s body.** Same reasoning as
    /// `DraftPayloadPreview.hasStructuredPreview`: the decision is where a bug here would live,
    /// and a decision inside a `View` body is only testable by rendering it.
    ///
    /// `hasApproved` is `company.firstApprovalAt != nil` — it retires because the rule was
    /// LEARNED, not because a counter ran out. `draftApproved` suppresses it on a card that
    /// already says "Added to Library": two answers to one question is worse than none.
    static func shouldShowNotFiledNote(hasApproved: Bool, draftApproved: Bool) -> Bool {
        !hasApproved && !draftApproved
    }

    /// The note itself. Wording fixed by
    /// `docs/superpowers/specs/2026-09-04-first-run-approval-note-design.md`.
    ///
    /// "Not saved yet" rather than "Not approved yet": the founder can see it is unapproved —
    /// the Approve button is right there. What they cannot see is that unapproved means unsaved.
    /// What the card says after Approve. A revision REPLACES a Library item (CP-025), so
    /// "Added" would be untrue there — found in the 25 Sep in-app check. `replacedItem` is what
    /// approval actually did (`CopilotMessage.draftReplacedItem`), not whether the draft merely
    /// pointed at an item.
    static func approvedLabel(_ lang: AppLanguage, replacedItem: Bool) -> String {
        if replacedItem {
            return lang == .vi ? "Đã cập nhật trong Thư viện" : "Updated in your Library"
        }
        return lang == .vi ? "Đã thêm vào Thư viện" : "Added to Library"
    }

    static func notFiledNote(_ lang: AppLanguage) -> String {
        lang == .vi
            ? "Chưa lưu — duyệt để đưa vào Thư viện."
            : "Not saved yet — approving files it in your Library."
    }

    // MARK: - What next, after "Added to Library"

    /// What the founder should do once a draft is filed. Before this, the card ended on
    /// "Added to Library" and nothing else — the founder read a finished art direction and did
    /// not know whether to wait, type, or go somewhere (founder, 2026-09-25).
    enum NextStep: Equatable {
        /// A task the team can run now — offered with a Run button.
        case run(RoadmapTask)
        /// The next task is the founder's own (`who == .you`).
        case yours(RoadmapTask)
        /// A draft is already waiting on the founder's review.
        case review(RoadmapTask)
        /// Nothing unblocked: the open phase is done or waiting on something.
        case none
    }

    /// The roadmap's own beacon (`RoadmapEngine.nextStep`), classified by the same `status` the
    /// board draws, so the card and the Roadmap never point at different things.
    static func nextStep(in tasks: [RoadmapTask]) -> NextStep {
        guard let t = RoadmapEngine.nextStep(tasks) else { return .none }
        switch RoadmapEngine.status(for: t, in: tasks) {
        case .codepetCanDo:  return .run(t)
        case .needsYou:      return .yours(t)
        case .needsApproval: return .review(t)
        default:             return .none
        }
    }

    /// Only the most recently filed draft carries the next step — otherwise every approved card
    /// in the transcript would repeat it, each pointing at the same task.
    static func isLatestFiled(_ id: String, in messages: [CopilotMessage]) -> Bool {
        messages.last(where: { $0.draft != nil && $0.draftApproved })?.id == id
    }

    static func nextLine(_ step: NextStep, deptName: (String?) -> String?, _ lang: AppLanguage) -> String {
        let vi = lang == .vi
        func who(_ t: RoadmapTask) -> String { deptName(t.dept).map { " — \($0)" } ?? "" }
        switch step {
        case .run(let t):
            return vi ? "Tiếp theo: \(t.title)\(who(t)). Bấm Chạy để cả đội làm tiếp."
                      : "Next: \(t.title)\(who(t)). Press Run and the team picks it up."
        case .yours(let t):
            return vi ? "Tiếp theo là việc của bạn: \(t.title). Làm xong thì đánh dấu trên Lộ trình."
                      : "Next is yours: \(t.title). Mark it done on the Roadmap when you have."
        case .review(let t):
            return vi ? "Còn một bản nháp chờ bạn duyệt: \(t.title)."
                      : "A draft is waiting for your review: \(t.title)."
        case .none:
            return vi ? "Không còn việc nào mở khoá lúc này. Nhắn cho mình việc bạn muốn làm tiếp, hoặc bấm Cả đội làm để build nó."
                      : "Nothing else is unblocked right now. Tell me what you want next, or press Team build to build it."
        }
    }
}

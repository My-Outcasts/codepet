// codepet/Models/RoadmapBoardCopy.swift
import Foundation

/// Pure copy + presentation rules for a roadmap board card, ported from the web
/// `RoadmapView.tsx` (VERB, STATUS, the locked tray marker, herePhrase). Kept out of the
/// views so the wording is unit-tested and can't drift from web.
enum RoadmapBoardCopy {
    /// Actionable states earn a verb the founder can act on; done/locked stay quiet labels.
    static func verb(for status: TaskStatus, _ lang: AppLanguage) -> String? {
        switch status {
        case .codepetCanDo:  return lang == .vi ? "Bắt đầu" : "Start"
        case .needsApproval: return lang == .vi ? "Duyệt" : "Review"
        case .needsYou:      return lang == .vi ? "Cần bạn" : "Add your input"
        case .done, .blocked: return nil
        }
    }

    /// The plain-language status line shown INSTEAD of a chip — web renders done/locked as
    /// text, not a pill. Returns nil for any state that has a verb chip.
    static func quietLabel(for status: TaskStatus, lang: AppLanguage) -> String? {
        switch status {
        case .done:    return lang == .vi ? "Xong" : "Done"
        case .blocked: return lang == .vi ? "Cần bước trước" : "Needs earlier steps"
        case .codepetCanDo, .needsYou, .needsApproval: return nil
        }
    }

    /// The small deliverable/output marker in a card's top-right — locked cards only.
    static func showsTrayMarker(_ status: TaskStatus) -> Bool { status == .blocked }

    /// The hover peek's status sentence — what the state means, plus what tapping the card now
    /// does. Tapping opens `TaskNodePanel`; it no longer fires the task's action, so every
    /// clause here reads "tap/click to see/open the panel", never "click to start/add/open the
    /// result" — those promises describe the OLD one-tap-runs-it behaviour.
    ///
    /// `isCurrent` only matters for `.codepetCanDo` — it distinguishes the single beacon card
    /// ("…'s next move") from a merely-runnable one ("… can run this now"); every other status
    /// has one sentence regardless of `isCurrent`.
    static func peekAction(for status: TaskStatus, isCurrent: Bool, companionName: String,
                           lang: AppLanguage) -> String {
        switch status {
        case .codepetCanDo:
            if isCurrent {
                return lang == .vi ? "Nước đi tiếp theo của \(companionName). Nhấn để xem chi tiết."
                                   : "\(companionName)'s next move. Click to see details."
            }
            return lang == .vi ? "\(companionName) có thể làm ngay bây giờ. Nhấn để xem chi tiết."
                               : "\(companionName) can run this now. Click to see details."
        case .needsYou:
            return lang == .vi ? "Cần bạn nhập. Nhấn để xem cách làm."
                               : "Your input needed. Click to see how."
        case .needsApproval:
            return lang == .vi ? "Bản nháp đã sẵn sàng. Nhấn để xem lại."
                               : "Ready for your review. Click to open it."
        case .done:
            return lang == .vi ? "Xong. Nhấn để xem chi tiết." : "Finished. Click to see details."
        case .blocked:
            return lang == .vi ? "Cần hoàn thành các bước trước. Nhấn để xem lý do."
                               : "Locked — finish the earlier steps first. Click to see why."
        }
    }

    /// The beacon marks where the FOUNDER stands — named when we have it, second person
    /// otherwise. Composed (not "{label} is here") so the fallback reads "You are here".
    static func herePhrase(founderName: String?, lang: AppLanguage) -> String {
        let n = (founderName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if n.isEmpty { return lang == .vi ? "Bạn đang ở đây" : "You are here" }
        return lang == .vi ? "\(n) đang ở đây" : "\(n) is here"
    }

    /// Why a locked card is locked, naming the step that must land first — so a locked card
    /// explains itself in the peek without the founder opening chat.
    static func waitingOn(_ blockerTitle: String, lang: AppLanguage) -> String {
        lang == .vi ? "Đang chờ: \(blockerTitle)" : "Waiting on: \(blockerTitle)"
    }

    /// A phase the plan never filled. Its rail says this instead of a bare 0/0, which reads
    /// like a bug rather than an absence.
    static func notPlannedYet(_ lang: AppLanguage) -> String {
        lang == .vi ? "Chưa lên kế hoạch" : "Not planned yet"
    }

    // MARK: node panel

    /// What finishing this node moves forward. Deliberately a PER-PHASE contract, not a
    /// per-task one: without authored per-node fields we cannot honestly say what one task
    /// makes true, and a truthful phase-level statement beats an invented task-level one. The
    /// sentence always names its phase so the panel can't read as generic filler.
    static func becomesTrue(_ phase: RoadmapPhase, _ lang: AppLanguage) -> String {
        let s: String
        switch phase {
        case .find:
            s = lang == .vi ? "bạn biết ai cần cái này và vì sao" : "you know who wants this and why"
        case .foundation:
            s = lang == .vi ? "những mảnh mà giai đoạn Xây dựng phụ thuộc vào đã có"
                            : "the pieces Build depends on exist"
        case .build:
            s = lang == .vi ? "sản phẩm tồn tại và chạy được" : "the product exists and runs"
        case .ship:
            s = lang == .vi ? "nó triển khai được, có tài liệu và bảo vệ được"
                            : "it's deployable, documented and defensible"
        case .launch:
            s = lang == .vi ? "nó đã công khai và tiếp cận được" : "it's public and reachable"
        case .grow:
            s = lang == .vi ? "nó lớn lên mà không cần bạn cầm tay từng bước"
                            : "it keeps growing without you steering every step"
        }
        let p = phase.label(lang)
        return lang == .vi ? "Hoàn thành việc này đẩy \(p) tiến lên: \(s)."
                           : "Finishing this moves \(p) forward: \(s)."
    }

    /// What "done" means for this node, from who owns it.
    static func toComplete(for who: TaskWho, _ lang: AppLanguage) -> String {
        switch who {
        case .does:  return lang == .vi ? "Codepet làm, bạn duyệt kết quả."
                                        : "Codepet runs it; you approve the result."
        case .draft: return lang == .vi ? "Codepet soạn bản nháp, bạn hoàn thiện."
                                        : "Codepet drafts it; you finalise."
        case .you:   return lang == .vi ? "Việc này bạn làm — Codepet sẽ hướng dẫn từng bước."
                                        : "You do this one — Codepet will walk you through it."
        }
    }

    /// Stand-in for "how to move this forward" when the generated task has no `detail`.
    static func howToFallback(for status: TaskStatus, _ lang: AppLanguage) -> String {
        switch status {
        case .codepetCanDo:  return lang == .vi ? "Codepet chạy được ngay bây giờ."
                                                : "Codepet can run this now."
        case .needsYou:      return lang == .vi ? "Cần bạn quyết — mở chat để được hướng dẫn."
                                                : "This needs your judgment — open chat to be walked through it."
        case .needsApproval: return lang == .vi ? "Bản nháp đã sẵn sàng để bạn xem lại."
                                                : "A draft is ready for your review."
        case .done:          return lang == .vi ? "Đã xong." : "Already done."
        case .blocked:       return lang == .vi ? "Xong các bước bên dưới trước."
                                                : "Clear the steps below first."
        }
    }

    /// The phase-window requirement's label — which phase has to settle before this node opens.
    static func phaseMustSettle(_ phase: RoadmapPhase, _ lang: AppLanguage) -> String {
        lang == .vi ? "\(phase.label(lang)) phải xong trước"
                    : "\(phase.label(lang)) must be settled first"
    }

    /// The panel's primary button. Unlike `verb(for:)` this covers EVERY status: the card leaves
    /// done and blocked chip-less on purpose, but the panel always offers a way forward.
    static func panelActionLabel(for status: TaskStatus, _ lang: AppLanguage) -> String {
        switch status {
        case .codepetCanDo:  return lang == .vi ? "Bắt đầu" : "Start"
        case .needsYou:      return lang == .vi ? "Thêm ý của bạn" : "Add your input"
        case .needsApproval: return lang == .vi ? "Xem & duyệt" : "Review"
        case .done:          return lang == .vi ? "Mở kết quả" : "Open the result"
        case .blocked:       return lang == .vi ? "Làm bước đang chặn" : "Start what's blocking this"
        }
    }

    static func markComplete(_ lang: AppLanguage) -> String {
        lang == .vi ? "Mình đã làm việc này rồi" : "I already did this"
    }

    /// The undo for `markComplete` — without it, marking a task done by mistake is a one-way
    /// door, since the mark-complete button hides itself once the task is done.
    static func markNotDone(_ lang: AppLanguage) -> String {
        lang == .vi ? "Chưa xong — mở lại" : "Not done after all"
    }

    static func inProgress(_ lang: AppLanguage) -> String {
        lang == .vi ? "Đang chạy" : "In progress"
    }

    /// Why a suggestion is worth doing next. Derived, not authored: the unlock count is a
    /// structural leverage signal, which is honest in a way invented prose wouldn't be.
    static func suggestionReason(dept: String?, unlockCount: Int, lang: AppLanguage) -> String {
        let d = dept ?? (lang == .vi ? "Chung" : "General")
        if unlockCount == 0 {
            return lang == .vi ? "\(d) · chưa có bước nào chờ nó"
                               : "\(d) · nothing else waits on it yet"
        }
        if unlockCount == 1 {
            return lang == .vi ? "\(d) · mở khoá 1 bước sau" : "\(d) · unlocks 1 later step"
        }
        return lang == .vi ? "\(d) · mở khoá \(unlockCount) bước sau"
                           : "\(d) · unlocks \(unlockCount) later steps"
    }

    /// What a collapsed rail prints where its count goes.
    ///
    /// An unplanned phase (`total == 0`) used to print NOTHING — the count was
    /// simply omitted, so the rail was structurally identical to one whose number
    /// had failed to render, and the only explanation lived in a hover tooltip
    /// nobody finds. It now prints an em dash: a visible "no work here yet" that
    /// can't be mistaken for a missing value, and that keeps every rail's count
    /// slot occupied so the row reads as one rhythm.
    static func railCount(done: Int, total: Int) -> String {
        total == 0 ? "—" : "\(done)/\(total)"
    }
}

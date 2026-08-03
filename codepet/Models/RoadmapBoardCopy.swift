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

// codepet/Models/DepartmentPulse.swift
import Foundation

/// The companion's one line on a department page, derived from that department's live tasks.
///
/// It replaces the static `Department.focus` render, which restated `rationale` almost verbatim
/// ("Build and ship the product itself…" / "This is where the thing you're building actually
/// gets made."). `focus` itself stays in the catalog — `ChatContext` grounds chat with it.
///
/// `mine` is the department's tasks; `all` is the whole board, because both `RoadmapEngine.status`
/// and `RoadmapGating.blocker` depend on tasks in OTHER departments — a dependency, or the
/// founder step holding the phase window shut.
///
/// Returns nil when NO line should render: a dormant department would otherwise show a sprite
/// next to nothing. Pure — no store, no view types.
func departmentPulse(_ dept: Department, mine: [RoadmapTask], all: [RoadmapTask],
                     lang: AppLanguage) -> String? {
    if mine.isEmpty { return nil }
    let open = mine.filter { !$0.done }
    if open.isEmpty {
        return lang == .vi ? "Xong hết trong \(dept.name)." : "All clear in \(dept.name)."
    }
    let statuses = open.map { (task: $0, status: RoadmapEngine.status(for: $0, in: all)) }

    // Precedence mirrors what the founder can act on soonest: their approval, then their own
    // step, then work Codepet can start, and only then the wait.
    let approving = statuses.filter { $0.status == .needsApproval }.count
    if approving == 1 {
        return lang == .vi ? "Có một bản nháp chờ bạn duyệt."
                           : "One thing's ready for you to approve."
    }
    if approving > 1 {
        return lang == .vi ? "\(approving) bản nháp chờ bạn duyệt."
                           : "\(approving) ready for you to approve."
    }
    let yours = statuses.filter { $0.status == .needsYou }.count
    if yours == 1 {
        return lang == .vi ? "Một việc ở đây cần bạn." : "One here needs you."
    }
    if yours > 1 {
        return lang == .vi ? "\(yours) việc ở đây cần bạn." : "\(yours) here need you."
    }
    let runnable = statuses.filter { $0.status == .codepetCanDo }.count
    if runnable == 1 {
        return lang == .vi ? "Không có gì chặn — tôi chạy được việc này ngay."
                           : "Nothing blocked — I can run this one now."
    }
    if runnable > 1 {
        return lang == .vi ? "Không có gì chặn — tôi chạy được \(runnable) việc ngay."
                           : "Nothing blocked — I can run \(runnable) of these now."
    }
    // Everything left is blocked. Name the one thing in front of it, resolved the same way the
    // roadmap card face does, so the two surfaces never disagree about the blocker.
    //
    // The nil fall-through is defensive only: `.blocked` means either a shut phase (so
    // `founderStep` is non-nil by definition — the phase is unsettled) or an unmet dependency
    // (so a not-done dependency exists). Neither can hand back nil today, which is why there is
    // no copy for it — no line beats an invented sentence.
    if let first = statuses.first(where: { $0.status == .blocked })?.task,
       let blocker = RoadmapGating.blocker(for: first, in: all) {
        return lang == .vi ? "Mọi việc ở đây đang chờ: \(blocker.title)."
                           : "Everything here is waiting on \(blocker.title)."
    }
    return nil
}

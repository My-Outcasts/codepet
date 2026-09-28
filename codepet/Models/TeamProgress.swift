// codepet/Models/TeamProgress.swift
import Foundation

/// What a running Team Build card shows instead of every step's full row (CP-033): one segment
/// per step in plan order, the step(s) running now, and the next one waiting.
///
/// Before this the card kept all seven rows, each with a department, a title, a status pill and a
/// "waits for" line, plus the plan's summary — while only one or two steps were moving. The rows
/// are still one click away ("See all N steps"); the default view answers "who is working and
/// what comes next".
struct TeamProgress: Equatable {
    let segments: [TeamStepStatus]
    let current: [WorkStep]
    let next: WorkStep?
    let doneCount: Int
    var total: Int { segments.count }

    init(_ run: TeamRun) {
        let status = { (step: WorkStep) in run.state(step.id)?.status ?? .waiting }
        segments = run.plan.steps.map(status)
        current = run.plan.steps.filter { status($0) == .running }
        next = run.plan.steps.first { status($0) == .waiting }
        doneCount = segments.filter { $0 == .done }.count
    }

    /// The plan the founder approves lists every step, and a failed or stopped run shows which
    /// step broke and its button; only a run in motion or finished compacts.
    static func compacts(_ phase: TeamRunPhase) -> Bool {
        [.running, .assembling, .ready, .filed].contains(phase)
    }
}

extension TeamBuildCopy {
    /// "Support: Write the FAQ answers", or "2 departments working: Support, Legal" when several
    /// run at once. Nil when nothing is running.
    static func liveLine(_ p: TeamProgress, lang: AppLanguage) -> String? {
        switch p.current.count {
        case 0:
            return nil
        case 1:
            let s = p.current[0]
            return "\(deptName(s.dept)): \(s.title)"
        default:
            var seen = Set<String>()
            let names = p.current.map { deptName($0.dept) }.filter { seen.insert($0).inserted }
                .joined(separator: ", ")
            return lang == .vi ? "\(p.current.count) phòng ban đang làm: \(names)"
                               : "\(p.current.count) departments working: \(names)"
        }
    }

    static func nextLine(_ p: TeamProgress, lang: AppLanguage) -> String? {
        guard let n = p.next else { return nil }
        return (lang == .vi ? "Tiếp theo: " : "Next: ") + "\(deptName(n.dept)), \(n.title)"
    }

    static func allSteps(_ count: Int, expanded: Bool, lang: AppLanguage) -> String {
        if expanded { return lang == .vi ? "Ẩn các bước" : "Hide steps" }
        return lang == .vi ? "Xem cả \(count) bước" : "See all \(count) steps"
    }
}

extension TeamBuildCopy {
    /// What a stopped run did, in one sentence (CP-034). The card used to show every row marked
    /// Cancelled — what did NOT happen — and nothing to do next.
    static func stoppedSummary(_ run: TeamRun, lang: AppLanguage) -> String {
        let vi = lang == .vi
        let done = run.plan.steps.filter { run.state($0.id)?.status == .done }
        let started = run.steps.contains { $0.startedAt != nil }
        guard !done.isEmpty else {
            if !started { return vi ? "Đã huỷ trước khi bắt đầu. Chưa có gì chạy." : "Cancelled before it started. Nothing ran." }
            return vi ? "Đã dừng trước khi bước nào xong. Chưa có gì được làm."
                      : "Stopped before any step finished. Nothing was built."
        }
        var seen = Set<String>()
        let names = done.map { deptName($0.dept) }.filter { seen.insert($0).inserted }
        let who = names.count == 1 ? names[0]
            : names.dropLast().joined(separator: ", ") + (vi ? " và " : " and ") + names.last!
        return vi ? "Đã dừng sau \(done.count)/\(run.plan.steps.count) bước. Phần việc của \(who) vẫn được giữ ở đây."
                  : "Stopped after \(done.count) of \(run.plan.steps.count) steps. \(who)'s work is kept here."
    }
}

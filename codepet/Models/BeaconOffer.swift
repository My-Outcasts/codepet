// codepet/Models/BeaconOffer.swift
import Foundation

/// What the hero's one card offers, resolved from the beacon task.
///
/// The prototype's hero is orb + greeting + composer + **one** card, and that card
/// is not a link — it names the work, says who does it and what it costs the
/// founder, and carries the buttons. Three generic starters ("Draft my
/// positioning") were the placeholder for this; they promise nothing the roadmap
/// actually holds, which is why the prototype's own comment says the hero has no
/// starter chips.
///
/// Pure and language-parameterised so the copy is asserted in tests rather than
/// read off a screenshot.
struct BeaconOffer: Equatable {
    /// The `DO THIS NEXT` eyebrow.
    let eyebrow: String
    let title: String
    /// One line: who can do it, and where the founder's gate is.
    let detail: String
    let primary: Primary
    /// `Something else` — only when there is another candidate to move to. The
    /// prototype's second beacon is reached by this button, so a board with one
    /// actionable task must not show a control that would do nothing.
    let canSkip: Bool

    /// The primary button. Each is a different promise, so each has its own verb:
    /// running spends, walking through does not, reviewing opens what already exists.
    enum Primary: Equatable {
        /// A department drafts it now.
        case run(String)
        /// Only the founder can do it; Codepet prepares and records.
        case walkthrough(String)
        /// A draft already exists and is waiting on approval.
        case review(String)

        var label: String {
            switch self {
            case .run(let l), .walkthrough(let l), .review(let l): return l
            }
        }
    }

    /// Everything the beacon may offer, in roadmap order — `Something else` walks
    /// this list. The filter is `RoadmapEngine.nextStep`'s, so `candidates.first`
    /// IS the beacon and the two can never disagree about what comes first.
    static func candidates(_ tasks: [RoadmapTask]) -> [RoadmapTask] {
        // Written as a loop, not a filter/sort chain: `status` is O(n) in `tasks`,
        // and calling it twice per element inside a predicate is both quadratic and
        // slow enough to type-check that the compiler gives up on it.
        var kept: [(offset: Int, task: RoadmapTask)] = []
        for (offset, task) in tasks.enumerated() {
            let status = RoadmapEngine.status(for: task, in: tasks)
            guard status != .done, status != .blocked else { continue }
            kept.append((offset, task))
        }
        kept.sort { a, b in
            a.task.phase.order != b.task.phase.order
                ? a.task.phase.order < b.task.phase.order
                : a.offset < b.offset
        }
        return kept.map(\.task)
    }

    /// `nil` when there is nothing actionable — the hero then shows greeting and
    /// composer alone rather than inventing an offer.
    static func offer(for task: RoadmapTask?, in tasks: [RoadmapTask],
                      host: String, language: AppLanguage) -> BeaconOffer? {
        guard let task else { return nil }
        let vi = language == .vi
        let eyebrow = vi ? "Làm việc này tiếp" : "Do this next"
        let canSkip = candidates(tasks).count > 1

        // `drafted` is checked before `who`: a task the founder must do themselves can
        // still have a prepared draft waiting, and the waiting draft is the newer fact.
        if task.drafted {
            return BeaconOffer(
                eyebrow: eyebrow, title: task.title,
                detail: vi ? "Một bản nháp đang chờ bạn — duyệt trước khi nó được lưu vào Thư viện."
                           : "A draft is waiting on you — approve it before it is filed in Library.",
                primary: .review(vi ? "Xem lại" : "Review it"), canSkip: canSkip)
        }
        if task.who == .you {
            return BeaconOffer(
                eyebrow: eyebrow, title: task.title,
                detail: vi ? "Việc này cần bạn — \(host) chỉ có thể chuẩn bị và ghi lại những gì bạn học được."
                           : "This one needs you — \(host) can only prepare it and record what you learn.",
                primary: .walkthrough(vi ? "Hướng dẫn tôi" : "Walk me through it"), canSkip: canSkip)
        }
        let dept = DepartmentCatalog.find(task.dept)?.name
        return BeaconOffer(
            eyebrow: eyebrow, title: task.title,
            detail: dept.map {
                vi ? "\($0) có thể soạn ngay — bạn duyệt trước khi nó được lưu."
                   : "\($0) can draft this now — you approve before it is filed."
            } ?? (vi ? "\(host) có thể soạn ngay — bạn duyệt trước khi nó được lưu."
                     : "\(host) can draft this now — you approve before it is filed."),
            primary: .run(vi ? "Chạy đi" : "Run it"), canSkip: canSkip)
    }
}

// codepet/Models/RoadmapEngine.swift
import Foundation

/// Pure derivations over a company's roadmap tasks — status, the next-step
/// beacon, progress, and phase grouping. No network, no mutation.
enum RoadmapEngine {
    private static func byId(_ tasks: [RoadmapTask]) -> [String: RoadmapTask] {
        Dictionary(tasks.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
    }

    /// A task's dependencies are all satisfied. A dangling dep id (one not present in the
    /// task set) is INTENTIONALLY treated as satisfied — fail-open: a task shows ready
    /// rather than dead-ending the board on a stale/removed dependency.
    private static func depsSatisfied(_ task: RoadmapTask, _ index: [String: RoadmapTask]) -> Bool {
        !task.dependsOn.contains { index[$0]?.done == false }
    }

    /// Legend status. Precedence: done → needsApproval → blocked → needsYou → codepetCanDo.
    ///
    /// TWO things block: the rolling phase window (`RoadmapGating`) and unmet dependencies. The
    /// window is checked first because it's the coarser truth — a task in a closed phase isn't
    /// workable no matter how its own deps look. `needsApproval` stays ahead of both: a draft
    /// that already exists must stay reviewable even in a closed phase.
    static func status(for task: RoadmapTask, in tasks: [RoadmapTask]) -> TaskStatus {
        if task.done { return .done }
        if task.drafted { return .needsApproval }
        if !RoadmapGating.openPhases(tasks).contains(task.phase) { return .blocked }
        if !depsSatisfied(task, byId(tasks)) { return .blocked }
        return task.who == .you ? .needsYou : .codepetCanDo
    }

    /// Resolve the deliverable a done task produced — the library item whose
    /// `sourceTaskId` matches the task's id. `nil` when none is found: legacy tasks
    /// predate `sourceTaskId`, or the task's deliverable was never generated. Pure —
    /// no network, no mutation; callers no-op the tap when this returns nil.
    static func deliverable(for task: RoadmapTask, in library: [Deliverable]) -> Deliverable? {
        library.first { $0.sourceTaskId == task.id }
    }

    /// The beacon: the first not-done, dependency-satisfied task INSIDE the open phase window,
    /// by phase order then position. The window clause matters when the open phase has no
    /// actionable task of its own — without it the beacon would skip into a locked phase and
    /// point at a card the board draws as locked.
    static func nextStep(_ tasks: [RoadmapTask]) -> RoadmapTask? {
        let index = byId(tasks)
        let open = RoadmapGating.openPhases(tasks)
        return tasks.enumerated()
            .filter { !$0.element.done && open.contains($0.element.phase)
                      && depsSatisfied($0.element, index) }
            .min(by: { a, b in
                a.element.phase.order != b.element.phase.order
                    ? a.element.phase.order < b.element.phase.order
                    : a.offset < b.offset
            })?.element
    }

    /// Up to `limit` parallelizable "next moves" for the chat fan-out: the first
    /// `codepetCanDo` task in each DISTINCT department that maps to a specialist
    /// companion, in roadmap order (phase order, then array position). Pure.
    static func nextMoves(_ tasks: [RoadmapTask], limit: Int) -> [RoadmapTask] {
        guard limit > 0 else { return [] }
        let ordered = tasks.enumerated().sorted { a, b in
            a.element.phase.order != b.element.phase.order
                ? a.element.phase.order < b.element.phase.order
                : a.offset < b.offset
        }.map { $0.element }
        var seenDepts = Set<String>()
        var out: [RoadmapTask] = []
        for task in ordered {
            guard let dept = task.dept,
                  DepartmentCompanions.companionId(for: dept) != nil,
                  !seenDepts.contains(dept),
                  status(for: task, in: tasks) == .codepetCanDo else { continue }
            seenDepts.insert(dept)
            out.append(task)
            if out.count == limit { break }
        }
        return out
    }

    /// Up to `limit` suggestions for the founder's next moves: the beacon first, then one
    /// actionable task per DISTINCT department, in roadmap order, all inside the open window.
    ///
    /// Deliberately NOT `nextMoves`. That one is the chat fan-out: it keeps only `codepetCanDo`
    /// tasks whose department maps to a specialist companion, which excludes every `needsYou`
    /// task — including the beacon on most real boards. Suggesting the founder's own next step
    /// is the whole point here, so this one admits `needsYou` and `needsApproval` too.
    ///
    /// `nextStep`'s result is forced into first place so the beacon card and this list can never
    /// disagree about what comes next. Legacy dept-less tasks each occupy their own slot rather
    /// than collapsing into one.
    static func suggestedNext(_ tasks: [RoadmapTask], limit: Int) -> [RoadmapTask] {
        guard limit > 0 else { return [] }
        let actionable: Set<TaskStatus> = [.codepetCanDo, .needsYou, .needsApproval]
        let ordered = tasks.enumerated().sorted { a, b in
            a.element.phase.order != b.element.phase.order
                ? a.element.phase.order < b.element.phase.order
                : a.offset < b.offset
        }.map { $0.element }

        var out: [RoadmapTask] = []
        var seenDepts = Set<String>()
        func slot(_ task: RoadmapTask) -> String { task.dept ?? "__none__\(task.id)" }

        if let beacon = nextStep(tasks) {
            out.append(beacon)
            seenDepts.insert(slot(beacon))
        }
        for task in ordered where out.count < limit {
            guard !out.contains(where: { $0.id == task.id }),
                  actionable.contains(status(for: task, in: tasks)),
                  !seenDepts.contains(slot(task)) else { continue }
            seenDepts.insert(slot(task))
            out.append(task)
        }
        return Array(out.prefix(limit))
    }

    static func progressPercent(_ tasks: [RoadmapTask]) -> Int {
        guard !tasks.isEmpty else { return 0 }
        let done = tasks.filter { $0.done }.count
        return Int((Double(done) / Double(tasks.count) * 100).rounded())
    }

    static func tasksByPhase(_ tasks: [RoadmapTask]) -> [RoadmapPhase: [RoadmapTask]] {
        Dictionary(grouping: tasks, by: { $0.phase })
    }

    /// All five phases in `RoadmapPhase.allCases` order, each paired with its tasks
    /// (empty array when none) — guarantees the board's column set + order regardless
    /// of which phases currently have tasks.
    static func orderedColumns(_ tasks: [RoadmapTask]) -> [(phase: RoadmapPhase, tasks: [RoadmapTask])] {
        let grouped = tasksByPhase(tasks)
        return RoadmapPhase.allCases.map { (phase: $0, tasks: grouped[$0] ?? []) }
    }
}

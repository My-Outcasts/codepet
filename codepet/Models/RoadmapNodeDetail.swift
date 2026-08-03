// codepet/Models/RoadmapNodeDetail.swift
import Foundation

/// One thing standing in front of a node: an unmet (or met) dependency, or the rolling phase
/// window itself. Met requirements are kept deliberately — the panel shows progress, not just
/// obstacles.
struct NodeRequirement: Identifiable, Equatable {
    enum Kind: Equatable {
        case task(String)                 // the dependency's task id
        case phaseWindow(RoadmapPhase)    // the earliest unsettled phase
    }
    let kind: Kind
    let label: String
    /// The requirement's own live state — a dependency's status label, or the step holding the
    /// window shut. nil when there is nothing more to say.
    let statusNote: String?
    let satisfied: Bool

    var id: String {
        switch kind {
        case .task(let id):      return "task:\(id)"
        case .phaseWindow(let p): return "phase:\(p.rawValue)"
        }
    }
}

/// Everything the node panel shows about one roadmap task, derived entirely from the task set —
/// no authored per-node fields, no network, no view types. Adapted from Cofounder's tech-tree
/// node view: what becomes true, how to move it, what counts as done, what's required first,
/// what it unlocks.
struct RoadmapNodeDetail: Equatable {
    let phaseLabel: String
    /// nil for legacy tasks saved before `dept` existed.
    let deptName: String?
    let title: String
    let status: TaskStatus
    let becomesTrue: String
    let howToMoveForward: String
    let toComplete: String
    let requiredFirst: [NodeRequirement]
    let unlocks: [String]

    /// Enough to show the shape of what this unblocks without turning the panel into a list.
    static let maxUnlocks = 4

    static func build(for task: RoadmapTask, in tasks: [RoadmapTask],
                      lang: AppLanguage) -> RoadmapNodeDetail {
        let status = RoadmapEngine.status(for: task, in: tasks)

        // Dependencies in their declared order. A dangling id is skipped rather than shown as a
        // phantom requirement — `RoadmapEngine.depsSatisfied` treats it as satisfied (fail-open),
        // so listing it would contradict the status.
        var requirements: [NodeRequirement] = task.dependsOn.compactMap { depId in
            guard let dep = tasks.first(where: { $0.id == depId }) else { return nil }
            return NodeRequirement(
                kind: .task(dep.id),
                label: dep.title,
                statusNote: RoadmapEngine.status(for: dep, in: tasks).label(lang),
                satisfied: dep.done)
        }

        // The window itself, when THAT is what's holding this node shut. The phase named is the
        // earliest unsettled one — not the task's own phase, which is merely downstream of it.
        if !RoadmapGating.openPhases(tasks).contains(task.phase),
           let blocking = RoadmapPhase.allCases.first(where: { !RoadmapGating.settled($0, in: tasks) }) {
            let step = RoadmapGating.founderStep(in: tasks)
            requirements.append(NodeRequirement(
                kind: .phaseWindow(blocking),
                label: RoadmapBoardCopy.phaseMustSettle(blocking, lang),
                statusNote: step.map { RoadmapBoardCopy.waitingOn($0.title, lang: lang) },
                satisfied: false))
        }

        let detail = task.detail.trimmingCharacters(in: .whitespacesAndNewlines)
        return RoadmapNodeDetail(
            phaseLabel: task.phase.label(lang).uppercased(),
            deptName: DepartmentCatalog.find(task.dept)?.name,
            title: task.title,
            status: status,
            becomesTrue: RoadmapBoardCopy.becomesTrue(task.phase, lang),
            howToMoveForward: detail.isEmpty
                ? RoadmapBoardCopy.howToFallback(for: status, lang)
                : detail,
            toComplete: RoadmapBoardCopy.toComplete(for: task.who, lang),
            requiredFirst: requirements,
            unlocks: tasks.filter { $0.dependsOn.contains(task.id) }
                .prefix(maxUnlocks).map(\.title))
    }
}

// codepet/Models/RoadmapEngine.swift
import Foundation

/// Pure derivations over a company's roadmap tasks — status, the next-step
/// beacon, progress, and phase grouping. No network, no mutation.
enum RoadmapEngine {
    private static func byId(_ tasks: [RoadmapTask]) -> [String: RoadmapTask] {
        Dictionary(tasks.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
    }

    /// A task's dependencies are all satisfied (a missing dep id is treated as satisfied).
    private static func depsSatisfied(_ task: RoadmapTask, _ index: [String: RoadmapTask]) -> Bool {
        !task.dependsOn.contains { index[$0]?.done == false }
    }

    /// Legend status. Precedence: done → needsApproval → blocked → needsYou → codepetCanDo.
    static func status(for task: RoadmapTask, in tasks: [RoadmapTask]) -> TaskStatus {
        if task.done { return .done }
        if task.drafted { return .needsApproval }
        if !depsSatisfied(task, byId(tasks)) { return .blocked }
        return task.who == .you ? .needsYou : .codepetCanDo
    }

    /// The beacon: the first not-done, dependency-satisfied task by phase order then position.
    static func nextStep(_ tasks: [RoadmapTask]) -> RoadmapTask? {
        let index = byId(tasks)
        return tasks.enumerated()
            .filter { !$0.element.done && depsSatisfied($0.element, index) }
            .min(by: { a, b in
                a.element.phase.order != b.element.phase.order
                    ? a.element.phase.order < b.element.phase.order
                    : a.offset < b.offset
            })?.element
    }

    static func progressPercent(_ tasks: [RoadmapTask]) -> Int {
        guard !tasks.isEmpty else { return 0 }
        let done = tasks.filter { $0.done }.count
        return Int((Double(done) / Double(tasks.count) * 100).rounded())
    }

    static func tasksByPhase(_ tasks: [RoadmapTask]) -> [RoadmapPhase: [RoadmapTask]] {
        Dictionary(grouping: tasks, by: { $0.phase })
    }
}

// codepet/Models/RoadmapEngine.swift
import Foundation

/// Pure "what to do next" picker over a project's roadmap tasks. No network, no
/// LLM — mirrors the web's pure next-step engine. The single pick is the first
/// not-done task ordered by department (`HealthPillar.order`) then array position.
enum RoadmapEngine {
    static func nextStep(_ tasks: [RoadmapTask], stage: ProjectStage) -> RoadmapNextStep? {
        let indexed = tasks.enumerated().filter { !$0.element.done }
        guard let pick = indexed.min(by: { a, b in
            if a.element.deptKey.order != b.element.deptKey.order {
                return a.element.deptKey.order < b.element.deptKey.order
            }
            return a.offset < b.offset
        })?.element else { return nil }
        let why = "Next up in \(pick.deptKey.label.en) for the \(stage.label.en.lowercased()) stage."
        return RoadmapNextStep(deptKey: pick.deptKey, taskTitle: pick.title, why: why)
    }
}

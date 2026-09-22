// codepet/Models/RoadmapShapeLine.swift
import Foundation

/// "I've lined up 14 tasks across 4 phases." — the board in one sentence.
///
/// The greeting went straight from "your company is ready" to a single next move, which
/// undersold a board of a dozen tasks. Pure, and separate from `BriefRead` so a reviewer can
/// reject one without the other.
///
/// Outside any `@MainActor ObservableObject` — landmine 3.
enum RoadmapShapeLine {

    static func compose(tasks: [RoadmapTask], language: AppLanguage) -> String? {
        guard !tasks.isEmpty else { return nil }
        let taskCount = tasks.count
        // DISTINCT phases. Counting `tasks.count` twice is the obvious wrong answer, and a
        // board where every task sits in one phase is the case that catches it.
        let phaseCount = Set(tasks.map(\.phase)).count

        if language == .vi {
            // Vietnamese does not inflect for number, so one form covers both.
            return "Mình đã chuẩn bị \(taskCount) việc trong \(phaseCount) giai đoạn."
        }
        let t = taskCount == 1 ? "1 task" : "\(taskCount) tasks"
        let p = phaseCount == 1 ? "1 phase" : "\(phaseCount) phases"
        return "I've lined up \(t) across \(p)."
    }
}

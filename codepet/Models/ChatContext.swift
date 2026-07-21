// codepet/Models/ChatContext.swift
import Foundation

/// Pure grounding-string builder for the Copilot chat — the company brief plus a
/// short roadmap summary, sent to the companyChat CF as `context`. Always returns
/// a non-empty string.
enum ChatContext {
    static func compose(brief: CompanyBrief, tasks: [RoadmapTask]) -> String {
        var parts: [String] = []
        parts.append(BriefContext.compose(brief) ?? "No brief yet.")
        parts.append("Roadmap progress: \(RoadmapEngine.progressPercent(tasks))%.")
        if let next = RoadmapEngine.nextStep(tasks) {
            parts.append("Next step: \(next.title).")
        }
        let openTitles = tasks.filter { !$0.done }.prefix(6).map { $0.title }
        if !openTitles.isEmpty {
            parts.append("Open tasks: " + openTitles.joined(separator: "; ") + ".")
        }
        return parts.joined(separator: "\n")
    }
}

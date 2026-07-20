// codepet/Models/RoadmapTask.swift
import Foundation

/// Who acts on a roadmap task — mirrors the web `Who`: the companion drafts it,
/// the companion does it, or the founder must.
enum TaskWho: String, Codable, Hashable {
    case draft    // companion drafts a deliverable for the founder to review
    case does     // companion can do it outright
    case needsYou // only the founder can do it
}

/// One AI-generated, stage-appropriate build task under a department. Rides on
/// `Project` (persisted with the projects dict), alongside the fixed health rubric.
struct RoadmapTask: Codable, Hashable, Identifiable {
    let id: String            // stable, e.g. "engineering-0"
    let deptKey: HealthPillar
    var title: String
    var detail: String
    var who: TaskWho
    var kind: String
    var done: Bool

    init(id: String, deptKey: HealthPillar, title: String, detail: String,
         who: TaskWho = .draft, kind: String = "build", done: Bool = false) {
        self.id = id; self.deptKey = deptKey; self.title = title; self.detail = detail
        self.who = who; self.kind = kind; self.done = done
    }
}

/// The single "do this next" pick across a project's open roadmap tasks.
/// Mirrors the web `NextStep { deptK, taskTitle, why }`.
struct RoadmapNextStep: Hashable {
    let deptKey: HealthPillar
    let taskTitle: String
    let why: String
}

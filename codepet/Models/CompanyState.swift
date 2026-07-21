// codepet/Models/CompanyState.swift
import Foundation

/// A company department (roadmap). Minimal this phase — tasks/details land in
/// the roadmap phase. Mirrors the web Dept skeleton (key + name).
struct Department: Codable, Hashable, Identifiable {
    let key: String
    var name: String
    var id: String { key }
}

/// The single company's in-memory state (companies/{uid}). `tasks` is the
/// roadmap and `library` is the delivered work — both loaded from the doc.
/// Departments is typed but empty until a later phase populates it.
struct CompanyState: Codable, Hashable {
    var brief: CompanyBrief
    var departments: [Department]
    var library: [Deliverable]
    var stage: ProjectStage
    var companionId: String
    var onboardedAt: Date?
    var tasks: [RoadmapTask]

    /// Explicit memberwise init so `tasks` (non-optional) can default to `[]` — existing
    /// call sites that predate the roadmap phase omit it and keep compiling.
    init(brief: CompanyBrief, departments: [Department], library: [Deliverable],
         stage: ProjectStage, companionId: String, onboardedAt: Date? = nil,
         tasks: [RoadmapTask] = []) {
        self.brief = brief
        self.departments = departments
        self.library = library
        self.stage = stage
        self.companionId = companionId
        self.onboardedAt = onboardedAt
        self.tasks = tasks
    }

    static let empty = CompanyState(
        brief: CompanyBrief(), departments: [], library: [], stage: .idea, companionId: "byte", onboardedAt: nil)
}

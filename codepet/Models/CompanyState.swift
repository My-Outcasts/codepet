// codepet/Models/CompanyState.swift
import Foundation

/// A company department (roadmap). Minimal this phase — tasks/details land in
/// the roadmap phase. Mirrors the web Dept skeleton (key + name).
struct Department: Codable, Hashable, Identifiable {
    let key: String
    var name: String
    var id: String { key }
}

/// An approved deliverable in the library. Minimal this phase.
struct LibItem: Codable, Hashable, Identifiable {
    let id: String
    var title: String
    var kind: String
}

/// The single company's in-memory state (companies/{uid}). Departments and
/// library are typed but empty until later phases populate them.
struct CompanyState: Codable, Hashable {
    var brief: CompanyBrief
    var departments: [Department]
    var library: [LibItem]
    var stage: ProjectStage
    var companionId: String
    var onboardedAt: Date?

    static let empty = CompanyState(
        brief: CompanyBrief(), departments: [], library: [], stage: .idea, companionId: "byte", onboardedAt: nil)
}

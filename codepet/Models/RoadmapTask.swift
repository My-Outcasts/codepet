// codepet/Models/RoadmapTask.swift
import Foundation

/// The roadmap board's columns, in order. Mirrors the web Overview board
/// (Find → Foundation → Build → Ship → Launch).
enum RoadmapPhase: String, Codable, CaseIterable, Identifiable {
    case find, foundation, build, ship, launch
    var id: String { rawValue }
    var order: Int { Self.allCases.firstIndex(of: self) ?? 0 }
    func label(_ lang: AppLanguage) -> String {
        switch self {
        case .find:       return lang == .vi ? "Tìm hiểu" : "Find"
        case .foundation: return lang == .vi ? "Nền tảng" : "Foundation"
        case .build:      return lang == .vi ? "Xây dựng" : "Build"
        case .ship:       return lang == .vi ? "Phát hành" : "Ship"
        case .launch:     return lang == .vi ? "Ra mắt" : "Launch"
        }
    }
}

/// Who acts on a task — mirrors the web `Who`: companion does it / drafts it /
/// the founder must.
enum TaskWho: String, Codable, Hashable { case does, draft, you }

/// One roadmap task under a phase. Fields are JSON-safe so it persists via the
/// companies/{uid} JSONSerialization path.
struct RoadmapTask: Codable, Hashable, Identifiable {
    let id: String
    var title: String
    var detail: String
    var phase: RoadmapPhase
    var who: TaskWho
    var dependsOn: [String]
    var done: Bool
    var drafted: Bool

    init(id: String, title: String, detail: String, phase: RoadmapPhase, who: TaskWho,
         dependsOn: [String] = [], done: Bool = false, drafted: Bool = false) {
        self.id = id; self.title = title; self.detail = detail; self.phase = phase
        self.who = who; self.dependsOn = dependsOn; self.done = done; self.drafted = drafted
    }
}

/// Derived per-task status (the board legend) — computed by RoadmapEngine, not stored.
enum TaskStatus { case done, needsApproval, blocked, needsYou, codepetCanDo }

// codepet/Models/RoadmapTask.swift
import SwiftUI

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
    /// Owning department key (one of the 8 DEPARTMENTS keys). OPTIONAL: existing saved
    /// tasks predate this field, and RoadmapTask decodes strictly — a required `dept`
    /// would fail to decode every stored board. nil == unassigned (pre-department tasks).
    var dept: String?

    init(id: String, title: String, detail: String, phase: RoadmapPhase, who: TaskWho,
         dependsOn: [String] = [], done: Bool = false, drafted: Bool = false, dept: String? = nil) {
        self.id = id; self.title = title; self.detail = detail; self.phase = phase
        self.who = who; self.dependsOn = dependsOn; self.done = done; self.drafted = drafted
        self.dept = dept
    }
}

/// Derived per-task status (the board legend) — computed by RoadmapEngine, not stored.
enum TaskStatus { case done, needsApproval, blocked, needsYou, codepetCanDo }

/// Shared status→accent mapping (matches TaskCardView's board colors). Used by the
/// department task cards; kept here so views don't each redefine it.
func taskStatusTint(_ s: TaskStatus) -> Color {
    switch s {
    case .done:          return CodepetTheme.accentTeal
    case .codepetCanDo:  return CodepetTheme.accentPurple
    case .needsApproval: return CodepetTheme.accentGold
    case .needsYou:      return CodepetTheme.accentOrange
    case .blocked:       return CodepetTheme.mutedText
    }
}

extension TaskWho {
    /// Board chip label — who acts on the task.
    func label(_ lang: AppLanguage) -> String {
        switch self {
        case .does:  return lang == .vi ? "Codepet làm" : "Codepet does"
        case .draft: return lang == .vi ? "Codepet soạn" : "Codepet drafts"
        case .you:   return lang == .vi ? "Bạn" : "You"
        }
    }
}

extension TaskStatus {
    /// Board legend label for the derived status.
    func label(_ lang: AppLanguage) -> String {
        switch self {
        case .done:          return lang == .vi ? "Xong" : "Done"
        case .codepetCanDo:  return lang == .vi ? "Codepet làm được" : "Codepet can do"
        case .needsApproval: return lang == .vi ? "Cần duyệt" : "Needs approval"
        case .needsYou:      return lang == .vi ? "Cần bạn" : "Needs you"
        case .blocked:       return lang == .vi ? "Cần bước trước" : "Needs earlier steps"
        }
    }
}

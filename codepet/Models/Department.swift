// codepet/Models/Department.swift
import SwiftUI

/// One of the 8 fixed departments (mirrors the web DEPTS catalog). Static identity +
/// hand-written rationale/focus; live status/tasks are DERIVED from the dept-tagged
/// roadmap tasks, never stored here.
struct Department: Identifiable, Hashable {
    let key: String
    let name: String
    let ab: String          // 2-letter badge
    let accent: Color
    let rationale: String    // web `d.need` — what this department must accomplish
    let focus: String        // web `d.byte` — a short companion-style focus line
    var id: String { key }
    var coverAsset: String { "dept-\(key)" }
}

enum DepartmentStatus {
    case attention, ready, idle, later
    func label(_ lang: AppLanguage) -> String {
        switch self {
        case .attention: return lang == .vi ? "cần bạn" : "needs you"
        case .ready:     return lang == .vi ? "sẵn sàng" : "ready"
        case .idle:      return lang == .vi ? "nhàn rỗi" : "idle"
        case .later:     return lang == .vi ? "sau này" : "later"
        }
    }
    var tint: Color {
        switch self {
        case .attention: return CodepetTheme.accentBlue
        case .ready:     return CodepetTheme.accentTeal
        case .idle:      return CodepetTheme.mutedText
        case .later:     return CodepetTheme.mutedText
        }
    }
}

struct DepartmentSummary: Identifiable {
    let department: Department
    let status: DepartmentStatus
    let pending: Int
    let currentTaskTitle: String?
    var id: String { department.key }
}

enum DepartmentCatalog {
    static let all: [Department] = [
        Department(key: "eng", name: "Engineering", ab: "En", accent: CodepetTheme.accentBlue,
            rationale: "Build and ship the product itself — the features, the technical foundation, the things users touch.",
            focus: "This is where the thing you're building actually gets made."),
        Department(key: "design", name: "Design", ab: "De", accent: CodepetTheme.accentPurple,
            rationale: "Shape how the product looks and feels so the first run lands and people get it fast.",
            focus: "Make it clear, make it yours, make it easy to fall into."),
        Department(key: "mkt", name: "Marketing", ab: "Mk", accent: CodepetTheme.accentOrange,
            rationale: "Get the product in front of the right people and tell its story clearly.",
            focus: "The best product still needs someone to hear about it."),
        Department(key: "sales", name: "Sales", ab: "Sa", accent: CodepetTheme.accentPurple,
            rationale: "Turn interest into real users and first customers, one conversation at a time.",
            focus: "Early on, you land users personally — not by broadcasting."),
        Department(key: "support", name: "Support", ab: "Su", accent: CodepetTheme.accentPink,
            rationale: "Help your users succeed and turn their friction into what you build next.",
            focus: "Every question is a signal about what to fix."),
        Department(key: "fin", name: "Finance", ab: "Fi", accent: CodepetTheme.accentGold,
            rationale: "Keep the money side sound — pricing, runway, and the basics that keep you shipping.",
            focus: "Know your numbers before they force your hand."),
        Department(key: "ops", name: "Operations", ab: "Op", accent: CodepetTheme.accentTeal,
            rationale: "Stand up the machinery that lets the whole company run without you touching every step.",
            focus: "The boring plumbing that makes everything else possible."),
        Department(key: "legal", name: "Legal", ab: "Lg", accent: CodepetTheme.accentPurple,
            rationale: "Cover the legal and compliance minimum so shipping never becomes a liability.",
            focus: "Not glamorous, but it protects everything you're building."),
    ]

    static func find(_ key: String?) -> Department? {
        guard let key else { return nil }
        return all.first { $0.key == key }
    }

    /// Derive a summary per department (catalog order) from the dept-tagged tasks.
    static func summaries(tasks: [RoadmapTask]) -> [DepartmentSummary] {
        all.map { dep in
            let mine = tasks.filter { $0.dept == dep.key }
            if mine.isEmpty {
                return DepartmentSummary(department: dep, status: .later, pending: 0, currentTaskTitle: nil)
            }
            let open = mine.filter { !$0.done }
            let statuses = open.map { RoadmapEngine.status(for: $0, in: tasks) }
            let status: DepartmentStatus =
                statuses.contains(.needsYou) ? .attention
                : statuses.contains(.codepetCanDo) ? .ready
                : .idle
            return DepartmentSummary(department: dep, status: status,
                                     pending: open.count, currentTaskTitle: open.first?.title)
        }
    }

    static func needToday(_ summaries: [DepartmentSummary]) -> Int {
        summaries.filter { $0.status == .attention }.count
    }
}

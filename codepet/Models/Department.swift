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
    /// Something is running for this department right now — a Team Build step, a chat run, a
    /// code run. Outranks every roadmap-derived status: Engineering read "LATER" on the Company
    /// page while it was building the founder's project, because it had no roadmap tasks
    /// (build 6 end-to-end test, bug #10).
    case working
    case attention, ready, idle, later
    func label(_ lang: AppLanguage) -> String {
        switch self {
        case .working:   return lang == .vi ? "đang làm" : "working"
        case .attention: return lang == .vi ? "cần bạn" : "needs you"
        case .ready:     return lang == .vi ? "sẵn sàng" : "ready"
        case .idle:      return lang == .vi ? "nhàn rỗi" : "idle"
        case .later:     return lang == .vi ? "sau này" : "later"
        }
    }
    var tint: Color {
        switch self {
        case .working:   return CodepetTheme.accentPurple
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
        // Its own accent, not ops' teal: the two sit four rows apart in the same list.
        Department(key: "product", name: "Product", ab: "Pr", accent: CodepetTheme.accentGreen,
            rationale: "Decide what to build next and what to leave alone — sequencing, scope, and whether anyone actually wants it.",
            focus: "This is where you find out if the thing is worth building before you build it."),
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

    /// The departments the founder is shown as rows/chips — the catalog minus any entry
    /// that exists purely to resolve a wire key.
    ///
    /// `product` is such an entry. The Virtual Company's backend emits
    /// `department_key: "product"` and the contract asks the client to resolve it, so the
    /// catalog needs it; but it has no cover illustration of its own (`dept-product.png`
    /// is a byte-identical copy of `dept-eng.png`), and a roster row wearing
    /// Engineering's art is a worse defect than a missing row — it ships to every
    /// founder, whether or not they ever convene the room. Give Product real art and
    /// delete this filter.
    static let roster: [Department] = all.filter { $0.key != "product" }

    /// Derive a summary per department from the dept-tagged tasks, in catalog order.
    /// `departments` defaults to the whole catalog — chat grounding
    /// (`ChatContext.composeDepartments`) must still see every department a task can be
    /// tagged with; the Company view passes `roster`.
    /// `working` holds the keys of departments with something running now
    /// (`CompanyStore.workingDepartmentKeys`); it outranks what the roadmap says.
    static func summaries(tasks: [RoadmapTask],
                          departments: [Department] = all,
                          working: Set<String> = []) -> [DepartmentSummary] {
        departments.map { dep in
            let mine = tasks.filter { $0.dept == dep.key }
            let isWorking = working.contains(dep.key)
            if mine.isEmpty {
                return DepartmentSummary(department: dep, status: isWorking ? .working : .later,
                                         pending: 0, currentTaskTitle: nil)
            }
            let open = mine.filter { !$0.done }
            let statuses = open.map { RoadmapEngine.status(for: $0, in: tasks) }
            // A draft awaiting approval needs the founder as much as a founder-only task does.
            // It matched no branch here and fell through to IDLE — Marketing read "idle" with a
            // draft sitting unread (5 Oct test).
            let status: DepartmentStatus =
                isWorking ? .working
                : statuses.contains(.needsYou) || statuses.contains(.needsApproval) ? .attention
                : statuses.contains(.codepetCanDo) ? .ready
                : .idle
            return DepartmentSummary(department: dep, status: status,
                                     pending: open.count, currentTaskTitle: open.first?.title)
        }
    }

    /// The departments with something running right now, for `summaries(working:)`.
    ///
    /// - a Team Build step that is running, by its `dept`; the build/assemble phase is
    ///   Engineering's
    /// - a chat run's "producing…" placeholder, by the department name it carries
    /// - a code run (Build / Code mode), which is Engineering's
    static func workingKeys(teamRun: TeamRun?, producingDeptNames: [String],
                            codeRunning: Bool) -> Set<String> {
        var keys = Set<String>()
        if let run = teamRun {
            for step in run.plan.steps where run.state(step.id)?.status == .running {
                keys.insert(step.dept)
            }
            if run.phase == .assembling { keys.insert("eng") }
        }
        for name in producingDeptNames {
            if let d = all.first(where: { $0.name == name }) { keys.insert(d.key) }
        }
        if codeRunning { keys.insert("eng") }
        return keys
    }

    static func needToday(_ summaries: [DepartmentSummary]) -> Int {
        summaries.filter { $0.status == .attention }.count
    }
}

// codepet/Models/CompanyContext.swift
import Foundation

/// The typed, per-slice read-surface for the Capability Bus (Layer 1) — one source
/// of truth read by the companion, the department agents, and the coding agent.
/// The grounding `String` sent to the cloud is now one *projection* of this model
/// (`groundingString`); the `project` slice is CLIENT-ONLY and never appears in it.
///
/// See docs/superpowers/specs/2026-07-29-chat-system-integration-map-design.md
struct CompanyContext {

    /// Read-only, client-only view of the linked project. Populated by the coding
    /// agent (Part 2); nil when nothing is linked. NEVER serialized to the cloud —
    /// the user's code stays on their machine (Part 1 resolved Q3).
    struct ProjectSlice: Equatable {
        let path: String
        let isGitRepo: Bool
        let hasClaudeMd: Bool
        /// Optional short summary of recent local changes (filled by Part 2).
        let recentChangeSummary: String?
    }

    // MARK: Slices
    let brief: CompanyBrief
    let tasks: [RoadmapTask]
    let decisions: [DecisionEntry]
    let library: [Deliverable]
    let departments: [DepartmentSummary]
    let enabledTools: Set<String>
    let project: ProjectSlice?

    // MARK: Turn inputs that shape the cloud projection
    let query: String?
    let focusDepartment: Department?

    init(company: CompanyState,
         query: String? = nil,
         focusDepartment: Department? = nil,
         project: ProjectSlice? = nil) {
        self.brief = company.brief
        self.tasks = company.tasks
        self.decisions = company.decisions
        self.library = company.library
        self.departments = DepartmentCatalog.summaries(tasks: company.tasks)
        self.enabledTools = company.enabledTools
        self.project = project
        self.query = query
        self.focusDepartment = focusDepartment
    }

    /// Grounding string sent to the companyChat CF as `context`. Byte-identical to
    /// the pre-existing chat `ChatContext.compose(...)` call — a pure additive
    /// refactor with no wire change. Deliberately never references `project`.
    var groundingString: String {
        ChatContext.compose(brief: brief, tasks: tasks, decisions: decisions,
                            library: library, query: query, focusDepartment: focusDepartment)
    }

    /// The leaner grounding string the run-task backend uses: brief + roadmap +
    /// decisions, WITHOUT the library/prior-work block that `groundingString`
    /// carries for chat. Byte-identical to the run-task site's previous inline
    /// `ChatContext.compose(brief:tasks:decisions:)` call — a structural migration
    /// with no payload change. Never references `project` (client-only).
    var runTaskGroundingString: String {
        ChatContext.compose(brief: brief, tasks: tasks, decisions: decisions)
    }

    /// Client-only rendering of the linked project for the LOCAL coding agent.
    /// nil when nothing is linked. This string must never be sent to the cloud.
    var projectSummary: String? {
        guard let p = project else { return nil }
        var parts = ["Linked project: \(p.path)",
                     "Git repo: \(p.isGitRepo ? "yes" : "no")",
                     "CLAUDE.md present: \(p.hasClaudeMd ? "yes" : "no")"]
        if let s = p.recentChangeSummary, !s.isEmpty { parts.append("Recent changes: \(s)") }
        return parts.joined(separator: "\n")
    }
}

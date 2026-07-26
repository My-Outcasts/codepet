// codepet/Models/SecondBrainData.swift
import Foundation

/// Pure, view-agnostic aggregation for the Overview "Second Brain" panel — derives the
/// panel's numbers straight from CompanyState. No network, no mutation, NOT @MainActor:
/// mirrors the RoadmapEngine / DepartmentCatalog pure-derivation pattern.
///
/// The web panel's Usage section (sessions/commits/PRs/hours-saved) and its
/// Decisions/Milestones rows are intentionally omitted — native has no LedgerEvent or
/// tracking subsystem to back them, and this struct never fabricates counts.
struct SecondBrainData {

    /// One department's topic tally (native analogue of the web `topicCounts` row).
    struct Topic: Identifiable, Equatable {
        let department: Department
        let count: Int
        var id: String { department.key }
    }

    let deliverables: Int        // company.library.count
    let tasksTotal: Int          // company.tasks.count
    let tasksDone: Int           // done tasks
    let topics: [Topic]          // per-dept task counts, count>0, desc then catalog order
    let nextTask: RoadmapTask?   // RoadmapEngine.nextStep
    let nextDeptName: String?    // department name for nextTask.dept
    let companionName: String    // companionId → PetCharacter name

    /// The active model label, matching the web panel's static MODEL_LABEL. A constant,
    /// not a tracked value.
    static let modelLabel = "claude-opus-4-8"

    init(company: CompanyState) {
        self.deliverables = company.library.count
        self.tasksTotal = company.tasks.count
        self.tasksDone = company.tasks.filter { $0.done }.count

        // Per-department task counts (native analogue of web topicCounts): tally the
        // dept-tagged tasks, drop empties, sort by count desc then catalog order.
        var byKey: [String: Int] = [:]
        for t in company.tasks { if let k = t.dept { byKey[k, default: 0] += 1 } }
        self.topics = DepartmentCatalog.all.enumerated()
            .compactMap { idx, dep -> (Int, Topic)? in
                let n = byKey[dep.key] ?? 0
                return n > 0 ? (idx, Topic(department: dep, count: n)) : nil
            }
            .sorted { $0.1.count != $1.1.count ? $0.1.count > $1.1.count : $0.0 < $1.0 }
            .map(\.1)

        let next = RoadmapEngine.nextStep(company.tasks)
        self.nextTask = next
        self.nextDeptName = DepartmentCatalog.find(next?.dept)?.name
        self.companionName = PetCharacter.all[company.companionId]?.name ?? "Codepet"
    }
}

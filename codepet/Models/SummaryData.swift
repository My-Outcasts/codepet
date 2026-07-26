// codepet/Models/SummaryData.swift
import Foundation

/// One "recent win" row on the Summary digest — a recently shipped (approved)
/// Library deliverable, with a resolved department/kind meta line.
struct SummaryWin: Identifiable, Hashable {
    let id: String     // the deliverable's id
    let title: String
    let meta: String   // owning department name, else the deliverable kind label
}

/// Pure, client-side aggregation of the company's delivered work + roadmap into
/// the numbers/rows the Summary view renders. No network, no mutation, no
/// @MainActor — value-in / value-out so it's trivially unit-testable. Mirrors the
/// web SummaryView's fallback (non-tracking) path.
struct SummaryData {
    let byteHandled: Int      // open tasks Codepet handles (who == .does)
    let needsYou: Int         // open tasks needing the founder (who == .you || .draft)
    let doneCount: Int        // tasks marked done
    let totalCount: Int       // all roadmap tasks
    let departmentCount: Int  // distinct departments with at least one task
    let shippedCount: Int     // approved Library deliverables
    let autopilotPct: Int     // byteHandled / (byteHandled + needsYou); 100 when idle
    let recentWins: [SummaryWin]  // 3 most-recent approved deliverables, newest-first

    /// True when Codepet has nothing open — drives the "All clear" hero copy.
    var isAllClear: Bool { byteHandled == 0 }

    init(company: CompanyState, language: AppLanguage) {
        let tasks = company.tasks
        self.totalCount = tasks.count
        self.doneCount = tasks.filter { $0.done }.count
        self.byteHandled = tasks.filter { !$0.done && $0.who == .does }.count
        self.needsYou = tasks.filter { !$0.done && ($0.who == .you || $0.who == .draft) }.count
        let active = byteHandled + needsYou
        self.autopilotPct = active > 0
            ? Int((Double(byteHandled) / Double(active) * 100).rounded())
            : 100
        self.departmentCount = Set(tasks.compactMap { $0.dept }).count
        self.shippedCount = company.library.count

        // Newest-first (matches LibraryView), take 3. Native Deliverable has no
        // department, so resolve it from the source task; fall back to the kind
        // label when the task/dept can't be resolved.
        self.recentWins = company.library
            .sorted { ($0.createdAt ?? "") > ($1.createdAt ?? "") }
            .prefix(3)
            .map { d in
                let task = d.sourceTaskId.flatMap { id in tasks.first { $0.id == id } }
                let deptName = task?.dept.flatMap { DepartmentCatalog.find($0)?.name }
                return SummaryWin(id: d.id, title: d.title,
                                  meta: deptName ?? d.kind.label(language))
            }
    }
}

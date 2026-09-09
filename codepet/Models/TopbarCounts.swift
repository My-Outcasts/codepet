import Foundation

/// Pure count helpers for the top-bar nav badges (mirrors the web Topbar counts):
/// open you/draft tasks, delivered-library size, and toolkit items still off.
enum TopbarCounts {
    static func tasks(_ tasks: [RoadmapTask]) -> Int {
        tasks.filter { !$0.done && ($0.who == .you || $0.who == .draft) }.count
    }
    static func library(_ library: [Deliverable]) -> Int { library.count }

    /// Toolkit items the founder can actually act on: built AND still off.
    ///
    /// It counted `catalog.count - enabled.count`, which advertised the ten items
    /// that do nothing as pending work — and the environment-honesty pass made that
    /// worse, because dropping `explorer` from `defaultOn` incremented the badge to
    /// 11 while leaving exactly one actionable item. A badge is a claim; this makes
    /// it a true one.
    static func envPending(enabled: Set<String>, builtSkills: Set<String>) -> Int {
        Toolkit.catalog.filter { $0.isBuilt(builtSkills: builtSkills) && !enabled.contains($0.id) }.count
    }
}

import Foundation

/// Pure count helpers for the top-bar nav badges (mirrors the web Topbar counts):
/// open you/draft tasks, delivered-library size, and toolkit items still off.
enum TopbarCounts {
    static func tasks(_ tasks: [RoadmapTask]) -> Int {
        tasks.filter { !$0.done && ($0.who == .you || $0.who == .draft) }.count
    }
    static func library(_ library: [Deliverable]) -> Int { library.count }
    static func envPending(enabled: Set<String>) -> Int { max(0, Toolkit.catalog.count - enabled.count) }
}

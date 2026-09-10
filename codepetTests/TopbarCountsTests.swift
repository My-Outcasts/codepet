import XCTest
@testable import codepet

final class TopbarCountsTests: XCTestCase {
    private func t(_ id: String, who: TaskWho, done: Bool = false) -> RoadmapTask {
        RoadmapTask(id: id, title: id, detail: "", phase: .find, who: who, done: done)
    }
    func testTaskCount_openYouOrDraft() {
        let tasks = [t("a", who: .you), t("b", who: .draft), t("c", who: .does), t("d", who: .you, done: true)]
        XCTAssertEqual(TopbarCounts.tasks(tasks), 2)   // you + draft, not done; .does excluded
    }
    func testEnvPending() {
        // Catalog is 4 skills (web-research, prd-writer built; code-review,
        // changelog not) + 5 connectors (only github has a ConnectorProvider
        // case) + 4 agents (never built). With the bundled floor as the
        // manifest and nothing enabled, built-and-off items are exactly
        // web-research, prd-writer, github — 3.
        let enabled = Set<String>()
        XCTAssertEqual(TopbarCounts.envPending(enabled: enabled, builtSkills: Toolkit.bundledBuiltSkills), 3)
    }

    /// Pins the actual product-visible number: a fresh company (prd-writer +
    /// github enabled by `defaultOn`, bundled floor as the manifest) has
    /// exactly one built-and-off item — web-research. This is the number the
    /// finding says the badge must show, not 11.
    func testEnvPending_freshCompany_isOne() {
        let enabled: Set<String> = ["prd-writer", "github"]
        XCTAssertEqual(TopbarCounts.envPending(enabled: enabled, builtSkills: Toolkit.bundledBuiltSkills), 1)
    }

    /// Agents are NEVER built (`isBuilt` hardcodes `false` for `.agents`), so
    /// even a manifest that claims every catalog id — agent ids included —
    /// must not count any of the 4 agents. With nothing enabled, the only
    /// countable items become the 4 skills + 1 connector (github) that are
    /// actually built: 5. If this fails at 9 (5 + the 4 agents), the agent
    /// carve-out in `isBuilt` has been bypassed.
    func testEnvPending_neverCountsAgents() {
        let everyId = Set(Toolkit.catalog.map(\.id))
        XCTAssertEqual(TopbarCounts.envPending(enabled: [], builtSkills: everyId), 5)
    }
}

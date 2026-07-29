import XCTest
@testable import codepet

final class CompanyContextTests: XCTestCase {

    private func fixtureCompany() -> CompanyState {
        var b = CompanyBrief()
        b.founderName = "Mona"
        b.projectName = "Acme"
        var c = CompanyState.empty
        c.brief = b
        c.tasks = [
            RoadmapTask(id: "t1", title: "Set up repo", detail: "", phase: .find, who: .does, done: true),
            RoadmapTask(id: "t2", title: "Pick a name", detail: "", phase: .foundation, who: .you),
            RoadmapTask(id: "t3", title: "Write landing copy", detail: "", phase: .build, who: .you),
        ]
        c.decisions = [
            DecisionEntry(topic: "Pricing", statement: "Charge $20/mo", source: "founder", updatedAt: 1_700_000_000_000),
        ]
        c.library = [
            Deliverable(kind: .doc, title: "Landing page draft", body: "# Acme\nWelcome."),
        ]
        return c
    }

    func test_groundingString_matchesChatContextCompose() {
        let company = fixtureCompany()
        let ctx = CompanyContext(company: company, query: "landing page copy")
        let expected = ChatContext.compose(
            brief: company.brief, tasks: company.tasks, decisions: company.decisions,
            library: company.library, query: "landing page copy", focusDepartment: nil)
        XCTAssertEqual(ctx.groundingString, expected)

        // Content sanity: parity against compose would still hold if BOTH sides
        // were empty, so pin that the enriched fixture actually renders real
        // slices — roadmap facts and the prior-work (library) block.
        XCTAssertFalse(ctx.groundingString.isEmpty)
        XCTAssertTrue(ctx.groundingString.contains("Roadmap progress"),
                      "roadmap slice should render into the grounding string")
        XCTAssertTrue(ctx.groundingString.contains("Landing page draft"),
                      "library/prior-work slice should render into the grounding string")
    }

    func test_groundingString_matchesCompose_whenNoQuery() {
        let company = fixtureCompany()
        let ctx = CompanyContext(company: company)
        let expected = ChatContext.compose(
            brief: company.brief, tasks: company.tasks, decisions: company.decisions,
            library: company.library, query: nil, focusDepartment: nil)
        XCTAssertEqual(ctx.groundingString, expected)
    }

    func test_runTaskGroundingString_matchesLeanCompose() {
        let company = fixtureCompany()
        let ctx = CompanyContext(company: company)
        // Byte-identical to the run-task site's pre-migration inline call:
        // brief + tasks + decisions only — no library/query/focus.
        let expected = ChatContext.compose(
            brief: company.brief, tasks: company.tasks, decisions: company.decisions)
        XCTAssertEqual(ctx.runTaskGroundingString, expected)
    }

    func test_runTaskGroundingString_excludesLibraryPriorWork() {
        // Even with a rich fixture (non-empty library), the run-task projection must
        // NOT include the prior-work/library block that the chat groundingString has.
        let company = fixtureCompany()
        let ctx = CompanyContext(company: company)
        XCTAssertFalse(ctx.runTaskGroundingString.contains("Landing page draft"),
                       "run-task grounding must stay lean — no library prior-work block")
    }

    func test_projectSlice_fromLink_stillNeverLeaksIntoGroundingString() {
        let company = fixtureCompany()
        let slice = CompanyContext.ProjectSlice(
            path: "/Users/mona/secret", isGitRepo: true, hasClaudeMd: true, recentChangeSummary: nil)
        let ctx = CompanyContext(company: company, query: "x", project: slice)
        XCTAssertFalse(ctx.groundingString.contains("/Users/mona/secret"))
        XCTAssertEqual(ctx.projectSummary?.contains("/Users/mona/secret"), true)
    }

    func test_project_neverLeaksIntoGroundingString() {
        let company = fixtureCompany()
        let secretPath = "/Users/mona/secret-repo"
        let secretChange = "TOPSECRET_CHANGE_9f2a"
        let proj = CompanyContext.ProjectSlice(
            path: secretPath, isGitRepo: true, hasClaudeMd: true, recentChangeSummary: secretChange)
        let ctx = CompanyContext(company: company, query: "anything", project: proj)

        XCTAssertFalse(ctx.groundingString.contains(secretPath),
                       "project path must never reach the cloud grounding string")
        XCTAssertFalse(ctx.groundingString.contains(secretChange),
                       "project change summary must never reach the cloud grounding string")
    }

    func test_projectSummary_isNilWhenUnlinked_andRendersWhenLinked() {
        let company = fixtureCompany()
        XCTAssertNil(CompanyContext(company: company).projectSummary)

        let proj = CompanyContext.ProjectSlice(
            path: "/Users/mona/acme", isGitRepo: false, hasClaudeMd: false, recentChangeSummary: nil)
        let summary = CompanyContext(company: company, project: proj).projectSummary
        XCTAssertNotNil(summary)
        XCTAssertTrue(summary!.contains("/Users/mona/acme"))
        XCTAssertTrue(summary!.contains("Git repo: no"))
    }
}

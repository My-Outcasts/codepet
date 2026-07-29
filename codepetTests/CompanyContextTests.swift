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
        return c
    }

    func test_groundingString_matchesChatContextCompose() {
        let company = fixtureCompany()
        let ctx = CompanyContext(company: company, query: "landing page copy")
        let expected = ChatContext.compose(
            brief: company.brief, tasks: company.tasks, decisions: company.decisions,
            library: company.library, query: "landing page copy", focusDepartment: nil)
        XCTAssertEqual(ctx.groundingString, expected)
    }

    func test_groundingString_matchesCompose_whenNoQuery() {
        let company = fixtureCompany()
        let ctx = CompanyContext(company: company)
        let expected = ChatContext.compose(
            brief: company.brief, tasks: company.tasks, decisions: company.decisions,
            library: company.library, query: nil, focusDepartment: nil)
        XCTAssertEqual(ctx.groundingString, expected)
    }
}

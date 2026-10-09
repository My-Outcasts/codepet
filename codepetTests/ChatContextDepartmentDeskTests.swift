// codepetTests/ChatContextDepartmentDeskTests.swift
import XCTest
@testable import codepet

/// 9 Oct: a question asked of one department got the same context as every other department —
/// three Library excerpts ranked by the query and the first six open tasks, none of them filtered
/// to the department. Finance could not see the pricing sheet it made, and `runway`, collected by
/// the interview, reached no prompt at all. The desk is that department's own work and the brief
/// fields it owns.
final class ChatContextDepartmentDeskTests: XCTestCase {
    private let finance = DepartmentCatalog.find("fin")!
    private let sales = DepartmentCatalog.find("sales")!

    private func doc(_ id: String, _ title: String, body: String = "Body of the work.") -> Deliverable {
        Deliverable(id: id, kind: .doc, title: title, body: body, createdAt: "2026-10-01T00:00:00Z")
    }

    private func task(_ id: String, _ title: String, dept: String, done: Bool = false) -> RoadmapTask {
        RoadmapTask(id: id, title: title, detail: "", phase: .foundation, who: .does, done: done, dept: dept)
    }

    private let brief = CompanyBrief(projectName: "Codepet", traction: "40 on the waitlist",
                                     runway: "8 months at current burn", constraints: "no hiring")

    func testTheDeskCarriesTheDepartmentsOwnWorkAndTasks() {
        let tasks = [task("t1", "Price the Pro plan", dept: "fin", done: true),
                     task("t2", "Model the first year", dept: "fin"),
                     task("t3", "Write the launch post", dept: "mkt")]
        let out = ChatContext.compose(brief: brief, tasks: tasks, focusDepartment: finance,
                                      departmentWork: [doc("p1", "Pricing sheet", body: "Pro is $19 a month.")])
        XCTAssertTrue(out.contains("Finance desk"))
        XCTAssertTrue(out.contains("Pricing sheet"))
        XCTAssertTrue(out.contains("Pro is $19 a month."))
        XCTAssertTrue(out.contains("Done: Price the Pro plan"))
        XCTAssertTrue(out.contains("Open: Model the first year"))
        XCTAssertFalse(out.contains("Done: Write the launch post"))
        XCTAssertFalse(out.contains("Open: Write the launch post"))
    }

    /// The brief fields a department owns go to that department and no other: runway is
    /// Finance's, traction is Sales'. Goes red if the fields are added for everyone or for no one.
    func testBriefFieldsGoToTheDepartmentThatOwnsThem() {
        let fin = ChatContext.compose(brief: brief, tasks: [], focusDepartment: finance)
        XCTAssertTrue(fin.contains("8 months at current burn"))
        XCTAssertTrue(fin.contains("no hiring"))
        XCTAssertFalse(fin.contains("40 on the waitlist"))

        let sal = ChatContext.compose(brief: brief, tasks: [], focusDepartment: sales)
        XCTAssertTrue(sal.contains("40 on the waitlist"))
        XCTAssertFalse(sal.contains("8 months at current burn"))
    }

    /// A field the founder never gave is named as missing — that is what lets the department
    /// say "not on record" instead of making up a runway.
    func testAnOwnedFieldThatIsEmptyIsNamedAsNotOnRecord() {
        let out = ChatContext.compose(brief: CompanyBrief(projectName: "Codepet"), tasks: [],
                                      focusDepartment: finance)
        XCTAssertTrue(out.contains("Runway: not on record"))
    }

    /// A desk item is excerpted once, on the desk — not again under the ranked prior work.
    func testDeskWorkIsNotRepeatedInPriorWork() {
        let pricing = doc("p1", "Pricing sheet", body: "Pro is $19 a month.")
        let out = ChatContext.compose(brief: brief, tasks: [], library: [pricing], query: "pricing",
                                      focusDepartment: finance, departmentWork: [pricing])
        XCTAssertEqual(out.components(separatedBy: "Pro is $19 a month.").count - 1, 1)
    }

    /// An ordinary turn is unchanged: no desk, and no owned field leaks into general chat.
    func testNoDeskWithoutADepartment() {
        let out = ChatContext.compose(brief: brief, tasks: [task("t1", "Price it", dept: "fin")],
                                      departmentWork: [doc("p1", "Pricing sheet")])
        XCTAssertFalse(out.contains("desk"))
        XCTAssertFalse(out.contains("8 months at current burn"))
    }
}

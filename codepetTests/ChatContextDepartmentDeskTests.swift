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

    // MARK: - The department's notebook (2026-10-09)

    /// The "- topic: statement" lines under "<Dept> has noted:", and nothing after them.
    private func notes(in out: String, _ dept: String = "Finance") -> [String] {
        guard let after = out.components(separatedBy: "\(dept) has noted:\n").dropFirst().first else { return [] }
        return Array(after.components(separatedBy: "\n").prefix { $0.hasPrefix("- ") })
    }

    private func note(_ topic: String, _ s: String, dept: String?, at t: Double = 1) -> DecisionEntry {
        DecisionEntry(topic: topic, statement: s, source: nil, updatedAt: t, scope: nil, dept: dept)
    }

    func testTheDeskListsOnlyItsOwnNotesAndTheDecisionsBlockDoesNotRepeatThem() {
        let ds = [note("runway", "runway noted at 7 months", dept: "fin"), note("pitch", "one line", dept: "mkt"),
                  note("goal", "ten founders", dept: nil)]
        let out = ChatContext.compose(brief: brief, tasks: [], decisions: ds, focusDepartment: finance)
        XCTAssertTrue(out.contains("Finance has noted:"))
        XCTAssertEqual(out.components(separatedBy: "runway noted at 7 months").count - 1, 1, "on the desk, not again below")
        XCTAssertTrue(out.contains("- goal: ten founders"), "company-wide stays in the decisions block")
        XCTAssertEqual(notes(in: out), ["- runway: runway noted at 7 months"])
    }

    func testNotesAreNewestFirstAndCapped() {
        let ds = (0..<10).map { note("t\($0)", "s\($0)", dept: "fin", at: Double($0)) }
        let out = ChatContext.compose(brief: brief, tasks: [], decisions: ds, focusDepartment: finance)
        let desk = notes(in: out)
        XCTAssertEqual(desk.count, ChatContext.deskNotesCap)
        XCTAssertEqual(desk.first, "- t9: s9")
        XCTAssertFalse(desk.contains("- t1: s1"))
        XCTAssertTrue(out.contains("- t1: s1"), "an older note stays in the decisions block, it is not lost")
    }

    func testMemoryOffMeansNoNotes() {
        let out = ChatContext.compose(brief: brief, tasks: [], decisions: [note("runway", "runway noted at 7 months", dept: "fin")],
                                      focusDepartment: finance, memoryEnabled: false)
        XCTAssertFalse(out.contains("runway noted at 7 months"))
        XCTAssertFalse(out.contains("has noted"))
    }

    /// Review, 9 Oct: moving a note to the desk took it out from under "honor these" — the one
    /// fact Finance is not told to stand by would be Finance's own.
    func testDeskNotesAreStillDecisionsToHonor() {
        let out = ChatContext.compose(brief: brief, tasks: [], decisions: [note("price", "Pro $19", dept: "fin")],
                                      focusDepartment: finance)
        let tail = out.components(separatedBy: "Finance has noted:\n").dropFirst().first ?? ""
        let afterNotes = tail.components(separatedBy: "\n").drop { $0.hasPrefix("- ") }.first ?? ""
        XCTAssertTrue(afterNotes.contains("never contradict"), "got: \(afterNotes)")
    }

    /// Review, 9 Oct: two entries can share an identity (assignDecision). Excluding by identity
    /// dropped the one that was NOT on the desk from the prompt altogether.
    func testAnotherEntryWithTheSameTopicIsNotDroppedFromThePrompt() {
        let ds = [note("pricing", "Finance says $19", dept: "fin"), note("pricing", "Sales says $29", dept: "sales")]
        let out = ChatContext.compose(brief: brief, tasks: [], decisions: ds, focusDepartment: finance)
        XCTAssertTrue(out.contains("Sales says $29"))
    }

    /// End to end through the merge: once Sales re-records Finance's price, Finance's desk no
    /// longer lists it and Sales' does.
    func testAReRecordedTopicMovesDesks() {
        let fin = Decisions.mergeDecisions(existing: [], extracted: [ExtractedDecision(topic: "pricing", statement: "$19", source: nil)],
                                           now: 1, dept: "fin")
        let both = Decisions.mergeDecisions(existing: fin, extracted: [ExtractedDecision(topic: "pricing", statement: "$29", source: nil)],
                                            now: 2, dept: "sales")
        XCTAssertEqual(notes(in: ChatContext.compose(brief: brief, tasks: [], decisions: both, focusDepartment: finance)), [])
        XCTAssertEqual(notes(in: ChatContext.compose(brief: brief, tasks: [], decisions: both, focusDepartment: sales), "Sales"),
                       ["- pricing: $29"])
    }
}

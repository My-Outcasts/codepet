import XCTest
@testable import codepet

// NON-@MainActor by design (Xcode 26.2 bug): SecondBrainData is a pure struct.
final class SecondBrainDataTests: XCTestCase {

    private func task(_ id: String, dept: String?, who: TaskWho = .does,
                      done: Bool = false) -> RoadmapTask {
        RoadmapTask(id: id, title: id, detail: "", phase: .find, who: who, done: done, dept: dept)
    }

    private func company(tasks: [RoadmapTask] = [], library: [Deliverable] = [],
                         companionId: String = "byte", decisions: [DecisionEntry] = []) -> CompanyState {
        CompanyState(brief: CompanyBrief(), departments: [], library: library,
                     stage: .idea, companionId: companionId, tasks: tasks, decisions: decisions)
    }

    func testCountsAndTopics() {
        let tasks = [
            task("a", dept: "eng", who: .you),
            task("b", dept: "eng", who: .does, done: true),
            task("c", dept: "mkt", who: .does),
            task("d", dept: nil,   who: .does),   // untagged → excluded from topics
        ]
        let lib = [Deliverable(kind: .doc, title: "X", body: "")]
        let data = SecondBrainData(company: company(tasks: tasks, library: lib))
        XCTAssertEqual(data.deliverables, 1)
        XCTAssertEqual(data.tasksTotal, 4)
        XCTAssertEqual(data.tasksDone, 1)
        XCTAssertEqual(data.topics.map(\.department.key), ["eng", "mkt"]) // desc by count
        XCTAssertEqual(data.topics.first?.count, 2)
    }

    func testNextStepAndDeptName() {
        let data = SecondBrainData(company: company(tasks: [task("a", dept: "design")]))
        XCTAssertEqual(data.nextTask?.id, "a")
        XCTAssertEqual(data.nextDeptName, "Design")
    }

    func testDecisionsCount() {
        let entries = [DecisionEntry(topic: "pricing", statement: "$9/mo", source: nil, updatedAt: nil),
                       DecisionEntry(topic: "naming", statement: "Codepet", source: nil, updatedAt: nil)]
        let data = SecondBrainData(company: company(decisions: entries))
        XCTAssertEqual(data.decisions, 2)
        XCTAssertEqual(SecondBrainData(company: company()).decisions, 0)
    }

    func testCompanionNameResolves() {
        // Both are real hits distinguishable from the `?? "Codepet"` fallback — byte included,
        // since it was renamed to "Byte" on 26 Aug. This catches a broken lookup.
        XCTAssertEqual(SecondBrainData(company: company(companionId: "byte")).companionName, "Byte")
        XCTAssertEqual(SecondBrainData(company: company(companionId: "nova")).companionName, "Nova")
        XCTAssertEqual(SecondBrainData(company: company(companionId: "nope")).companionName,
                       "Codepet")
    }

    func testEmptyCompanyIsCalm() {
        let data = SecondBrainData(company: company())
        XCTAssertEqual(data.deliverables, 0)
        XCTAssertEqual(data.tasksTotal, 0)
        XCTAssertEqual(data.decisions, 0)
        XCTAssertTrue(data.topics.isEmpty)
        XCTAssertNil(data.nextTask)
        XCTAssertNil(data.nextDeptName)
    }
}

import XCTest
@testable import codepet

final class FirstRunGreetingTests: XCTestCase {
    private func task(_ id: String, _ title: String) -> RoadmapTask {
        RoadmapTask(id: id, title: title, detail: "", phase: .find, who: .does)
    }

    func testNameAndNextStepProducesAction() {
        let g = FirstRunGreetingBuilder.build(
            brief: CompanyBrief(founderName: "Mona", projectName: "Codepet"),
            nextStep: task("t1", "Write your landing page"), language: .en)
        XCTAssertTrue(g.text.hasPrefix("Mona, your company for Codepet is ready."))
        XCTAssertTrue(g.text.contains("The best first move is \"Write your landing page\"."))
        XCTAssertEqual(g.action, FirstRunAction(taskId: "t1", taskTitle: "Write your landing page"))
    }

    func testNoNameFallsBackToGenericLead() {
        let g = FirstRunGreetingBuilder.build(
            brief: CompanyBrief(projectName: "Codepet"),
            nextStep: task("t1", "X"), language: .en)
        XCTAssertTrue(g.text.hasPrefix("Your company for Codepet is ready."))
    }

    func testNoProjectNameUsesPlaceholder() {
        let g = FirstRunGreetingBuilder.build(
            brief: CompanyBrief(founderName: "Mona"), nextStep: nil, language: .en)
        XCTAssertTrue(g.text.contains("your product"))
    }

    func testNoNextStepHasNoAction() {
        let g = FirstRunGreetingBuilder.build(
            brief: CompanyBrief(founderName: "Mona", projectName: "Codepet"),
            nextStep: nil, language: .en)
        XCTAssertNil(g.action)
        XCTAssertTrue(g.text.contains("Take a look around"))
    }

    func testVietnameseLeadNoAction() {
        let g = FirstRunGreetingBuilder.build(
            brief: CompanyBrief(founderName: "Mona", projectName: "Codepet"),
            nextStep: nil, language: .vi)
        XCTAssertTrue(g.text.contains("đã sẵn sàng"))
        XCTAssertNil(g.action)
    }
}

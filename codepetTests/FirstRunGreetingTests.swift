import XCTest
@testable import codepet

final class FirstRunGreetingTests: XCTestCase {
    private func task(_ id: String, _ title: String, _ phase: RoadmapPhase = .find) -> RoadmapTask {
        RoadmapTask(id: id, title: title, detail: "", phase: phase, who: .does)
    }

    func testNameAndNextStepProducesAction() {
        let t = task("t1", "Write your landing page")
        let g = FirstRunGreetingBuilder.build(
            brief: CompanyBrief(founderName: "Mona", projectName: "Codepet"),
            nextStep: t, tasks: [t], language: .en)
        XCTAssertTrue(g.text.hasPrefix("Mona, your company for Codepet is ready."))
        XCTAssertTrue(g.text.contains("The best first move is \"Write your landing page\"."))
        XCTAssertEqual(g.action, FirstRunAction(taskId: "t1", taskTitle: "Write your landing page"))
    }

    func testNoNameFallsBackToGenericLead() {
        let t = task("t1", "X")
        let g = FirstRunGreetingBuilder.build(
            brief: CompanyBrief(projectName: "Codepet"),
            nextStep: t, tasks: [t], language: .en)
        XCTAssertTrue(g.text.hasPrefix("Your company for Codepet is ready."))
    }

    func testNoProjectNameUsesPlaceholder() {
        let g = FirstRunGreetingBuilder.build(
            brief: CompanyBrief(founderName: "Mona"), nextStep: nil, tasks: [], language: .en)
        XCTAssertTrue(g.text.contains("your product"))
    }

    func testNoNextStepHasNoAction() {
        let g = FirstRunGreetingBuilder.build(
            brief: CompanyBrief(founderName: "Mona", projectName: "Codepet"),
            nextStep: nil, tasks: [], language: .en)
        XCTAssertNil(g.action)
        XCTAssertTrue(g.text.contains("Take a look around"))
    }

    func testVietnameseLeadNoAction() {
        let g = FirstRunGreetingBuilder.build(
            brief: CompanyBrief(founderName: "Mona", projectName: "Codepet"),
            nextStep: nil, tasks: [], language: .vi)
        XCTAssertTrue(g.text.contains("đã sẵn sàng"))
        XCTAssertNil(g.action)
    }

    // MARK: - The paragraphs added 2026-09-18

    /// Order is load-bearing: the founder should meet her project before her first task.
    func testTheReadComesBetweenTheLeadAndTheMove() {
        let brief = CompanyBrief(founderName: "Mona", stage: "Building",
                                 projectName: "Codepet",
                                 oneLiner: "A macOS AI coding companion")
        let t = task("t1", "Lock the pricing copy", .foundation)
        let g = FirstRunGreetingBuilder.build(brief: brief, nextStep: t,
                                              tasks: [t], language: .en)

        let lead = g.text.range(of: "Mona, your company for Codepet is ready.")
        let read = g.text.range(of: "Here's what I understood")
        let move = g.text.range(of: "The best first move is")
        XCTAssertNotNil(lead); XCTAssertNotNil(read); XCTAssertNotNil(move)
        XCTAssertTrue(lead!.lowerBound < read!.lowerBound)
        XCTAssertTrue(read!.lowerBound < move!.lowerBound)
    }

    func testTheShapeLineIsIncludedWhenThereAreTasks() {
        let brief = CompanyBrief(stage: "Building", projectName: "Codepet",
                                 oneLiner: "A macOS AI coding companion")
        let tasks = [task("a", "A", .foundation), task("b", "B", .find)]
        let g = FirstRunGreetingBuilder.build(brief: brief, nextStep: tasks[0],
                                              tasks: tasks, language: .en)
        XCTAssertTrue(g.text.contains("2 tasks across 2 phases"))
    }

    /// A brief with no anchor must not produce a dangling "Here's what I understood:" —
    /// the paragraph is dropped whole and the greeting still reads as prose.
    func testAnUnreadableBriefDropsTheParagraphNotTheGreeting() {
        let brief = CompanyBrief(founderName: "Mona", stage: "Building", projectName: "Codepet")
        let t = task("t1", "Lock the pricing copy", .foundation)
        let g = FirstRunGreetingBuilder.build(brief: brief, nextStep: t,
                                              tasks: [t], language: .en)
        XCTAssertFalse(g.text.contains("Here's what I understood"))
        XCTAssertTrue(g.text.contains("Mona, your company for Codepet is ready."))
        XCTAssertTrue(g.text.contains("The best first move is"))
        XCTAssertFalse(g.text.contains("\n\n\n"), "a dropped paragraph left a hole")
    }

    /// The existing no-task branch keeps its own tail and gains no shape line.
    ///
    /// Asserted on "tasks across", not on "lined up": the no-task TAIL already says
    /// "see what I've lined up", so that phrase cannot tell the shape line apart from the
    /// copy that shipped before it. A first draft of this test asserted the wrong substring
    /// and failed against correct code.
    func testNoTasksKeepsTheLookAroundTailAndNoShapeLine() {
        let brief = CompanyBrief(stage: "Building", projectName: "Codepet",
                                 oneLiner: "A macOS AI coding companion")
        let g = FirstRunGreetingBuilder.build(brief: brief, nextStep: nil,
                                              tasks: [], language: .en)
        XCTAssertTrue(g.text.contains("Take a look around"))
        XCTAssertFalse(g.text.contains("tasks across"), "a shape line was emitted for an empty board")
        XCTAssertFalse(g.text.contains("phases"))
        XCTAssertNil(g.action)
    }

    /// `CopilotChatView.prose` splits on blank lines and renders one block per paragraph,
    /// so the separator has to be a real blank line.
    func testTheGreetingIsParagraphsNotOneRun() {
        let brief = CompanyBrief(founderName: "Mona", stage: "Building",
                                 projectName: "Codepet",
                                 oneLiner: "A macOS AI coding companion")
        let t = task("t1", "Lock the pricing copy", .foundation)
        let g = FirstRunGreetingBuilder.build(brief: brief, nextStep: t,
                                              tasks: [t], language: .en)
        XCTAssertEqual(g.text.components(separatedBy: "\n\n").count, 4,
                       "expected lead + read + shape + move")
    }

    /// Every greeting offers the tour; the store reads this rather than assuming.
    func testTheGreetingOffersTheTour() {
        let t = task("t1", "Lock the pricing copy", .foundation)
        let g = FirstRunGreetingBuilder.build(
            brief: CompanyBrief(founderName: "Mona", projectName: "Codepet"),
            nextStep: t, tasks: [t], language: .en)
        XCTAssertTrue(g.offersTour)
    }
}

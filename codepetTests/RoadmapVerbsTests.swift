// codepetTests/RoadmapVerbsTests.swift
import XCTest
@testable import codepet

/// The chat can now change the roadmap — by proposing, never by applying.
///
/// Before this it had four verbs (run an existing task, navigate, enable a toolkit item, remember a
/// fact) and none touched the roadmap: it could DO a task that existed and point at the board, but
/// not create one or complete one. Founder, Aug 8: "the chat should be the central brain, with all
/// other features operating in accordance with it."
@MainActor
final class RoadmapVerbsTests: XCTestCase {

    private static let deadStream: (CompanyChatRequest) -> AsyncThrowingStream<CompanyChatStreamEvent, Error> = { _ in
        AsyncThrowingStream { $0.finish(throwing: CompanyChatStreamError.notSignedIn) }
    }

    private func store(_ reply: CompanyChatReply?, tasks: [RoadmapTask],
                       taskSaves: @escaping () -> Void = {}) -> CompanyStore {
        CompanyStore(
            loader: { _ in
                CompanyState(brief: CompanyBrief(), departments: [], library: [], stage: .idea,
                             companionId: "byte", onboardedAt: Date(), tasks: tasks)
            },
            saver: { _, _ in true },
            tasksSaver: { _, _ in taskSaves(); return true },
            chatSender: { _ in reply },
            chatStreamer: Self.deadStream,
            decisionExtractor: { _, _ in [] })
    }

    private func mine(_ id: String = "t1") -> RoadmapTask {
        RoadmapTask(id: id, title: "Talk to 5 potential users", detail: "", phase: .find, who: .you)
    }

    // MARK: - complete_task

    /// The verb whose absence caused "you can consider this step done" followed by a nav chip.
    func testCompleteTaskProposesAndChangesNothingYet() async {
        let s = store(CompanyChatReply(text: "Nice.", completeTaskId: "t1"), tasks: [mine()])
        await s.hydrate(companyId: "u")
        await s.sendChat("I talked to them already", language: .en)

        XCTAssertFalse(s.company.tasks[0].done, "a proposal must not change the roadmap")
        let offer = s.chatMessages.last { $0.roadmapProposal != nil }
        XCTAssertEqual(offer?.roadmapProposal,
                       .complete(taskId: "t1", title: "Talk to 5 potential users"))
    }

    func testConfirmingCompletesTheTaskExactlyOnce() async {
        var saves = 0
        let s = store(CompanyChatReply(text: "Nice.", completeTaskId: "t1"),
                      tasks: [mine()], taskSaves: { saves += 1 })
        await s.hydrate(companyId: "u")
        await s.sendChat("done that", language: .en)
        guard let id = s.chatMessages.last(where: { $0.roadmapProposal != nil })?.id else {
            return XCTFail("no proposal")
        }
        await s.confirmRoadmapProposal(messageId: id, language: .en)
        XCTAssertTrue(s.company.tasks[0].done)

        await s.confirmRoadmapProposal(messageId: id, language: .en)
        XCTAssertTrue(s.company.tasks[0].done, "a second press must not toggle it back OFF")
        XCTAssertEqual(saves, 1)
    }

    /// A task that is already done, or that the model invented, must not produce an offer at all.
    func testNoOfferForAnAlreadyDoneOrUnknownTask() async {
        let done = RoadmapTask(id: "t1", title: "x", detail: "", phase: .find, who: .you, done: true)
        let a = store(CompanyChatReply(text: "ok", completeTaskId: "t1"), tasks: [done])
        await a.hydrate(companyId: "u")
        await a.sendChat("done", language: .en)
        XCTAssertNil(a.chatMessages.last { $0.roadmapProposal != nil })

        let b = store(CompanyChatReply(text: "ok", completeTaskId: "ghost"), tasks: [mine()])
        await b.hydrate(companyId: "u")
        await b.sendChat("done", language: .en)
        XCTAssertNil(b.chatMessages.last { $0.roadmapProposal != nil })
    }

    // MARK: - add_task

    func testAddTaskProposesALeafInTheCurrentPhase() async {
        let reply = CompanyChatReply(text: "Sure.", addTask: AddTaskDTO(
            title: "Call the two bakeries who asked to pay",
            detail: "Find out what they would pay.", dept: "sales", owner: "founder"))
        let s = store(reply, tasks: [mine()])
        await s.hydrate(companyId: "u")
        await s.sendChat("add a task to call them", language: .en)
        guard let id = s.chatMessages.last(where: { $0.roadmapProposal != nil })?.id else {
            return XCTFail("no proposal")
        }
        XCTAssertEqual(s.company.tasks.count, 1, "proposing must not add anything")

        await s.confirmRoadmapProposal(messageId: id, language: .en)
        XCTAssertEqual(s.company.tasks.count, 2)
        let added = s.company.tasks[1]
        XCTAssertEqual(added.title, "Call the two bakeries who asked to pay")
        XCTAssertEqual(added.dept, "sales")
        XCTAssertEqual(added.who, .you)
        // Founder's call, Aug 8: chat-created tasks are LEAVES. A model guessing at a dependency
        // graph is how a roadmap becomes unusable.
        XCTAssertTrue(added.dependsOn.isEmpty, "a chat-created task must never invent dependencies")
        XCTAssertEqual(added.phase, .find, "it lands in the phase she is working in")
    }

    func testCodepetOwnedTasksArriveRunnable() async {
        let reply = CompanyChatReply(text: "Sure.", addTask: AddTaskDTO(
            title: "Draft the refund policy", detail: "", dept: "legal", owner: "codepet"))
        let s = store(reply, tasks: [mine()])
        await s.hydrate(companyId: "u")
        await s.sendChat("add that", language: .en)
        guard let id = s.chatMessages.last(where: { $0.roadmapProposal != nil })?.id else {
            return XCTFail("no proposal")
        }
        await s.confirmRoadmapProposal(messageId: id, language: .en)
        XCTAssertEqual(s.company.tasks[1].who, .does)
    }

    /// Two identical offers would let her confirm one and leave an orphan that adds a duplicate.
    func testTheSameProposalIsNotOfferedTwice() async {
        let s = store(CompanyChatReply(text: "ok", completeTaskId: "t1"), tasks: [mine()])
        await s.hydrate(companyId: "u")
        await s.sendChat("done that", language: .en)
        await s.sendChat("I said done", language: .en)
        XCTAssertEqual(s.chatMessages.filter { $0.roadmapProposal != nil }.count, 1)
    }
}

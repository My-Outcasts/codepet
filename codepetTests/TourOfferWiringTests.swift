// codepetTests/TourOfferWiringTests.swift
import XCTest
@testable import codepet

/// The greeting's tour chip: offered, tappable once, and never entangled with the primary
/// "Do it with me" action.
@MainActor
final class TourOfferWiringTests: XCTestCase {

    // MARK: - The two flags stay independent

    /// `actionConsumed` is shared by firstRunAction, runProposal, chainOffer and vcRun.
    /// Reusing it here would make "Do it with me" retire the tour chip, and the reverse.
    func testConsumingThePrimaryActionLeavesTheTourOffered() {
        var m = CopilotMessage(role: .companion, text: "hi",
                               firstRunAction: FirstRunAction(taskId: "t1", taskTitle: "T"))
        m.tourOffer = true
        m.actionConsumed = true
        XCTAssertTrue(m.tourOffer)
        XCTAssertFalse(m.tourConsumed, "the tour was retired by an unrelated action")
    }

    func testConsumingTheTourLeavesThePrimaryActionAlone() {
        var m = CopilotMessage(role: .companion, text: "hi",
                               firstRunAction: FirstRunAction(taskId: "t1", taskTitle: "T"))
        m.tourOffer = true
        m.tourConsumed = true
        XCTAssertFalse(m.actionConsumed, "the primary action was retired by the tour")
        XCTAssertNotNil(m.firstRunAction)
    }

    /// A message with no tour offer must not accidentally render one.
    func testTourIsNotOfferedByDefault() {
        let m = CopilotMessage(role: .companion, text: "hi")
        XCTAssertFalse(m.tourOffer)
        XCTAssertFalse(m.tourConsumed)
    }

    // MARK: - WHICH SITE draws the chip

    /// Build a greeting-shaped message: text, a primary action, tour offered.
    private func greeting(actionConsumed: Bool = false,
                          tourConsumed: Bool = false,
                          withTask: Bool = true) -> CopilotMessage {
        var m = CopilotMessage(role: .companion, text: "hi",
                               firstRunAction: withTask
                                   ? FirstRunAction(taskId: "t1", taskTitle: "T") : nil)
        m.tourOffer = true
        m.actionConsumed = actionConsumed
        m.tourConsumed = tourConsumed
        return m
    }

    /// CP-013, the regression this suite exists for. Seen on screen 22 Sep: the founder
    /// tapped "Do it with me" and "Show me around" vanished with it.
    ///
    /// The site must move to `.inline`, because `CopilotChatView`'s primary branch is gated
    /// on `!actionConsumed` and stops rendering the moment the action is taken. Asserting
    /// merely that the offer is still LIVE is what the flag tests below already do, and it
    /// stays true while the chip is invisible — which is precisely how this shipped.
    func testTheSiteMovesInlineOnceThePrimaryActionIsTapped() {
        XCTAssertEqual(greeting(actionConsumed: true).tourChipSite, .inline,
                       "the primary's branch has stopped rendering, so the chip must fall "
                       + "through to inlineActions rather than stay claimed by a dead site")
    }

    /// While the primary is on screen the chip rides beside it, so it reads as the second
    /// option rather than jumping to its own row.
    func testTheChipRidesBesideThePrimaryActionUntilItIsTapped() {
        XCTAssertEqual(greeting().tourChipSite, .besidePrimary)
    }

    /// A greeting with no task has no primary branch to sit in.
    func testAGreetingWithNoTaskDrawsTheChipInline() {
        XCTAssertEqual(greeting(withTask: false).tourChipSite, .inline)
    }

    /// Once taken, it draws nowhere — whatever the primary did.
    func testAConsumedTourDrawsNowhere() {
        XCTAssertEqual(greeting(tourConsumed: true).tourChipSite, .nowhere)
        XCTAssertEqual(greeting(actionConsumed: true, tourConsumed: true).tourChipSite, .nowhere)
    }

    /// Never offered means never drawn, so an ordinary reply cannot sprout a tour chip.
    func testAMessageThatNeverOfferedTheTourDrawsNowhere() {
        var m = CopilotMessage(role: .companion, text: "hi")
        m.actionConsumed = true
        XCTAssertEqual(m.tourChipSite, .nowhere)
    }

    // MARK: - The seeded greeting carries it

    func testTheSeededGreetingOffersTheTour() async throws {
        let s = store(tasks: runnable)
        await s.hydrate(companyId: "u")
        await s.greetIfNeeded(language: .en)
        XCTAssertEqual(s.chatMessages.count, 1, "nothing was seeded")
        let g = try XCTUnwrap(s.chatMessages.first)
        XCTAssertTrue(g.tourOffer)
        XCTAssertFalse(g.tourConsumed)
    }

    // MARK: - Tapping it appends the script and retires the chip

    func testActivatingTheTourAppendsTheScriptAndRetiresTheChip() async throws {
        let s = store(tasks: runnable)
        await s.hydrate(companyId: "u")
        await s.greetIfNeeded(language: .en)
        let id = try XCTUnwrap(s.chatMessages.first).id

        s.activateTour(messageId: id, language: .en)

        XCTAssertEqual(s.chatMessages.count, 2, "the tour message was not appended")
        XCTAssertTrue(try XCTUnwrap(s.chatMessages.first).tourConsumed, "the chip was not retired")
        let tour = try XCTUnwrap(s.chatMessages.last)
        XCTAssertTrue(tour.text.contains("Roadmap"))
        XCTAssertEqual(tour.navChip?.destination, "roadmap")
    }

    /// A second tap must not append the tour twice.
    func testASecondTapIsANoOp() async throws {
        let s = store(tasks: runnable)
        await s.hydrate(companyId: "u")
        await s.greetIfNeeded(language: .en)
        let id = try XCTUnwrap(s.chatMessages.first).id
        s.activateTour(messageId: id, language: .en)
        s.activateTour(messageId: id, language: .en)
        XCTAssertEqual(s.chatMessages.count, 2, "the tour was appended twice")
    }

    /// An unknown id must do nothing at all rather than append an orphan tour.
    func testAnUnknownMessageIdDoesNothing() async {
        let s = store(tasks: runnable)
        await s.hydrate(companyId: "u")
        await s.greetIfNeeded(language: .en)
        s.activateTour(messageId: "no-such-message", language: .en)
        XCTAssertEqual(s.chatMessages.count, 1)
    }

    /// The tour answers in the founder's language.
    func testVietnameseTour() async throws {
        let s = store(tasks: runnable)
        await s.hydrate(companyId: "u")
        await s.greetIfNeeded(language: .vi)
        let id = try XCTUnwrap(s.chatMessages.first).id
        s.activateTour(messageId: id, language: .vi)
        XCTAssertEqual(s.chatMessages.last?.text, TourScript.message(language: .vi))
    }

    // MARK: - Helpers

    /// Same stubs as `FirstRunGreetingWiringTests`: the live defaults reach Firestore and
    /// Firebase Auth, both of which trap under an unconfigured `FirebaseApp`.
    private func store(tasks: [RoadmapTask]) -> CompanyStore {
        CompanyStore(loader: { _ in
            var brief = CompanyBrief()
            brief.founderName = "Mona"
            brief.projectName = "Murror"
            return CompanyState(brief: brief, departments: [], library: [], stage: .building,
                                companionId: "byte", onboardedAt: Date(), tasks: tasks)
        }, saver: { _, _ in true }, tasksSaver: { _, _ in true },
           chatSender: { _ in nil },
           chatStreamer: { _ in
               AsyncThrowingStream { $0.finish(throwing: CompanyChatStreamError.notSignedIn) }
           },
           taskRunner: { _ in nil }, librarySaver: { _, _ in true },
           firstApprovalSaver: { _, _ in true },
           greetedSaver: { _, _ in true },
           decisionExtractor: { _, _ in [] })
    }

    private var runnable: [RoadmapTask] {
        [RoadmapTask(id: "t1", title: "Lock the pricing copy", detail: "",
                     phase: .foundation, who: .does)]
    }
}

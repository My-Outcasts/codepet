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

    // MARK: - WHERE the chip draws, not just whether the flag survives

    /// CP-013. The flag tests above pass while the chip is INVISIBLE: its only two render
    /// sites are `CopilotChatView`'s `firstRunAction` branch, gated on `!actionConsumed`,
    /// and `inlineActions`, gated on `firstRunAction == nil`. A greeting that HAS a task
    /// satisfies neither once the primary is tapped, so "Do it with me" silently destroys
    /// "Show me around" -- the exact pairing the separate flags exist to prevent.
    ///
    /// Seen on screen 22 Sep before it was described here.
    func testTheTourChipStillDrawsAfterThePrimaryActionIsTapped() {
        var m = CopilotMessage(role: .companion, text: "hi",
                               firstRunAction: FirstRunAction(taskId: "t1", taskTitle: "T"))
        m.tourOffer = true
        m.actionConsumed = true

        XCTAssertTrue(m.drawsTourChipSomewhere,
                      "the tour offer is live but no render site claims it")
    }

    /// The offer must be drawn by exactly ONE site, never both -- the duplicate the
    /// `firstRunAction == nil` guard was written to stop.
    func testTheChipIsClaimedByExactlyOneSiteWhileOffered() {
        for consumed in [false, true] {
            var m = CopilotMessage(role: .companion, text: "hi",
                                   firstRunAction: FirstRunAction(taskId: "t1", taskTitle: "T"))
            m.tourOffer = true
            m.actionConsumed = consumed

            XCTAssertNotEqual(m.drawsTourChipBesidePrimary, m.drawsTourChipInline,
                              "actionConsumed=\(consumed) drew the chip twice or not at all")
        }
    }

    /// While the primary is still on screen the chip rides beside it, so it keeps reading
    /// as the second option rather than jumping to its own row.
    func testTheChipRidesBesideThePrimaryActionUntilItIsTapped() {
        var m = CopilotMessage(role: .companion, text: "hi",
                               firstRunAction: FirstRunAction(taskId: "t1", taskTitle: "T"))
        m.tourOffer = true

        XCTAssertTrue(m.drawsTourChipBesidePrimary)
        XCTAssertFalse(m.drawsTourChipInline)
    }

    /// A greeting with no task has no primary branch to sit in, so it draws inline.
    func testAGreetingWithNoTaskDrawsTheChipInline() {
        var m = CopilotMessage(role: .companion, text: "hi")
        m.tourOffer = true

        XCTAssertTrue(m.drawsTourChipInline)
        XCTAssertFalse(m.drawsTourChipBesidePrimary)
    }

    /// Once taken, it draws nowhere.
    func testAConsumedTourDrawsNowhere() {
        var m = CopilotMessage(role: .companion, text: "hi",
                               firstRunAction: FirstRunAction(taskId: "t1", taskTitle: "T"))
        m.tourOffer = true
        m.tourConsumed = true

        XCTAssertFalse(m.drawsTourChipSomewhere)
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

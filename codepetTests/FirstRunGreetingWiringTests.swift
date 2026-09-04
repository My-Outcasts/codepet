// codepetTests/FirstRunGreetingWiringTests.swift
import XCTest
@testable import codepet

/// Guards on the first-run greeting actually reaching a founder.
///
/// `FirstRunGreetingBuilder` wrote the right message, carried an inline action to start the
/// first task, and was covered by two suites — and nothing called it. `seedFirstRunGreeting`
/// was reachable only from the first-run enrich interview's completion, and
/// `startEnrichInterviewIfNeeded` has no caller in the app; its own comment says so. So a new
/// founder got the hero and a beacon card, and the message that would have oriented them was
/// unreachable. Reported by the founder, 4 Sep: "as soon as they log in, they're directed
/// straight to a task card — where's the initial prompt?"
@MainActor
final class FirstRunGreetingWiringTests: XCTestCase {

    // MARK: - Task 1: the field and its wire shape

    /// Millis, not ISO — `introSeenAt` and `firstApprovalAt` beside it are numbers.
    func testGreetedPayloadIsEpochMillis() {
        let at = Date(timeIntervalSince1970: 1_700_000_000)
        XCTAssertEqual(CompanyData.greetedPayload(at)["greetedAt"] as? Double,
                       1_700_000_000_000)
    }

    /// **The landmine.** `CompanyState.init(from:)` is hand-written because Swift's synthesised
    /// `Decodable` throws `keyNotFound` rather than falling back to a declared default. Every
    /// company document in Firestore predates this field.
    func testACompanyDocumentWithoutTheFieldStillDecodes() throws {
        let json = #"{"companionId":"byte","stage":"building"}"#
        let state = try JSONDecoder().decode(CompanyState.self, from: Data(json.utf8))
        XCTAssertNil(state.greetedAt)
        XCTAssertEqual(state.companionId, "byte")
    }

    func testItRoundTripsWhenPresent() throws {
        var state = CompanyState.empty
        state.greetedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let back = try JSONDecoder().decode(
            CompanyState.self, from: try JSONEncoder().encode(state))
        XCTAssertEqual(back.greetedAt?.timeIntervalSince1970, 1_700_000_000)
    }

    // MARK: - Task 2: the gate

    /// A pure static, not a condition inside `hydrate`. Three inputs' worth of truth table is
    /// where a bug here would live, and a condition inside an async store method is only
    /// testable by driving the whole store.
    func testGreetsOnlyAFreshAccountWithWorkToName() {
        XCTAssertTrue(FirstRunGreetingGate.shouldGreet(
            hasBeenGreeted: false, transcriptIsEmpty: true, hasTasks: true))
    }

    func testDoesNotGreetTwice() {
        XCTAssertFalse(FirstRunGreetingGate.shouldGreet(
            hasBeenGreeted: true, transcriptIsEmpty: true, hasTasks: true))
    }

    /// The trap the persisted flag exists for: `newChat()` empties the transcript.
    func testDoesNotGreetIntoAConversationInProgress() {
        XCTAssertFalse(FirstRunGreetingGate.shouldGreet(
            hasBeenGreeted: false, transcriptIsEmpty: false, hasTasks: true))
    }

    /// With no roadmap there is no first move to name, and the builder falls back to "Take a
    /// look around…" — a weaker message not worth spending the one-time greeting on. Wait for
    /// the next hydrate, when the roadmap has resolved.
    func testDoesNotGreetBeforeTheRoadmapExists() {
        XCTAssertFalse(FirstRunGreetingGate.shouldGreet(
            hasBeenGreeted: false, transcriptIsEmpty: true, hasTasks: false))
    }

    // MARK: - Task 3: through the store

    /// Same stubs as `CompanyStoreChatRunTests`: the live defaults reach Firestore and Firebase
    /// Auth, both of which trap under an unconfigured `FirebaseApp`.
    private func store(tasks: [RoadmapTask],
                       greetedAt: Date? = nil,
                       saver: @escaping (String, Date) async -> Bool = { _, _ in true })
        -> CompanyStore {
        CompanyStore(loader: { _ in
            var brief = CompanyBrief()
            brief.founderName = "Mona"
            brief.projectName = "Murror"
            var s = CompanyState(brief: brief, departments: [], library: [], stage: .building,
                                 companionId: "byte", onboardedAt: Date(), tasks: tasks)
            s.greetedAt = greetedAt
            return s
        }, saver: { _, _ in true }, tasksSaver: { _, _ in true },
           chatSender: { _ in nil },
           chatStreamer: { _ in
               AsyncThrowingStream { $0.finish(throwing: CompanyChatStreamError.notSignedIn) }
           },
           taskRunner: { _ in nil }, librarySaver: { _, _ in true },
           firstApprovalSaver: { _, _ in true },
           greetedSaver: saver,
           decisionExtractor: { _, _ in [] })
    }

    private var runnable: [RoadmapTask] {
        [RoadmapTask(id: "t1", title: "Write your landing page copy", detail: "",
                     phase: .find, who: .does, dept: "mkt")]
    }

    /// The whole point: a new founder's first screen carries the greeting.
    func testAFreshAccountIsGreetedOnHydrate() async throws {
        let s = store(tasks: runnable)
        await s.hydrate(companyId: "u")
        XCTAssertTrue(s.chatMessages.isEmpty, "hydrate alone must not seed a message")
        await s.greetIfNeeded(language: .en)
        XCTAssertEqual(s.chatMessages.count, 1)
        let g = try XCTUnwrap(s.chatMessages.first)
        XCTAssertEqual(g.role, .companion)
        XCTAssertTrue(g.text.contains("Mona"), g.text)
        XCTAssertTrue(g.text.contains("Murror"), g.text)
        XCTAssertTrue(g.text.contains("Write your landing page copy"), g.text)
        XCTAssertNotNil(g.firstRunAction, "the founder must be able to start it from here")
        XCTAssertNotNil(s.company.greetedAt, "and the account is marked as greeted")
    }

    /// The rule the greeting itself states. Asserted because it is the reason this message is
    /// worth reaching a founder at all, and a copy edit that dropped it should go red.
    func testTheGreetingStatesThatNothingShipsWithoutApproval() async throws {
        let s = store(tasks: runnable)
        await s.hydrate(companyId: "u")
        await s.greetIfNeeded(language: .en)
        let text = try XCTUnwrap(s.chatMessages.first?.text)
        XCTAssertTrue(text.contains("nothing ships without your say-so"), text)
    }

    func testAnAlreadyGreetedAccountIsNotGreetedAgain() async {
        let s = store(tasks: runnable, greetedAt: Date(timeIntervalSince1970: 1))
        await s.hydrate(companyId: "u")
        await s.greetIfNeeded(language: .en)
        XCTAssertTrue(s.chatMessages.isEmpty)
    }

    func testAnEmptyRoadmapIsNotGreeted() async {
        let s = store(tasks: [])
        await s.hydrate(companyId: "u")
        await s.greetIfNeeded(language: .en)
        XCTAssertTrue(s.chatMessages.isEmpty)
        XCTAssertNil(s.company.greetedAt, "and NOT marked greeted — try again next time")
    }

    /// Fail-soft: a rejected write still marks the account greeted in memory, so a founder is
    /// not welcomed twice inside one session.
    func testAFailedWriteStillMarksTheSessionGreeted() async {
        let s = store(tasks: runnable, saver: { _, _ in false })
        await s.hydrate(companyId: "u")
        await s.greetIfNeeded(language: .en)
        XCTAssertEqual(s.chatMessages.count, 1)
        XCTAssertNotNil(s.company.greetedAt)
    }

    /// **The boundary this design exists for.** The greeting lived inside `hydrate` for one
    /// commit. 34 suites call `hydrate` and 14 of them assert on `chatMessages`, so seeding a
    /// message there shifted the baseline of the entire store suite — not 14 broken tests, but
    /// the wrong seam. `hydrate` loads company DATA; starting a conversation is a separate
    /// concern, and this asserts they stay separate.
    func testHydrateAloneNeverTouchesTheTranscript() async {
        let s = store(tasks: runnable)
        await s.hydrate(companyId: "u")
        XCTAssertTrue(s.chatMessages.isEmpty)
        XCTAssertNil(s.company.greetedAt, "and nothing is written until the greeting is asked for")
    }

    /// Greeting twice in one session appends once — the guard is the flag, not the caller's
    /// discipline, because `ContentView` can re-run its task on a token refresh.
    func testCallingGreetTwiceAppendsOnce() async {
        let s = store(tasks: runnable)
        await s.hydrate(companyId: "u")
        await s.greetIfNeeded(language: .en)
        await s.greetIfNeeded(language: .en)
        XCTAssertEqual(s.chatMessages.count, 1)
    }

}

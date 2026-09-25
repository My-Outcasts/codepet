// codepetTests/CompanyStoreReviseWorkTests.swift
import XCTest
@testable import codepet

/// Revising approved work, end to end in the store (CP-025, spec test 7).
///
/// Found 24 Sep on prod build 3: every revision of an approved landing page offered a NEW roadmap
/// task and, once approved, filed a NEW Library item. The fix: the app sends its delivered work,
/// the model answers a revision with `revise_work`, and the app offers a revise pass of the item's
/// own task — never a new task — whose approval replaces the item in place.
///
/// These drive the non-streaming fallback (the streamer is dead), which is the path that once
/// dropped `add_task` because nobody threaded it through. The streaming decode is pinned in
/// `CompanyChatClientTests`.
@MainActor
final class CompanyStoreReviseWorkTests: XCTestCase {

    private static let deadStream: (CompanyChatRequest) -> AsyncThrowingStream<CompanyChatStreamEvent, Error> = { _ in
        AsyncThrowingStream { $0.finish(throwing: CompanyChatStreamError.notSignedIn) }
    }

    private let landing = Deliverable(id: "L1", kind: .site, title: "Landing page", body: "# v1",
                                      createdAt: "2026-09-24T10:00:00Z", sourceTaskId: "t1")
    private let pricing = Deliverable(id: "L2", kind: .doc, title: "Pricing", body: "p",
                                      createdAt: "2026-09-24T11:00:00Z", sourceTaskId: "t2")
    /// A chat ask no roadmap task owns. A revise pass needs a task to run, so this is never
    /// offered for revision — it falls back to today's behaviour.
    private let orphan = Deliverable(id: "L3", kind: .doc, title: "Loose notes", body: "n",
                                     createdAt: "2026-09-24T12:00:00Z")

    private func done(_ id: String, _ title: String) -> RoadmapTask {
        var t = RoadmapTask(id: id, title: title, detail: "", phase: .find, who: .does, dept: "mkt")
        t.done = true
        return t
    }

    private func store(reply: CompanyChatReply?,
                       library: [Deliverable]? = nil,
                       requests: @escaping (CompanyChatRequest) -> Void = { _ in },
                       runs: @escaping (RunTaskRequest) -> Void = { _ in },
                       runBody: String = "# v2") -> CompanyStore {
        let lib = library ?? [landing, pricing]
        return CompanyStore(
            loader: { _ in
                CompanyState(brief: CompanyBrief(), departments: [], library: lib, stage: .idea,
                             companionId: "byte", onboardedAt: Date(),
                             tasks: [self.done("t1", "Redesign the landing page"),
                                     self.done("t2", "Decide your pricing")])
            },
            saver: { _, _ in true },
            tasksSaver: { _, _ in true },
            chatSender: { req in requests(req); return reply },
            chatStreamer: Self.deadStream,
            taskRunner: { req in
                runs(req)
                return RunTaskResponse(kind: "site", title: "Landing page", body: runBody)
            },
            librarySaver: { _, _ in true },
            firstApprovalSaver: { _, _ in true },
            decisionExtractor: { _, _ in [] })
    }

    private let editorial = CompanyChatReply(
        text: "Sure.", reviseWork: ReviseWorkDTO(libraryId: "L1", note: "more editorial type"))

    private func offerId(_ s: CompanyStore) -> String? {
        s.chatMessages.last { m in
            if case .revise = m.roadmapProposal { return true } else { return false }
        }?.id
    }

    // MARK: - The request

    func testTheRequestCarriesDeliveredWorkNewestFirstAndOnlyWhatCanBeRevised() async {
        var sent: CompanyChatRequest?
        let s = store(reply: CompanyChatReply(text: "ok"), library: [landing, pricing, orphan],
                      requests: { sent = $0 })
        await s.hydrate(companyId: "u")
        await s.sendChat("hello", language: .en)

        XCTAssertEqual(sent?.delivered?.map(\.id), ["L2", "L1"],
                       "newest first, and the task-less item left out")
        XCTAssertEqual(sent?.delivered?.last, DeliveredRef(id: "L1", kind: "site", title: "Landing page",
                                                            taskId: "t1"))
    }

    func testAnEmptyLibrarySendsNoDeliveredKeyAtAll() throws {
        let req = CompanyChatRequest(companyId: "u", language: "en", companionId: "byte",
                                     context: "", history: [], userMessage: "hi")
        let json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(req)) as? [String: Any]
        XCTAssertNil(json?["delivered"], "an empty list would put a new key on every request")
    }

    // MARK: - The offer

    func testReviseWorkIsOfferedAndChangesNothingYet() async {
        var runs = 0
        let s = store(reply: editorial, runs: { _ in runs += 1 })
        await s.hydrate(companyId: "u")
        await s.sendChat("make the landing page more editorial", language: .en)

        let offer = s.chatMessages.last { $0.roadmapProposal != nil }?.roadmapProposal
        XCTAssertEqual(offer, .revise(libraryId: "L1", title: "Landing page", note: "more editorial type"))
        XCTAssertEqual(runs, 0, "a revise pass spends credits, so it must wait for the press")
        XCTAssertEqual(s.company.tasks.count, 2, "a revision must never add a roadmap task")
        XCTAssertEqual(s.company.library.map(\.id), ["L1", "L2"])
    }

    func testNoOfferForAnItemTheLibraryDoesNotHave() async {
        let s = store(reply: CompanyChatReply(
            text: "Sure.", reviseWork: ReviseWorkDTO(libraryId: "L9", note: "x")))
        await s.hydrate(companyId: "u")
        await s.sendChat("change it", language: .en)
        XCTAssertNil(offerId(s))
    }

    func testTheSameOfferIsNotMadeTwice() async {
        let s = store(reply: editorial)
        await s.hydrate(companyId: "u")
        await s.sendChat("make it more editorial", language: .en)
        await s.sendChat("make it more editorial", language: .en)

        let open = s.chatMessages.filter { m in
            if case .revise = m.roadmapProposal, !m.actionConsumed { return true } else { return false }
        }
        XCTAssertEqual(open.count, 1)
    }

    // MARK: - Pressing it

    func testPressingRunsARevisePassOfTheItemsOwnTask() async throws {
        var runs: [RunTaskRequest] = []
        let s = store(reply: editorial, runs: { runs.append($0) })
        await s.hydrate(companyId: "u")
        await s.sendChat("make it more editorial", language: .en)
        let id = try XCTUnwrap(offerId(s))

        await s.confirmRoadmapProposal(messageId: id, language: .en)

        XCTAssertEqual(runs.count, 1)
        XCTAssertEqual(runs.first?.taskId, "t1")
        XCTAssertEqual(runs.first?.reviseNote, "more editorial type")
        XCTAssertEqual(runs.first?.current, "# v1", "revise the approved version, not regenerate")
        let draft = try XCTUnwrap(s.chatMessages.last { $0.draft != nil }?.draft)
        XCTAssertEqual(draft.supersedes, "L1")
        XCTAssertEqual(s.company.tasks.count, 2)
        XCTAssertTrue(s.company.tasks[0].done, "the original task stays done")
    }

    func testADoublePressSpendsOnce() async throws {
        var runs = 0
        let s = store(reply: editorial, runs: { _ in runs += 1 })
        await s.hydrate(companyId: "u")
        await s.sendChat("make it more editorial", language: .en)
        let id = try XCTUnwrap(offerId(s))

        async let a: Void = s.confirmRoadmapProposal(messageId: id, language: .en)
        async let b: Void = s.confirmRoadmapProposal(messageId: id, language: .en)
        _ = await (a, b)

        XCTAssertEqual(runs, 1)
    }

    // MARK: - The whole loop — the bug, closed

    func testApprovingTheRevisionReplacesTheItemAndAddsNoTask() async throws {
        let s = store(reply: editorial)
        await s.hydrate(companyId: "u")
        await s.sendChat("make it more editorial", language: .en)
        await s.confirmRoadmapProposal(messageId: try XCTUnwrap(offerId(s)), language: .en)
        let card = try XCTUnwrap(s.chatMessages.last { $0.draft != nil }?.id)

        await s.approveDraft(messageId: card)

        XCTAssertEqual(s.company.library.map(\.id), ["L1", "L2"], "the revision was filed as a new item")
        XCTAssertEqual(s.company.library[0].body, "# v2")
        XCTAssertEqual(s.company.library[0].versions?.map(\.body), ["# v1"])
        XCTAssertEqual(s.company.tasks.count, 2)
    }

    /// The card must say the item was UPDATED — the store records what approval actually did.
    func testApprovingARevisionMarksTheCardAsHavingReplacedAnItem() async throws {
        let s = store(reply: editorial)
        await s.hydrate(companyId: "u")
        await s.sendChat("make it more editorial", language: .en)
        await s.confirmRoadmapProposal(messageId: try XCTUnwrap(offerId(s)), language: .en)
        let card = try XCTUnwrap(s.chatMessages.last { $0.draft != nil }?.id)

        await s.approveDraft(messageId: card)

        XCTAssertEqual(s.chatMessages.first { $0.id == card }?.draftReplacedItem, true)
    }

    /// The revise chips on the revision's OWN card rebuild the draft from the run result. If that
    /// rebuild forgot `supersedes`, a founder who tweaked the revision once before approving would
    /// get the old bug back: a second Library item.
    func testChipRevisingTheRevisionBeforeApprovingKeepsItsLink() async throws {
        let s = store(reply: editorial)
        await s.hydrate(companyId: "u")
        await s.sendChat("make it more editorial", language: .en)
        await s.confirmRoadmapProposal(messageId: try XCTUnwrap(offerId(s)), language: .en)
        let card = try XCTUnwrap(s.chatMessages.last { $0.draft != nil }?.id)

        await s.redoDraft(messageId: card, language: .en, reviseNote: "shorter")

        XCTAssertEqual(s.chatMessages.first { $0.id == card }?.draft?.supersedes, "L1")
    }
}

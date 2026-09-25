// codepetTests/CompanyStoreRevisionApprovalTests.swift
import XCTest
@testable import codepet

/// The store's one approval path, `fileApproval`, must file through `LibraryFiling` — so approving
/// a revision replaces the Library item it supersedes instead of appending a second one (CP-025).
///
/// Driven through `approveTask`, which shares `fileApproval` with the chat card's `approveDraft`
/// (see `ApprovalParityTests`), because a task draft can be seeded through the loader while a chat
/// draft needs a model turn.
@MainActor
final class CompanyStoreRevisionApprovalTests: XCTestCase {

    private let landing = Deliverable(id: "L1", kind: .site, title: "Landing v1", body: "# v1",
                                      sourceTaskId: "t1")

    private func store(library: [Deliverable], tasks: [RoadmapTask],
                       librarySaves: @escaping ([Deliverable]) -> Void = { _ in }) -> CompanyStore {
        CompanyStore(
            loader: { _ in
                CompanyState(brief: CompanyBrief(), departments: [], library: library, stage: .idea,
                             companionId: "byte", onboardedAt: Date(), tasks: tasks)
            },
            saver: { _, _ in true },
            tasksSaver: { _, _ in true },
            chatSender: { _ in CompanyChatReply(text: "") },
            chatStreamer: { _ in AsyncThrowingStream { $0.finish(throwing: CompanyChatStreamError.notSignedIn) } },
            taskRunner: { _ in nil },
            librarySaver: { _, lib in librarySaves(lib); return true },
            firstApprovalSaver: { _, _ in true },
            decisionExtractor: { _, _ in [] })
    }

    private func taskAwaitingApproval(of draft: Deliverable) -> RoadmapTask {
        var t = RoadmapTask(id: "t2", title: "Rework the landing page", detail: "", phase: .find,
                            who: .does, dept: "mkt")
        t.draft = draft
        t.drafted = true
        return t
    }

    func testApprovingARevisionReplacesTheLibraryItemAndSavesThatLibrary() async {
        let revision = Deliverable(id: "D9", kind: .site, title: "Landing v2", body: "# v2",
                                   sourceTaskId: "t2", supersedes: "L1")
        var saved: [Deliverable]?
        let s = store(library: [landing], tasks: [taskAwaitingApproval(of: revision)],
                      librarySaves: { saved = $0 })
        await s.hydrate(companyId: "u")

        await s.approveTask(id: "t2")

        XCTAssertEqual(s.company.library.map(\.id), ["L1"], "the revision was filed as a second item")
        XCTAssertEqual(s.company.library.first?.body, "# v2")
        XCTAssertEqual(s.company.library.first?.versions?.map(\.body), ["# v1"])
        XCTAssertEqual(saved?.map(\.id), ["L1"], "what was persisted must be the replaced library")
    }

    func testApprovingAFirstPassStillAppends() async {
        let first = Deliverable(id: "D1", kind: .doc, title: "Pricing", body: "p", sourceTaskId: "t2")
        let s = store(library: [landing], tasks: [taskAwaitingApproval(of: first)])
        await s.hydrate(companyId: "u")

        await s.approveTask(id: "t2")

        XCTAssertEqual(s.company.library.map(\.id), ["L1", "D1"])
    }
}

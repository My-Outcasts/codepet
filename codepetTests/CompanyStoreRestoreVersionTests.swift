// codepetTests/CompanyStoreRestoreVersionTests.swift
import XCTest
@testable import codepet

/// Restore from the Library's version menu makes an earlier version current and SAVES that
/// library. Replace-in-place, so the item keeps its id and the Library keeps its count.
@MainActor
final class CompanyStoreRestoreVersionTests: XCTestCase {

    private let item = Deliverable(
        id: "L1", kind: .doc, title: "Brand v2", body: "# two", createdAt: "2026-09-25T03:27:00Z",
        sourceTaskId: "t1",
        versions: [DeliverableVersion(title: "Brand v1", body: "# one", createdAt: "2026-09-24T04:06:00Z",
                                      kind: .doc, payload: nil)])

    private func store(saves: @escaping ([Deliverable]) -> Void) -> CompanyStore {
        CompanyStore(
            loader: { _ in
                CompanyState(brief: CompanyBrief(), departments: [], library: [self.item], stage: .idea,
                             companionId: "byte", onboardedAt: Date(), tasks: [])
            },
            saver: { _, _ in true },
            tasksSaver: { _, _ in true },
            chatSender: { _ in nil },
            chatStreamer: { _ in AsyncThrowingStream { $0.finish(throwing: CompanyChatStreamError.notSignedIn) } },
            taskRunner: { _ in nil },
            librarySaver: { _, lib in saves(lib); return true },
            firstApprovalSaver: { _, _ in true },
            decisionExtractor: { _, _ in [] })
    }

    func testRestoringMakesTheOlderVersionCurrentAndSavesIt() async {
        var saved: [Deliverable]?
        let s = store(saves: { saved = $0 })
        await s.hydrate(companyId: "u")

        await s.restoreVersion(itemId: "L1", historyIndex: 0)

        XCTAssertEqual(s.company.library.map(\.id), ["L1"])
        XCTAssertEqual(s.company.library.first?.body, "# one")
        XCTAssertEqual(s.company.library.first?.versions?.map(\.body), ["# two"],
                       "the version it replaced must be kept, so a restore can be undone")
        XCTAssertEqual(saved?.first?.body, "# one", "the restore must be persisted")
    }

    func testRestoringSomethingThatIsNotThereSavesNothing() async {
        var saves = 0
        let s = store(saves: { _ in saves += 1 })
        await s.hydrate(companyId: "u")

        await s.restoreVersion(itemId: "nope", historyIndex: 0)
        await s.restoreVersion(itemId: "L1", historyIndex: 5)

        XCTAssertEqual(saves, 0)
        XCTAssertEqual(s.company.library.first?.body, "# two")
    }
}

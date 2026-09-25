// codepetTests/LibraryFilingTests.swift
import XCTest
@testable import codepet

/// Filing an approved deliverable into the Library: append a first pass, REPLACE IN PLACE a
/// revision (CP-025).
///
/// The bug these guard: every Approve appended, so ten revisions of one landing page became ten
/// Library items. `LibraryFiling` is pure so the rule can be pinned here without a store; the
/// store's `fileApproval` is the only caller.
final class LibraryFilingTests: XCTestCase {

    private let pricing = Deliverable(id: "L0", kind: .doc, title: "Pricing", body: "p")

    private let landingV1 = Deliverable(
        id: "L1", kind: .site, title: "Landing v1", body: "# v1",
        createdAt: "2026-09-24T10:00:00Z", sourceTaskId: "t1",
        payload: DeliverablePayload(call: "v1 call"))

    private func revision(of id: String?, title: String = "Landing v2", body: String = "# v2",
                          at createdAt: String = "2026-09-24T11:00:00Z") -> Deliverable {
        Deliverable(id: "D9", kind: .site, title: title, body: body, createdAt: createdAt,
                    sourceTaskId: "t1", payload: DeliverablePayload(call: "\(title) call"),
                    supersedes: id)
    }

    private func snapshot(of d: Deliverable) -> DeliverableVersion {
        DeliverableVersion(title: d.title, body: d.body, createdAt: d.createdAt,
                           kind: d.kind, payload: d.payload)
    }

    // MARK: - Spec test 1: a revision replaces the item it supersedes

    func testARevisionReplacesTheItemInPlaceInsteadOfAddingOne() {
        let out = LibraryFiling.file(revision(of: "L1"), into: [pricing, landingV1])

        XCTAssertEqual(out.map(\.id), ["L0", "L1"], "a revision must not add an item or reorder")
        let item = out[1]
        XCTAssertEqual(item.title, "Landing v2")
        XCTAssertEqual(item.body, "# v2")
        XCTAssertEqual(item.createdAt, "2026-09-24T11:00:00Z")
        XCTAssertEqual(item.payload, DeliverablePayload(call: "Landing v2 call"),
                       "a Site draws its payload, not its body; keeping the old one shows v1")
        XCTAssertEqual(item.sourceTaskId, "t1")
        XCTAssertNil(item.supersedes, "the filed item IS the item; it supersedes nothing")
        XCTAssertEqual(out[0], pricing, "an unrelated item was touched")
    }

    func testTheReplacedVersionIsKeptInHistory() {
        let out = LibraryFiling.file(revision(of: "L1"), into: [landingV1])
        XCTAssertEqual(out[0].versions, [snapshot(of: landingV1)])
    }

    func testHistoryIsNewestFirstAcrossTwoRevisions() {
        let once = LibraryFiling.file(revision(of: "L1"), into: [landingV1])
        let twice = LibraryFiling.file(
            revision(of: "L1", title: "Landing v3", body: "# v3", at: "2026-09-24T12:00:00Z"),
            into: once)

        XCTAssertEqual(twice.count, 1)
        XCTAssertEqual(twice[0].body, "# v3")
        XCTAssertEqual(twice[0].versions?.map(\.body), ["# v2", "# v1"])
    }

    // MARK: - Spec test 2: the superseded item is gone → never drop the approval

    func testARevisionOfAMissingItemIsAppendedRatherThanLost() {
        let out = LibraryFiling.file(revision(of: "deleted-meanwhile"), into: [pricing])

        XCTAssertEqual(out.map(\.id), ["L0", "D9"])
        XCTAssertNil(out[1].supersedes, "a dangling link would point at nothing forever")
    }

    // MARK: - Spec test 3: a first pass is today's behaviour, unchanged

    func testAFirstPassIsAppendedExactlyAsBefore() {
        let first = Deliverable(id: "D1", kind: .doc, title: "New", body: "n")
        XCTAssertEqual(LibraryFiling.file(first, into: [pricing]), [pricing, first])
    }

    // MARK: - Spec test 4: history is capped, oldest dropped

    func testHistoryKeepsTwentyVersionsAndDropsTheOldest() {
        var full = landingV1
        full.versions = (0..<20).map { i in
            DeliverableVersion(title: "v\(19 - i)", body: "b\(19 - i)", createdAt: nil,
                               kind: .site, payload: nil)
        }   // newest first: v19 … v0

        let out = LibraryFiling.file(revision(of: "L1"), into: [full])
        let titles = out[0].versions?.map(\.title) ?? []

        XCTAssertEqual(titles.count, 20)
        XCTAssertEqual(titles.first, "Landing v1", "the version just replaced must be kept")
        XCTAssertEqual(titles.last, "v1")
        XCTAssertFalse(titles.contains("v0"), "the oldest should have been dropped")
    }

    // MARK: - Spec test 6: restore is itself a replace-in-place

    func testRestoringAVersionMakesItCurrentAndKeepsTheOneItReplaced() {
        let revised = LibraryFiling.file(revision(of: "L1"), into: [pricing, landingV1])
        let out = LibraryFiling.restore(versionAt: 0, of: "L1", in: revised,
                                        now: "2026-09-24T13:00:00Z")

        XCTAssertEqual(out.map(\.id), ["L0", "L1"])
        let item = out[1]
        XCTAssertEqual(item.body, "# v1")
        XCTAssertEqual(item.title, "Landing v1")
        XCTAssertEqual(item.payload, DeliverablePayload(call: "v1 call"),
                       "restoring text without the payload would still draw v2's Site")
        XCTAssertEqual(item.createdAt, "2026-09-24T13:00:00Z")
        XCTAssertEqual(item.versions?.map(\.body), ["# v2"],
                       "restore must keep the version it replaced, and not keep v1 twice")
    }

    func testRestoringAVersionThatDoesNotExistChangesNothing() {
        let revised = LibraryFiling.file(revision(of: "L1"), into: [landingV1])
        XCTAssertEqual(LibraryFiling.restore(versionAt: 5, of: "L1", in: revised, now: "x"), revised)
        XCTAssertEqual(LibraryFiling.restore(versionAt: 0, of: "nope", in: revised, now: "x"), revised)
    }
}

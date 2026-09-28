// codepetTests/LibraryVersionsTests.swift
import XCTest
@testable import codepet

/// The Library's version history UI (CP-025 follow-up, design option A: a "v3 ▾" menu in the
/// detail header, preview in place, Restore). The decisions live in `LibraryVersions` so they are
/// pinned here without rendering a view.
final class LibraryVersionsTests: XCTestCase {

    private func v(_ title: String, _ body: String, _ at: String?) -> DeliverableVersion {
        DeliverableVersion(title: title, body: body, createdAt: at, kind: .doc,
                           payload: DeliverablePayload(call: "\(title) call"))
    }

    /// Current v3; history newest first: v2, v1.
    private var item: Deliverable {
        Deliverable(id: "L1", kind: .doc, title: "Brand v3", body: "# three",
                    createdAt: "2026-09-25T05:13:00Z", sourceTaskId: "t1",
                    payload: DeliverablePayload(call: "Brand v3 call"),
                    versions: [v("Brand v2", "# two", "2026-09-25T03:27:00Z"),
                               v("Brand v1", "# one", "2026-09-24T04:06:00Z")])
    }

    private let never = Deliverable(id: "L2", kind: .doc, title: "Pricing", body: "p")

    // MARK: - The card badge

    func testAnItemNeverRevisedShowsNoBadge() {
        XCTAssertNil(LibraryVersions.badge(for: never))
    }

    func testTheBadgeCountsTheCurrentVersionToo() {
        XCTAssertEqual(LibraryVersions.badge(for: item), "V3")
        var once = never
        once.versions = [v("Pricing v1", "p0", nil)]
        XCTAssertEqual(LibraryVersions.badge(for: once), "V2")
    }

    // MARK: - The menu

    func testTheMenuListsCurrentFirstThenOlderNewestFirst() {
        let entries = LibraryVersions.entries(for: item)
        XCTAssertEqual(entries.map(\.number), [3, 2, 1])
        XCTAssertEqual(entries.map(\.isCurrent), [true, false, false])
        XCTAssertEqual(entries.map(\.historyIndex), [nil, 0, 1],
                       "an older entry must point at its index in `versions`, which Restore takes")
    }

    func testAnItemNeverRevisedHasNoMenu() {
        XCTAssertTrue(LibraryVersions.entries(for: never).isEmpty,
                      "a one-version menu would be a control with nothing to choose")
    }

    // MARK: - Previewing an older version

    func testPreviewingAVersionShowsItsOwnTitleBodyAndPayload() {
        let shown = LibraryVersions.preview(of: item, historyIndex: 1)
        XCTAssertEqual(shown.id, "L1")
        XCTAssertEqual(shown.title, "Brand v1")
        XCTAssertEqual(shown.body, "# one")
        XCTAssertEqual(shown.payload, DeliverablePayload(call: "Brand v1 call"),
                       "a Site or sheet is drawn from its payload, so the preview must use v1's")
    }

    func testPreviewingAnIndexThatDoesNotExistShowsTheCurrentVersion() {
        XCTAssertEqual(LibraryVersions.preview(of: item, historyIndex: 9), item)
    }

    // MARK: - Dates in the menu

    func testDatesReadAsDayMonthTime() {
        let utc = TimeZone(identifier: "UTC")!
        XCTAssertEqual(LibraryVersions.dateLabel("2026-09-24T04:06:00Z", timeZone: utc), "24 Sep 04:06")
        XCTAssertEqual(LibraryVersions.dateLabel(nil, timeZone: utc), "")
        XCTAssertEqual(LibraryVersions.dateLabel("not a date", timeZone: utc), "")
    }
}

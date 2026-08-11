// codepetTests/LibraryFixturesTests.swift
import XCTest
@testable import codepet

/// `LibraryFixtures` decodes its payloads from the flat wire JSON and `fatalError`s on a
/// malformed one — which would otherwise surface as a crash on launch, during the audit the
/// fixtures exist to support. These assert the decode instead, so a broken fixture is a red test
/// rather than a dead app.
///
/// They also pin each fixture to the payload slice its VIEWER reads. `DeliverablePayload` decodes
/// fail-open: an unrecognised or mis-shaped payload yields nil fields rather than throwing, so a
/// fixture with a typo would decode "successfully" into an empty payload, fall through
/// `DeliverableBodyView`'s `where` guards to the markdown fallback, and look exactly like a
/// viewer regression to whoever was auditing.
final class LibraryFixturesTests: XCTestCase {

    func testEveryFixtureBuildsWithoutTrapping() {
        XCTAssertEqual(LibraryFixtures.all.count, 12)
    }

    /// Every kind that reaches a viewer of its own must be seeded, or the harness silently fails
    /// to cover it — which is exactly what happened first time round: `.email` and `.dms` were
    /// omitted, and `.dms` is the one viewer that overrides the no-card-in-a-sheet rule.
    ///
    /// `.other` is the single allowed omission: it shares `DeliverableBodyView`'s `default`
    /// branch with `.text`, so it would be a duplicate row rather than new coverage.
    func testEveryKindWithItsOwnViewerIsSeeded() {
        let seeded = Set(LibraryFixtures.all.map(\.kind))
        let missing = DeliverableKind.allCases.filter { $0 != .other && !seeded.contains($0) }
        XCTAssertTrue(missing.isEmpty,
                      "not seeded, so unauditable: \(missing.map(\.rawValue).joined(separator: ", "))")
    }

    /// `.dms` renders one card per recipient, and the question its fixture exists to answer is
    /// whether several read as separate objects. One message would not ask it.
    func testTheDmsFixtureHasEnoughRecipientsToJudgeSeparation() {
        let messages = LibraryFixtures.all.first { $0.kind == .dms }?.payload?.messages
        XCTAssertGreaterThanOrEqual(messages?.count ?? 0, 2)
    }

    func testIdsAreUniqueAndPrefixed() {
        let ids = LibraryFixtures.all.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count, "fixture ids collide — the Library would drop rows")
        for id in ids {
            XCTAssertTrue(id.hasPrefix(LibraryFixtures.idPrefix),
                          "\(id) is not identifiable as seeded")
        }
    }

    /// Distinct timestamps: the Library sorts newest-first on `createdAt`, and equal stamps make
    /// the row order arbitrary between launches.
    func testTimestampsAreDistinct() {
        let stamps = LibraryFixtures.all.compactMap(\.createdAt)
        XCTAssertEqual(stamps.count, LibraryFixtures.all.count)
        XCTAssertEqual(Set(stamps).count, LibraryFixtures.all.count,
                       "two fixtures share a timestamp — the Library sorts on it, so their order "
                       + "would shuffle between launches")
    }

    /// The important one. Each structured kind must carry the slice its viewer switches on,
    /// otherwise it silently renders as markdown.
    func testStructuredKindsCarryTheSliceTheirViewerReads() {
        func fixture(_ kind: DeliverableKind) -> Deliverable {
            guard let d = LibraryFixtures.all.first(where: { $0.kind == kind }) else {
                XCTFail("no fixture for \(kind.rawValue)")
                return Deliverable(kind: .other, title: "", body: "")
            }
            return d
        }

        XCTAssertFalse(fixture(.doc).payload?.call?.isEmpty ?? true)
        XCTAssertFalse(fixture(.doc).payload?.sections?.isEmpty ?? true)
        XCTAssertFalse(fixture(.plan).payload?.goal?.isEmpty ?? true)
        XCTAssertFalse(fixture(.plan).payload?.steps?.isEmpty ?? true)
        XCTAssertFalse(fixture(.checklist).payload?.items?.isEmpty ?? true)
        XCTAssertNotNil(fixture(.calendar).payload?.calendar)
        XCTAssertNotNil(fixture(.sheet).payload?.sheet)
        XCTAssertNotNil(fixture(.site).payload?.site)
        XCTAssertNotNil(fixture(.screens).payload?.screens)
    }

    /// `.calendar`, `.site` and `.screens` share flat keys with other kinds (`steps` is both
    /// `[String]` on a plan and `[{h,p}]` on a site). Confirm the sub-payloads actually populated
    /// rather than decoding to an empty shell.
    func testSubPayloadsAreNotEmptyShells() {
        let all = LibraryFixtures.all
        let calendar = all.first { $0.kind == .calendar }?.payload?.calendar
        XCTAssertEqual(calendar?.weeks.count, 2)
        XCTAssertFalse(calendar?.weeks.first?.items.isEmpty ?? true)

        let screens = all.first { $0.kind == .screens }?.payload?.screens
        XCTAssertEqual(screens?.screens.count, 3)
        XCTAssertFalse(screens?.screens.first?.title.isEmpty ?? true)

        let site = all.first { $0.kind == .site }?.payload?.site
        XCTAssertFalse(site?.headline.isEmpty ?? true)
        XCTAssertFalse(site?.steps.isEmpty ?? true)

        let sheet = all.first { $0.kind == .sheet }?.payload?.sheet
        XCTAssertNotNil(sheet)
        // A degenerate range would crash SwiftUI's Slider — SheetViewer guards it, but a fixture
        // should not be the thing exercising that guard.
        XCTAssertLessThan(sheet!.price.min, sheet!.price.max)
        XCTAssertLessThan(sheet!.churn.min, sheet!.churn.max)
    }

    /// The payload-less kinds must NOT carry one — `.post` and `.legal` render `title` + `body`,
    /// and `.text` is the fallback branch. A stray payload would route them somewhere else.
    func testPayloadLessKindsCarryBodyOnly() {
        for kind in [DeliverableKind.post, .legal, .text] {
            let d = LibraryFixtures.all.first { $0.kind == kind }
            XCTAssertNotNil(d, "no fixture for \(kind.rawValue)")
            XCTAssertNil(d?.payload, "\(kind.rawValue) should have no structured payload")
            XCTAssertFalse(d?.body.isEmpty ?? true)
        }
    }

    /// Blanks are what the footer counts. If no fixture carried one, an audit would never see
    /// the tinting or the "fill in N blanks" line that this whole pass added.
    func testSomeFixturesCarryBlanksToExerciseTheFooter() {
        let withBlanks = LibraryFixtures.all.filter {
            !MessagePlaceholders.labels(in: $0.body).isEmpty
        }
        XCTAssertFalse(withBlanks.isEmpty,
                       "no fixture has a [blank] — the blanks footer and tint go unaudited")
    }
}

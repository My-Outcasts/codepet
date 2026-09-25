// codepetTests/DeliverableVersioningTests.swift
import XCTest
@testable import codepet

/// A revision of approved work must update the Library item it revises, not file a new one.
///
/// Found 24 Sep on prod build 3: redesigning the landing page and then revising it left three
/// landing-page tasks on the Roadmap and four near-identical landing-page Sites in the Library,
/// because `fileApproval` always appends and a `Deliverable` had no idea of being a newer version
/// of another. Spec: docs/superpowers/specs/2026-09-24-revision-versioning-design.md (CP-025).
///
/// These cover the model the fix rests on: two optional fields, `supersedes` (on a draft, the
/// Library item it will replace) and `versions` (on a Library item, its earlier bodies).
final class DeliverableVersioningTests: XCTestCase {

    /// Every deliverable already stored has neither field. If adding them broke decoding, every
    /// founder's Library would fail to load — so an old document must decode, with both nil.
    func testAnExistingDeliverableWithNeitherFieldStillDecodes() throws {
        let stored = ##"{"id":"d1","kind":"site","title":"Landing page","body":"# v1"}"##
        let d = try JSONDecoder().decode(Deliverable.self, from: Data(stored.utf8))

        XCTAssertEqual(d.id, "d1")
        XCTAssertNil(d.supersedes)
        XCTAssertNil(d.versions)
    }

    /// Both fields must survive the REAL save path. `Deliverable` has a hand-written encoder, so a
    /// field added to the struct but not to `encode(to:)` compiles fine and is silently dropped on
    /// every save — the history would exist in memory and vanish on the next launch.
    func testSupersedesAndVersionsSurviveTheLibrarySavePayload() throws {
        let earlier = DeliverableVersion(title: "Landing page", body: "# v1",
                                         createdAt: "2026-09-24T10:00:00Z")
        let d = Deliverable(id: "d1", kind: .site, title: "Landing page — second pass",
                            body: "# v2", createdAt: "2026-09-24T11:00:00Z",
                            supersedes: "d0", versions: [earlier])

        let payload = CompanyData.deliverablesPayload([d])
        let rows = try XCTUnwrap(payload["library"] as? [[String: Any]])
        let data = try JSONSerialization.data(withJSONObject: rows)
        let back = try JSONDecoder().decode([Deliverable].self, from: data)

        XCTAssertEqual(back.first?.supersedes, "d0")
        XCTAssertEqual(back.first?.versions, [earlier])
    }
}

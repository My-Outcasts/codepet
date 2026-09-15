import XCTest
@testable import codepet

/// **Three problems with three fixes must not share one sentence.** "Codepet can't reach its
/// local runner" was the only copy the old `.localUnavailable(String)` carried, and it was
/// shown for a missing grant, a missing CLI and a missing sidecar alike — a founder told to
/// check the wrong thing three times.
final class BlockReasonTests: XCTestCase {

    func testEveryReasonHasItsOwnWords() {
        let all: [BlockReason] = [.notGranted, .claudeCodeMissing, .sidecarMissing, .noFolderLinked]
        let texts = Set(all.map(\.founderText))
        XCTAssertEqual(texts.count, all.count, "two reasons share a sentence")
        for r in all {
            XCTAssertFalse(r.founderText.isEmpty)
            XCTAssertFalse(r.founderTextVi.isEmpty, "\(r) has no Vietnamese copy")
            XCTAssertNotEqual(r.founderText, r.founderTextVi,
                              "\(r) has the English copy in its Vietnamese slot")
        }
    }

    /// The copy names the fix, not the internal state. "not authorised" is our word for it.
    func testTheCopyNamesAnActionTheFounderCanTake() {
        XCTAssertTrue(BlockReason.claudeCodeMissing.founderText.contains("install"))
        XCTAssertTrue(BlockReason.noFolderLinked.founderText.contains("folder"))
    }
}

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
        // Case-insensitive on purpose. The first version of this assertion was
        // `contains("install")` against copy that reads "Install it, then try again." — so the
        // test failed and the copy was lowercased to satisfy it, shipping a sentence that
        // began with a small letter. The assertion is about the WORD being there, not its case.
        XCTAssertTrue(BlockReason.claudeCodeMissing.founderText.lowercased().contains("install"))
        XCTAssertTrue(BlockReason.noFolderLinked.founderText.lowercased().contains("folder"))
        // `sidecarMissing` is the one that read as a bare statement of fact — true, and
        // useless to the founder, who cannot run the build script that produces the bundle.
        // What she can do is reinstall, so the copy has to say so.
        XCTAssertTrue(BlockReason.sidecarMissing.founderText.lowercased().contains("reinstall"))
    }
}

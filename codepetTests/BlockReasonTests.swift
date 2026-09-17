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

    /// The grant a Codex-only founder is asked for must be the Codex one. Naming Claude
    /// here is the specific wrong answer: she has a plan, just not that one.
    func testTheCodexBlockAsksForTheCodexGrant() {
        let reason = BlockReason.notGrantedFor(.codex)
        XCTAssertTrue(reason.founderText.lowercased().contains("chatgpt"),
                      "expected the ChatGPT plan named, got: \(reason.founderText)")
        XCTAssertFalse(reason.founderText.lowercased().contains("claude"),
                       "must not name Claude to a Codex founder: \(reason.founderText)")
    }

    func testTheClaudeBlockStillAsksForTheClaudeGrant() {
        let reason = BlockReason.notGrantedFor(.claudeCode)
        XCTAssertTrue(reason.founderText.lowercased().contains("claude"))
    }

    /// Chat and meetings are Claude-only. The copy must name a REAL action — `resolve` only
    /// ever returns this reason when Claude Code is not installed, so "install" is the one
    /// true move. It must NOT point at a company-level provider switch: no such control
    /// exists anywhere in this app, so "switch" passing here is exactly what let a founder go
    /// hunting Settings for a button that was never built.
    func testNeedsClaudeCodeNamesARealAction() {
        let text = BlockReason.needsClaudeCode.founderText.lowercased()
        XCTAssertTrue(text.contains("install"),
                      "expected an install instruction, got: \(BlockReason.needsClaudeCode.founderText)")
        XCTAssertFalse(text.contains("switch"),
                       "must not point at a company-level provider switch, which does not exist: "
                       + BlockReason.needsClaudeCode.founderText)
    }

    /// Every case carries both languages. A missing Vietnamese string renders English to a
    /// Vietnamese founder, which reads as a bug rather than a fallback.
    func testEveryNewCaseHasVietnamese() {
        for reason in [BlockReason.notGrantedFor(.codex),
                       .notGrantedFor(.claudeCode),
                       .needsClaudeCode] {
            XCTAssertFalse(reason.founderTextVi.isEmpty)
            XCTAssertNotEqual(reason.founderTextVi, reason.founderText)
        }
    }
}

// codepetTests/GrantRevokeConfirmTests.swift
import XCTest
@testable import codepet

/// Turning the Claude grant off stops the product. While the copy promised a fallback that
/// was a one-click accident waiting to happen; with the copy fixed (see `GrantCopyTests`) it
/// is still worth one question, because the consequence is total.
///
/// Revocation stays fully possible — consent that cannot be withdrawn is not consent. This
/// only stops it happening unintentionally.
final class GrantRevokeConfirmTests: XCTestCase {

    /// Claude off = nothing runs. `ChatTransportRouter.transport` blocks on the grant, and
    /// `LocalTransportRouter.chooseProvider` has no other provider to fall through to.
    func testClaudeNeedsAConfirm() {
        XCTAssertTrue(GrantCopy.needsRevokeConfirm(.claudeCode))
    }

    /// Codex off is not a kill switch: the one-shot ops fall through to Claude. A confirm
    /// here would be ceremony for a consequence that does not occur.
    func testCodexDoesNotNeedAConfirm() {
        XCTAssertFalse(GrantCopy.needsRevokeConfirm(.codex))
    }

    /// The guard: if someone makes the confirm unconditional, this goes red.
    func testTheConfirmIsNotUnconditional() {
        let needing = AIProvider.allCases.filter(GrantCopy.needsRevokeConfirm)
        XCTAssertEqual(needing, [.claudeCode])
    }

    func testTheBodyNamesTheConsequenceAndTheTerminal() {
        let body = GrantCopy.revokeBody(lang: .en)
        XCTAssertTrue(body.contains("stops working until you turn this back on"))
        XCTAssertTrue(body.contains("terminal's Claude Code is unaffected"))
    }

    func testBothLanguagesArePresent() {
        XCTAssertFalse(GrantCopy.revokeTitle(lang: .vi).isEmpty)
        XCTAssertNotEqual(GrantCopy.revokeBody(lang: .en), GrantCopy.revokeBody(lang: .vi))
        XCTAssertNotEqual(GrantCopy.revokeTitle(lang: .en), GrantCopy.revokeTitle(lang: .vi))
        XCTAssertNotEqual(GrantCopy.revokeConfirm(lang: .en), GrantCopy.revokeConfirm(lang: .vi))
        XCTAssertNotEqual(GrantCopy.revokeCancel(lang: .en), GrantCopy.revokeCancel(lang: .vi))
    }
}

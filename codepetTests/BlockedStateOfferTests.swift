import XCTest
@testable import codepet

/// `BlockedOffer.resolve` is a pure function — no store, no view, no SwiftUI — so there is no
/// excuse for an inert assertion here (landmine 3 in CLAUDE.md: the XCTest host crashes when a
/// `@MainActor ObservableObject` deallocates, which is exactly why this stays a plain static).
final class BlockedStateOfferTests: XCTestCase {

    /// A Codex-only founder is asked for the grant she can actually give.
    func testTheOfferNamesTheInstalledProvider() {
        let offer = BlockedOffer.resolve(reason: .notGranted, installed: [.codex])
        XCTAssertEqual(offer, .grant(.codex))
        XCTAssertTrue(offer.founderText(lang: .en).lowercased().contains("chatgpt"))
    }

    /// Claude wins the tie here for the same reason it wins in `chooseProvider` — one
    /// precedence, not two that can disagree.
    func testClaudeIsOfferedWhenBothAreInstalled() {
        XCTAssertEqual(BlockedOffer.resolve(reason: .notGranted, installed: [.claudeCode, .codex]),
                       .grant(.claudeCode))
    }

    /// Nothing installed means there is no grant to offer. Telling a founder to authorise
    /// software she does not have is an instruction nobody can follow — the same reasoning
    /// that puts `notAuthorised` last in `CLIStatus.Blocker`.
    func testNothingInstalledOffersInstallNotAGrant() {
        XCTAssertEqual(BlockedOffer.resolve(reason: .notGranted, installed: []), .install)
    }

    /// Only the not-granted block becomes an offer. A missing sidecar is a build problem and
    /// no grant fixes it — offering one there would be a button that cannot work.
    func testOtherBlockReasonsAreLeftAlone() {
        XCTAssertEqual(BlockedOffer.resolve(reason: .sidecarMissing, installed: [.codex]),
                       .explain(.sidecarMissing))
    }

    /// Chat and meetings run on Claude and nothing else. A founder with only Codex installed
    /// needs to be told THAT, not sent to grant a plan she does not have.
    func testAClaudeOnlySurfaceTellsACodexFounderWhatItNeeds() {
        let offer = BlockedOffer.resolve(reason: .notGranted,
                                         installed: [.codex],
                                         surface: .claudeOnly)
        XCTAssertEqual(offer, .explain(.needsClaudeCode))
    }

    /// The same surface for a founder who HAS Claude installed but has not granted it is an
    /// ordinary consent problem, not a missing-product problem.
    func testAClaudeOnlySurfaceStillOffersTheGrantWhenClaudeIsInstalled() {
        let offer = BlockedOffer.resolve(reason: .notGranted,
                                         installed: [.claudeCode],
                                         surface: .claudeOnly)
        XCTAssertEqual(offer, .grant(.claudeCode))
    }

    /// Nothing installed on a Claude-only surface is still a "you need Claude Code" story,
    /// not an "install something" story with no name attached — covers the branch the two
    /// tests above don't exercise together (claudeOnly AND empty).
    func testAClaudeOnlySurfaceWithNothingInstalledNamesClaudeCode() {
        let offer = BlockedOffer.resolve(reason: .notGranted, installed: [], surface: .claudeOnly)
        XCTAssertEqual(offer, .explain(.needsClaudeCode))
    }

    /// `.install`'s copy must actually tell the founder to install something — this is the
    /// one case whose text is NOT drawn from the reason it wraps, so it needs its own check.
    func testInstallOfferNamesInstalling() {
        let text = BlockedOffer.install.founderText(lang: .en).lowercased()
        XCTAssertTrue(text.contains("install"), "expected an install instruction, got: \(text)")
    }

    /// Every offer has to speak Vietnamese too — this is founder-facing copy, not a debug log.
    func testEveryOfferHasVietnamese() {
        let offers: [BlockedOffer] = [.grant(.codex), .grant(.claudeCode), .install,
                                       .explain(.sidecarMissing), .explain(.needsClaudeCode)]
        for offer in offers {
            let en = offer.founderText(lang: .en)
            let vi = offer.founderText(lang: .vi)
            XCTAssertFalse(vi.isEmpty, "\(offer) has no Vietnamese copy")
            XCTAssertNotEqual(en, vi, "\(offer) has the English copy in its Vietnamese slot")
        }
    }
}

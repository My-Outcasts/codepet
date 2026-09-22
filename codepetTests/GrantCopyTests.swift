// codepetTests/GrantCopyTests.swift
import XCTest
@testable import codepet

/// The copy said "turn it off and Codepet goes back to the old route". There is no old
/// route: `ChatTransportRouter` and `LocalTransportRouter` both document that they have no
/// hosted case, and `CloudAIBlock.blockedPaths` refuses the endpoints outright. So the
/// toggle is the product's on/off switch, described as a preference — and a founder who
/// read it as optional declined it and landed in an app where nothing worked.
///
/// The Codex row had a second, different defect: it claimed chat and the department room,
/// which are `.claudeOnly` and have never run on Codex.
final class GrantCopyTests: XCTestCase {

    // MARK: - The retired lie

    /// The guard. Delete the rewrite and this goes red.
    func testNoProviderPromisesAFallbackRoute() {
        for provider in AIProvider.allCases {
            for lang in [AppLanguage.en, .vi] {
                let copy = GrantCopy.description(for: provider, lang: lang)
                XCTAssertFalse(copy.lowercased().contains("old route"),
                               "\(provider) \(lang) still promises a route that was deleted")
                XCTAssertFalse(copy.contains("đường cũ"),
                               "\(provider) \(lang) still promises a route that was deleted")
            }
        }
    }

    // MARK: - Claude: the kill switch says so

    func testClaudeSaysCodepetStopsWithoutIt() {
        let copy = GrantCopy.description(for: .claudeCode, lang: .en)
        XCTAssertTrue(copy.contains("Codepet needs this to work"))
        XCTAssertTrue(copy.contains("stops until you turn it back on"))
    }

    /// Benefit before cost: the founder learns what she gets before what it spends.
    func testClaudeLeadsWithTheBenefitNotTheCost() {
        let copy = GrantCopy.description(for: .claudeCode, lang: .en)
        let benefit = copy.range(of: "your own Claude plan")
        let cost = copy.range(of: "spends your Claude quota")
        XCTAssertNotNil(benefit); XCTAssertNotNil(cost)
        XCTAssertTrue(benefit!.lowerBound < cost!.lowerBound,
                      "cost is stated before the benefit it pays for")
    }

    func testClaudeKeepsTheTerminalReassurance() {
        XCTAssertTrue(GrantCopy.description(for: .claudeCode, lang: .en)
            .contains("terminal's Claude Code is unaffected"))
    }

    // MARK: - Codex: a different scope and a different off-state

    /// `BlockedOffer.Surface.claudeOnly` — chat streaming and the virtual company meeting
    /// run on Claude or nothing. Naming them here promised work Codex cannot do.
    func testCodexClaimsNoClaudeOnlySurface() {
        for lang in [AppLanguage.en, .vi] {
            let copy = GrantCopy.description(for: .codex, lang: lang).lowercased()
            XCTAssertFalse(copy.contains("chat"), "Codex copy still claims chat")
            XCTAssertFalse(copy.contains("department room"))
            XCTAssertFalse(copy.contains("phòng họp"))
        }
    }

    /// Codex off is not a kill switch: `LocalTransportRouter.chooseProvider` falls through
    /// Claude → Codex, so the one-shot work goes back to Claude when Claude is granted.
    func testCodexOffStateNamesTheClaudeFallback() {
        let copy = GrantCopy.description(for: .codex, lang: .en)
        XCTAssertTrue(copy.contains("goes back to Claude"))
        XCTAssertFalse(copy.contains("Codepet needs this to work"),
                       "Codex is not the kill switch; Claude is")
    }

    // MARK: - Both languages are real

    func testEveryProviderHasDistinctVietnamese() {
        for provider in AIProvider.allCases {
            let en = GrantCopy.description(for: provider, lang: .en)
            let vi = GrantCopy.description(for: provider, lang: .vi)
            XCTAssertFalse(vi.isEmpty)
            XCTAssertNotEqual(en, vi, "\(provider) has untranslated Vietnamese")
        }
    }
}

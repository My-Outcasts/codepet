// codepetTests/DeveloperPaneCopyTests.swift
import XCTest
@testable import codepet

/// The CODE tab's idle words. Found testing as a non-technical founder (5 Oct): a literal
/// "*is*" (asterisks — `hint` renders a plain String, not markdown), a pane called
/// "Developer" under a tab labelled CODE, a green "0 credits" that read as "you're out", and
/// a "NEVER, AT ANY TIER" heading naming tiers nothing on screen explains.
final class DeveloperPaneCopyTests: XCTestCase {
    private var all: [String] {
        [AppLanguage.en, .vi].flatMap { l in
            [DeveloperPaneCopy.idleHint(l), DeveloperPaneCopy.backendChip(local: true, l),
             DeveloperPaneCopy.backendChip(local: false, l), DeveloperPaneCopy.neverHeading(l),
             DeveloperPaneCopy.dormantHeading(l), DeveloperPaneCopy.dormantCostTitle(l),
             DeveloperPaneCopy.dormantCost(l)]
        }
    }

    func testNoMarkdownSurvivesIntoPlainText() {
        for s in all { XCTAssertFalse(s.contains("*"), s) }
    }

    func testNoInternalNamesOrTiers() {
        for s in all {
            XCTAssertFalse(s.contains("Developer"), s)
            XCTAssertFalse(s.lowercased().contains("tier"), s)
            XCTAssertFalse(s.contains("MỨC"), s)
        }
    }

    /// "0 credits" in green reads as an empty balance. Say what it runs on instead.
    func testLocalRunSaysWhatItSpends() {
        let en = DeveloperPaneCopy.backendChip(local: true, .en)
        XCTAssertFalse(en.contains("0 credits"), en)
        XCTAssertTrue(en.contains("Claude plan"), en)
        XCTAssertTrue(DeveloperPaneCopy.backendChip(local: true, .vi).contains("gói Claude"))
    }

    /// The idle hint promises a plan before any change — true: `.plan` shows Run / Cancel.
    func testIdleHintPromisesAPlanFirst() {
        XCTAssertTrue(DeveloperPaneCopy.idleHint(.en).contains("plan"))
        XCTAssertTrue(DeveloperPaneCopy.idleHint(.vi).contains("kế hoạch"))
    }

    /// Before a folder is linked the tab still said "0 credits on your own CLI · credits in the
    /// cloud · and the ceiling holds from the first run" (build 8 retest, 6 Oct).
    func testDormantCostSaysWhatEachPathSpends() {
        for l in [AppLanguage.en, .vi] {
            let s = DeveloperPaneCopy.dormantCost(l)
            XCTAssertFalse(s.contains("0 "), s)
            XCTAssertFalse(s.contains("CLI"), s)
            XCTAssertFalse(s.lowercased().contains("ceiling"), s)
            XCTAssertFalse(s.contains("trần"), s)
        }
        XCTAssertTrue(DeveloperPaneCopy.dormantCost(.en).contains("Claude plan"))
        XCTAssertTrue(DeveloperPaneCopy.dormantCost(.vi).contains("gói Claude"))
    }
}

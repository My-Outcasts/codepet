// codepetTests/TeamBuildButtonTests.swift
import XCTest
@testable import codepet

final class TeamBuildButtonTests: XCTestCase {
    func testEnabledOnlyWithADraftWhenIdleAndAvailable() {
        XCTAssertTrue(TeamBuildButton.isEnabled(draft: "pants page", busy: false, available: true))
        XCTAssertFalse(TeamBuildButton.isEnabled(draft: "  ", busy: false, available: true))
        XCTAssertFalse(TeamBuildButton.isEnabled(draft: "pants", busy: true, available: true))
        XCTAssertFalse(TeamBuildButton.isEnabled(draft: "pants", busy: false, available: false))
    }
    func testHelpSaysItRunsOnTheFoundersPlan() {
        XCTAssertTrue(TeamBuildButton.help(.en).localizedCaseInsensitiveContains("Claude plan"))
        XCTAssertTrue(TeamBuildButton.help(.vi).localizedCaseInsensitiveContains("gói Claude"))
    }
    func testStatusCopyIsHonest() {
        XCTAssertEqual(TeamBuildCopy.status(.running, elapsed: 42, lang: .en), "0:42")
        XCTAssertEqual(TeamBuildCopy.status(.failed("Timed out"), elapsed: nil, lang: .en), "Failed")
        XCTAssertEqual(TeamBuildCopy.status(.blocked, elapsed: nil, lang: .vi), "Bị chặn")
        XCTAssertEqual(TeamBuildCopy.waitsFor(["Marketing", "Design"], lang: .en), "waits for Marketing, Design")
    }
}

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
    /// CP-027: the row shown while the router picks the room. It names what is happening in the
    /// founder's words, in both languages, and never claims a department has started. Since the
    /// 6 Oct design pass it is a quiet line with its own pulse and clock, so no trailing ellipsis.
    func testConveningCopyNamesTheWaitInBothLanguages() {
        XCTAssertEqual(TeamBuildCopy.conveningTitle(.en), "Gathering the team")
        XCTAssertEqual(TeamBuildCopy.conveningTitle(.vi), "Đang gọi cả đội")
        XCTAssertEqual(TeamBuildCopy.conveningDetail(.en),
                       "Choosing who should weigh in, usually about a minute")
        XCTAssertEqual(TeamBuildCopy.conveningDetail(.vi),
                       "Đang chọn ai sẽ góp ý, thường khoảng một phút")
    }
}

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

    /// What chat is told when Team build is pressed: the team is meeting and will build it, so the
    /// reply must neither refuse nor turn it into a roadmap offer. Her words ride at the end,
    /// unchanged, the same way `ChatMode.plan` frames a turn.
    func testTheChatFrameSaysTheTeamIsBuildingIt() {
        let en = TeamBuildCopy.chatFrame("a locker booking page", lang: .en)
        XCTAssertTrue(en.hasSuffix("a locker booking page"))
        XCTAssertTrue(en.contains("Team build"))
        XCTAssertTrue(en.contains("do not offer"), "must steer away from add_task offers")
        let vi = TeamBuildCopy.chatFrame("trang đặt tủ", lang: .vi)
        XCTAssertTrue(vi.hasSuffix("trang đặt tủ"))
        XCTAssertNotEqual(vi, en)
    }
}

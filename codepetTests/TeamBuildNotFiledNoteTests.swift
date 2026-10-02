import XCTest
@testable import codepet

/// CP-049, from Dominich's build 6 report (1 Oct): "Not saved yet — approving files it in your
/// Library" still showed on the Team Build card after the founder had already approved a draft.
/// The chat draft card retires that note on the founder's first approval
/// (`DraftCardCopy.shouldShowNotFiledNote`); the Team Build card's ready footer printed it with
/// no condition at all. Approving a Team Build already records the first approval (it files
/// through `fileApproval`), so only the card's rule was missing.
final class TeamBuildNotFiledNoteTests: XCTestCase {
    func testTheNoteShowsBeforeTheFoundersFirstApproval() {
        XCTAssertTrue(TeamBuildCopy.showsNotFiledNote(firstApprovalAt: nil))
    }

    func testTheNoteRetiresOnceTheFounderHasApprovedAnything() {
        XCTAssertFalse(TeamBuildCopy.showsNotFiledNote(firstApprovalAt: Date(timeIntervalSince1970: 1_790_000_000)))
    }

    /// Same answer as the chat draft card for an unapproved draft, so the two cards cannot drift.
    func testItAgreesWithTheChatDraftCard() {
        for approved in [nil, Date()] as [Date?] {
            XCTAssertEqual(TeamBuildCopy.showsNotFiledNote(firstApprovalAt: approved),
                           DraftCardCopy.shouldShowNotFiledNote(hasApproved: approved != nil, draftApproved: false))
        }
    }
}

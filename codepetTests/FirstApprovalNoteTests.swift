// codepetTests/FirstApprovalNoteTests.swift
import XCTest
@testable import codepet

/// Guards on the draft card admitting it is not saved yet.
///
/// The rule "nothing is committed until you approve" is stated BEFORE a run (`BeaconOffer`:
/// "you approve before it is filed") and confirmed AFTER ("Added to Library"). In between, the
/// founder looks at a finished-LOOKING deliverable beside a button marked Approve, with nothing
/// saying it is unsaved. That middle moment is what this note fills.
@MainActor
final class FirstApprovalNoteTests: XCTestCase {

    // MARK: - Task 1: the field and its wire shape

    /// Millis, not ISO — `introSeenAt` next to it is a number and the web reads both.
    func testFirstApprovalPayloadIsEpochMillis() {
        let at = Date(timeIntervalSince1970: 1_700_000_000)
        let payload = CompanyData.firstApprovalPayload(at)
        XCTAssertEqual(payload["firstApprovalAt"] as? Double, 1_700_000_000_000)
    }

    /// **The landmine this file's own comment warns about.** `CompanyState.init(from:)` is
    /// hand-written because Swift's synthesised `Decodable` throws `keyNotFound` rather than
    /// falling back to a declared default. Every company document in Firestore predates this
    /// field, so a required decode would fail to load EVERY existing account.
    func testACompanyDocumentWithoutTheFieldStillDecodes() throws {
        let json = #"{"companionId":"byte","stage":"building"}"#
        let state = try JSONDecoder().decode(CompanyState.self, from: Data(json.utf8))
        XCTAssertNil(state.firstApprovalAt)
        XCTAssertEqual(state.companionId, "byte")
    }

    func testItRoundTripsWhenPresent() throws {
        var state = CompanyState.empty
        state.firstApprovalAt = Date(timeIntervalSince1970: 1_700_000_000)
        let back = try JSONDecoder().decode(
            CompanyState.self, from: try JSONEncoder().encode(state))
        XCTAssertEqual(back.firstApprovalAt?.timeIntervalSince1970, 1_700_000_000)
    }
}

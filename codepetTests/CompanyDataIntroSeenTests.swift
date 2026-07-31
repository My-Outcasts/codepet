import XCTest
@testable import codepet

final class CompanyDataIntroSeenTests: XCTestCase {
    // The web writes companies/{uid}.introSeenAt as MILLIS (schema.ts: `introSeenAt?: Millis`),
    // not an ISO string like onboardedAt — both clients read the same doc, so native must match.
    func testReadsMillisIntoADate() {
        let doc = CompanyDoc(introSeenAt: 1_753_900_000_000)
        let state = CompanyData.state(from: doc)
        XCTAssertEqual(state.introSeenAt?.timeIntervalSince1970 ?? 0, 1_753_900_000, accuracy: 0.001)
    }

    func testMissingFieldMeansNeverSeen() {
        XCTAssertNil(CompanyData.state(from: CompanyDoc()).introSeenAt)
        XCTAssertNil(CompanyData.state(from: nil).introSeenAt)
    }

    func testPayloadIsMillisNumber() {
        let at = Date(timeIntervalSince1970: 1_753_900_000)
        let payload = CompanyData.introSeenPayload(at)
        XCTAssertEqual(payload["introSeenAt"] as? Double, 1_753_900_000_000)
    }
}

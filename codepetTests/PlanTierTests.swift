import XCTest
@testable import codepet

/// The tier used to be resolved server-side by `generatePlan`, which is being deleted. The
/// RevenueCat webhook still writes `entitlements/{uid}`; this reads it.
///
/// **The absent document is the important case.** A founder who has never subscribed has no
/// document at all, and Firestore answers nil rather than `{pro: false}` — reading that as
/// "no answer, assume full" would hand every feature to everyone.
final class PlanTierTests: XCTestCase {

    private func resolver(_ doc: [String: Any]?) -> PlanTierResolver {
        PlanTierResolver(read: { _ in doc })
    }

    func testAProSubscriberGetsFull() async {
        let t = await resolver(["pro": true]).tier(uid: "u1")
        XCTAssertEqual(t, .full)
    }

    func testAnExplicitlyNonProAccountGetsFree() async {
        let t = await resolver(["pro": false]).tier(uid: "u1")
        XCTAssertEqual(t, .free)
    }

    func testAMissingDocumentIsFreeNotFull() async {
        let t = await resolver(nil).tier(uid: "u1")
        XCTAssertEqual(t, .free, "an absent entitlement was read as a subscription")
    }
}

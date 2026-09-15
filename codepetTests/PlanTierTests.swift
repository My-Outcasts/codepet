import XCTest
import FirebaseFirestore
@testable import codepet

/// The tier used to be resolved server-side by `resolvePlanTier` in the (now-deleted)
/// `generatePlan` function. The RevenueCat webhook still writes `entitlements/{uid}`; this
/// reads it, reproducing three behaviors the server had:
///
/// 1. The vocabulary is `preview` / `full` (matching the surviving
///    `functions/src/generatePlanCore.ts`'s `PlanTier`), not `free` / `full`.
/// 2. A subscriber whose `pro_until` has passed is `preview`, even when `pro == true`.
/// 3. `PLAN_GATING_ENABLED` gates the whole check. It shipped `false`, so `resolvePlanTier`
///    always answered `full` — the Firestore read below it never ran in production. The
///    Swift port must default to the same OFF, or this "port" is a product change: gating
///    founders who have always had everything.
///
/// **The absent document is the important case.** A founder who has never subscribed has no
/// document at all, and Firestore answers nil rather than `{pro: false}` — reading that as
/// "no answer, assume full" would hand every feature to everyone. (Only true when gating is on;
/// see the gating-off tests below, which is the case that matches production today.)
final class PlanTierTests: XCTestCase {

    private func resolver(_ doc: [String: Any]?, gatingEnabled: Bool) -> PlanTierResolver {
        PlanTierResolver(gatingEnabled: gatingEnabled, read: { _ in doc })
    }

    private var farFuture: Timestamp { Timestamp(date: Date().addingTimeInterval(60 * 60 * 24 * 365)) }
    private var farPast: Timestamp { Timestamp(date: Date().addingTimeInterval(-60 * 60 * 24)) }

    // MARK: - Gating ON: the behavior `resolvePlanTier`'s Firestore branch actually encoded

    func testGatingOn_lapsedSubscriberIsPreview() async {
        let doc: [String: Any] = ["pro": true, "pro_until": farPast]
        let t = await resolver(doc, gatingEnabled: true).tier(uid: "u1")
        XCTAssertEqual(t, .preview, "pro_until in the past must not still read as full")
    }

    func testGatingOn_currentSubscriberWithFutureExpiryIsFull() async {
        let doc: [String: Any] = ["pro": true, "pro_until": farFuture]
        let t = await resolver(doc, gatingEnabled: true).tier(uid: "u1")
        XCTAssertEqual(t, .full)
    }

    func testGatingOn_currentSubscriberWithNoExpiryIsFull() async {
        let doc: [String: Any] = ["pro": true]
        let t = await resolver(doc, gatingEnabled: true).tier(uid: "u1")
        XCTAssertEqual(t, .full, "an absent pro_until must not be treated as expired")
    }

    func testGatingOn_explicitlyNonProAccountIsPreview() async {
        let t = await resolver(["pro": false], gatingEnabled: true).tier(uid: "u1")
        XCTAssertEqual(t, .preview)
    }

    func testGatingOn_missingDocumentIsPreviewNotFull() async {
        let t = await resolver(nil, gatingEnabled: true).tier(uid: "u1")
        XCTAssertEqual(t, .preview, "an absent entitlement was read as a subscription")
    }

    // MARK: - Gating OFF (the default, matching production): everything is full, unconditionally

    func testGatingOff_lapsedSubscriberIsStillFull() async {
        let doc: [String: Any] = ["pro": true, "pro_until": farPast]
        let t = await resolver(doc, gatingEnabled: false).tier(uid: "u1")
        XCTAssertEqual(t, .full)
    }

    func testGatingOff_currentSubscriberWithFutureExpiryIsFull() async {
        let doc: [String: Any] = ["pro": true, "pro_until": farFuture]
        let t = await resolver(doc, gatingEnabled: false).tier(uid: "u1")
        XCTAssertEqual(t, .full)
    }

    func testGatingOff_currentSubscriberWithNoExpiryIsFull() async {
        let doc: [String: Any] = ["pro": true]
        let t = await resolver(doc, gatingEnabled: false).tier(uid: "u1")
        XCTAssertEqual(t, .full)
    }

    func testGatingOff_explicitlyNonProAccountIsStillFull() async {
        let t = await resolver(["pro": false], gatingEnabled: false).tier(uid: "u1")
        XCTAssertEqual(t, .full)
    }

    func testGatingOff_missingDocumentIsStillFull() async {
        let t = await resolver(nil, gatingEnabled: false).tier(uid: "u1")
        XCTAssertEqual(t, .full)
    }

    // MARK: - The default itself, with no argument passed at all

    func testDefaultResolverHasGatingOff() async {
        let t = await PlanTierResolver(read: { _ in ["pro": false] }).tier(uid: "u1")
        XCTAssertEqual(t, .full, "PlanTierResolver() with no gating override must match production: gating off")
    }
}

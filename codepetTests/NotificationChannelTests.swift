// codepetTests/NotificationChannelTests.swift
import XCTest
@testable import codepet

final class NotificationChannelTests: XCTestCase {
    func test_absentChoiceMeansInApp() {
        let prefs = FounderPrefs()
        XCTAssertEqual(NotificationCategory.sessionNudges.channel(in: prefs), .inApp)
    }

    func test_explicitOffIsHonoured() {
        var prefs = FounderPrefs()
        prefs.notifications[NotificationCategory.sessionNudges.key] = .off
        XCTAssertEqual(NotificationCategory.sessionNudges.channel(in: prefs), .off)
        XCTAssertEqual(NotificationCategory.runFinished.channel(in: prefs), .inApp)
    }

    func test_everyCategoryIsTranslated() {
        for c in NotificationCategory.allCases {
            XCTAssertFalse(c.title(.en).isEmpty)
            XCTAssertNotEqual(c.title(.en), c.title(.vi), c.key)
        }
    }

    /// The round trip this panel exists to get right: turning a category back to its
    /// default must REMOVE the key, not write `.inApp` explicitly. `saveFounderPrefs`
    /// writes `founderPrefs` with `mergeFields` (whole-field replace — see its doc
    /// comment), so what actually reaches the document is exactly `prefs.notifications`;
    /// a leftover key there is exactly the bug `mergeFields` was introduced to prevent.
    /// Verified here at the value-type level, one layer below the write itself.
    func test_backToDefaultRemovesTheKeyRatherThanWritingInAppExplicitly() {
        var prefs = FounderPrefs()
        prefs.notifications[NotificationCategory.sessionNudges.key] = .off
        XCTAssertEqual(prefs.notifications, ["sessionNudges": .off])

        // The panel's commit logic: setting the picker back to "In-app" removes the key.
        prefs.notifications.removeValue(forKey: NotificationCategory.sessionNudges.key)

        XCTAssertEqual(prefs.notifications, [:],
                       "back-to-default must leave no stale entry behind")
        XCTAssertEqual(NotificationCategory.sessionNudges.channel(in: prefs), .inApp)
    }

    /// End-to-end through the real write path, mirroring `FounderPrefsPersistenceTests`'
    /// pattern: off → back to default must persist an EMPTY notifications dict, not a
    /// dict still carrying `sessionNudges: .inApp` — the shape `merge: true` would have
    /// been unable to produce (it can only add/change keys, never remove one).
    @MainActor
    func test_offThenBackToDefaultRoundTripsThroughSetFounderPrefs() async {
        var written: [FounderPrefs] = []
        let store = CompanyStore(loader: { _ in .empty },
                                 founderPrefsSaver: { _, prefs in
            written.append(prefs); return true
        })
        await store.hydrate(companyId: "u")

        var prefs = store.company.founderPrefs
        prefs.notifications[NotificationCategory.sessionNudges.key] = .off
        await store.setFounderPrefs(prefs)
        XCTAssertEqual(written.last?.notifications, ["sessionNudges": .off])

        // Back to default: remove the key (the panel's commit logic), not `.inApp`.
        var backToDefault = store.company.founderPrefs
        backToDefault.notifications.removeValue(forKey: NotificationCategory.sessionNudges.key)
        await store.setFounderPrefs(backToDefault)

        XCTAssertEqual(written.last?.notifications, [:],
                       "the write must carry an empty dict, not a stale entry")
        XCTAssertEqual(store.company.founderPrefs.notifications, [:])
        XCTAssertEqual(NotificationCategory.sessionNudges.channel(in: store.company.founderPrefs), .inApp)
    }

    /// One category's choice must not bleed into the other.
    func test_oneCategoryOffDoesNotAffectTheOther() {
        var prefs = FounderPrefs()
        prefs.notifications[NotificationCategory.runFinished.key] = .off
        XCTAssertEqual(NotificationCategory.runFinished.channel(in: prefs), .off)
        XCTAssertEqual(NotificationCategory.sessionNudges.channel(in: prefs), .inApp)
    }
}

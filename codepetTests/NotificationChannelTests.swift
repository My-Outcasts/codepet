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

    /// The round trip this panel exists to get right, driven through the REAL rule the
    /// picker runs (`applying(_:to:)`) rather than a hand-rolled `removeValue`: turning a
    /// category back to its default must REMOVE the key, not write `.inApp` explicitly.
    /// `saveFounderPrefs` writes `founderPrefs` with `mergeFields` (whole-field replace —
    /// see its doc comment), so what reaches the document is exactly this dict; a leftover
    /// key here is exactly the bug `mergeFields` was introduced to prevent.
    func test_backToDefaultRemovesTheKeyRatherThanWritingInAppExplicitly() {
        let cat = NotificationCategory.sessionNudges
        let off = cat.applying(.off, to: [:])
        XCTAssertEqual(off, ["sessionNudges": .off])

        let backToDefault = cat.applying(.inApp, to: off)
        XCTAssertEqual(backToDefault, [:],
                       "back-to-default must leave no stale entry behind, not sessionNudges: .inApp")

        var prefs = FounderPrefs()
        prefs.notifications = backToDefault
        XCTAssertEqual(cat.channel(in: prefs), .inApp)

        // Choosing the default when it was never set is a no-op, not an inserted key.
        XCTAssertEqual(cat.applying(.inApp, to: [:]), [:])
        // ...and it only ever touches its OWN key.
        XCTAssertEqual(cat.applying(.inApp, to: ["runFinished": .off]), ["runFinished": .off])
    }

    /// `applying(_:to:)` is the exact inverse of `channel(in:)` for every category and
    /// channel — the property that makes "absent means in-app" safe to rely on.
    func test_applyingRoundTripsThroughChannelInPrefs() {
        for cat in NotificationCategory.allCases {
            for channel in NotificationChannel.allCases {
                var prefs = FounderPrefs()
                prefs.notifications = cat.applying(channel, to: prefs.notifications)
                XCTAssertEqual(cat.channel(in: prefs), channel, "\(cat.key) -> \(channel)")
            }
        }
    }

    /// End-to-end through the real write path, mirroring `FounderPrefsPersistenceTests`'
    /// pattern, and through the panel's real rule at every step: off → back to default must
    /// persist an EMPTY notifications dict, not a dict still carrying
    /// `sessionNudges: .inApp` — the shape `merge: true` would have been unable to produce
    /// (it can only add/change keys, never remove one).
    ///
    /// The saver asserts on the PAYLOAD `CompanyData` would hand Firestore, not on the
    /// `FounderPrefs` it was passed: a spy that only echoes its argument proves nothing
    /// about what the document ends up holding.
    @MainActor
    func test_offThenBackToDefaultRoundTripsThroughSetFounderPrefs() async {
        var written: [[String: NotificationChannel]?] = []
        let store = CompanyStore(loader: { _ in .empty },
                                 founderPrefsSaver: { _, prefs in
            written.append(Self.notificationsInPayload(prefs)); return true
        })
        await store.hydrate(companyId: "u")

        let cat = NotificationCategory.sessionNudges
        var prefs = store.company.founderPrefs
        prefs.notifications = cat.applying(.off, to: prefs.notifications)
        await store.setFounderPrefs(prefs)
        XCTAssertEqual(written.last, ["sessionNudges": .off])

        // Back to default, through the same rule the picker runs.
        var backToDefault = store.company.founderPrefs
        backToDefault.notifications = cat.applying(.inApp, to: backToDefault.notifications)
        await store.setFounderPrefs(backToDefault)

        XCTAssertEqual(written.last, [:],
                       "the payload must carry an empty notifications map, not a stale entry")
        XCTAssertEqual(store.company.founderPrefs.notifications, [:])
        XCTAssertEqual(cat.channel(in: store.company.founderPrefs), .inApp)
    }

    /// The guard on the write MODE, the thing the two round-trip tests above cannot see:
    /// `saveFounderPrefs` takes both of its Firestore arguments from `founderPrefsWrite`,
    /// so this asserts that descriptor is a whole-field replace of `founderPrefs`.
    ///
    /// Why it matters: with `merge: true` Firestore deep-merges nested maps, so writing
    /// `notifications: [:]` can only ADD or CHANGE keys — never remove one — and a category
    /// turned back to its default would survive in the document forever. `mergeFields`
    /// replaces the whole `founderPrefs` field instead of recursing into it.
    func test_founderPrefsWriteReplacesTheWholeFounderPrefsField() throws {
        var prefs = FounderPrefs()
        prefs.notifications[NotificationCategory.sessionNudges.key] = .off
        let set = try XCTUnwrap(CompanyData.founderPrefsWrite(prefs))

        XCTAssertEqual(set.mergeFields, ["founderPrefs"],
                       "the write must name founderPrefs as a replaced field; an empty list " +
                       "here (or a mode change to merge: true) resurrects removed keys")
        // Nothing may be written that isn't covered by mergeFields — an uncovered top-level
        // key is silently dropped by Firestore.
        XCTAssertEqual(Set(set.payload.keys), Set(set.mergeFields))
        // A whole-field replace: `notifications` nested UNDER founderPrefs, not flattened to
        // a dotted path (which would deep-merge into the map, key by key).
        let field = try XCTUnwrap(set.payload["founderPrefs"] as? [String: Any])
        XCTAssertEqual(field["notifications"] as? [String: String], ["sessionNudges": "off"])

        // And the shape whose meaning depends entirely on the mode: back to default sends an
        // EMPTY map — a no-op under `merge: true`, a clear under `mergeFields`.
        var cleared = prefs
        cleared.notifications = NotificationCategory.sessionNudges
            .applying(.inApp, to: cleared.notifications)
        let clearedSet = try XCTUnwrap(CompanyData.founderPrefsWrite(cleared))
        XCTAssertEqual(clearedSet.mergeFields, ["founderPrefs"])
        let clearedField = try XCTUnwrap(clearedSet.payload["founderPrefs"] as? [String: Any])
        XCTAssertEqual(clearedField["notifications"] as? [String: String], [:],
                       "an emptied map must still be present in the payload — that is what " +
                       "clears the stored key when the whole field is replaced")
    }

    /// `notifications` as it appears in the payload `CompanyData` would hand Firestore,
    /// read back out of the encoded blob rather than off the in-memory struct.
    private static func notificationsInPayload(_ prefs: FounderPrefs) -> [String: NotificationChannel]? {
        guard let write = CompanyData.founderPrefsWrite(prefs),
              let field = write.payload["founderPrefs"] as? [String: Any],
              let raw = field["notifications"] as? [String: String] else { return nil }
        return raw.compactMapValues(NotificationChannel.init(rawValue:))
    }

    /// One category's choice must not bleed into the other.
    func test_oneCategoryOffDoesNotAffectTheOther() {
        var prefs = FounderPrefs()
        prefs.notifications[NotificationCategory.runFinished.key] = .off
        XCTAssertEqual(NotificationCategory.runFinished.channel(in: prefs), .off)
        XCTAssertEqual(NotificationCategory.sessionNudges.channel(in: prefs), .inApp)
    }
}

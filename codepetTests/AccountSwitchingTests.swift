import XCTest
@testable import codepet

// Tests for the account-switch / data-isolation path. These lock down the three
// fixes that prevent one account's data from leaking into or overwriting
// another's when signing in and out on the same machine.

// MARK: - AccountDataStore (per-uid UserDefaults vault)

final class AccountDataStoreTests: XCTestCase {

    private var suiteName: String!
    private var defaults: UserDefaults!
    private var store: AccountDataStore!

    override func setUp() {
        super.setUp()
        // An isolated suite so the test never touches the real app domain.
        suiteName = "AccountDataStoreTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        store = AccountDataStore(defaults: defaults)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        store = nil
        super.tearDown()
    }

    /// First account on a fresh install adopts whatever working keys exist
    /// (snapshots them, does NOT clear them) and reports that it had data.
    func testFirstAccountAdoptsExistingData() {
        defaults.set(100, forKey: "cp_totalXP")

        let hadData = store.activate(uid: "A", previousUID: nil)

        XCTAssertTrue(hadData)
        XCTAssertEqual(defaults.integer(forKey: "cp_totalXP"), 100, "adoption must not clear keys")
        XCTAssertTrue(store.hasSnapshot(forUID: "A"))
    }

    /// First account with no working data reports no data (so the caller knows
    /// to attempt a cloud restore).
    func testFirstAccountWithNoDataReturnsFalse() {
        XCTAssertFalse(store.activate(uid: "A", previousUID: nil))
    }

    /// The core guarantee: switching between accounts is non-destructive and
    /// each account only ever sees its own data.
    func testSwitchVaultsOutgoingAndRestoresIncoming() {
        // A signs in first with 100 XP.
        defaults.set(100, forKey: "cp_totalXP")
        store.activate(uid: "A", previousUID: nil)

        // Switch to brand-new B: A's data is vaulted, the working set is cleared.
        let restoredB = store.activate(uid: "B", previousUID: "A")
        XCTAssertFalse(restoredB, "B is new, nothing to restore")
        XCTAssertNil(defaults.object(forKey: "cp_totalXP"), "outgoing account's data must be cleared")

        // B earns 5 XP, then switches back to A.
        defaults.set(5, forKey: "cp_totalXP")
        let restoredA = store.activate(uid: "A", previousUID: "B")
        XCTAssertTrue(restoredA)
        XCTAssertEqual(defaults.integer(forKey: "cp_totalXP"), 100, "A's data restored intact")

        // Switch back to B once more — B's 5 XP survived in the vault.
        let restoredB2 = store.activate(uid: "B", previousUID: "A")
        XCTAssertTrue(restoredB2)
        XCTAssertEqual(defaults.integer(forKey: "cp_totalXP"), 5, "B's data preserved, not lost")
    }

    /// Device-level prefs are never vaulted/cleared, so they persist across a
    /// switch while account data is swapped out.
    func testPreservedKeysSurviveSwitch() {
        defaults.set(true, forKey: "cp_isDarkMode") // preserved (device pref)
        defaults.set(100, forKey: "cp_totalXP")     // account data
        store.activate(uid: "A", previousUID: nil)

        store.activate(uid: "B", previousUID: "A")

        XCTAssertTrue(defaults.bool(forKey: "cp_isDarkMode"), "device pref preserved across switch")
        XCTAssertNil(defaults.object(forKey: "cp_totalXP"), "account data cleared for the new account")
    }

    /// Re-activating the same account (e.g. relaunch / same-account re-login) is
    /// a no-op and must not disturb the working keys.
    func testSameAccountIsNoOp() {
        defaults.set(100, forKey: "cp_totalXP")
        store.activate(uid: "A", previousUID: nil)

        defaults.set(150, forKey: "cp_totalXP")
        let restored = store.activate(uid: "A", previousUID: "A")

        XCTAssertTrue(restored)
        XCTAssertEqual(defaults.integer(forKey: "cp_totalXP"), 150, "same-account activate must not roll back")
    }
}

// MARK: - Cloud-restore gate (meaningful-progress predicate)

final class AppStateProgressGateTests: XCTestCase {

    @MainActor
    func testStrayDefaultsDoNotCountAsProgress() {
        let app = AppState()
        app.totalXP = 0
        app.completedLessons = []
        app.completedChallenges = []
        // A fresh-device account with only stray launch keys must read as "no
        // progress" so the sign-in path pulls its cloud backup instead of
        // overwriting it.
        XCTAssertFalse(app.hasMeaningfulProgress)
    }

    @MainActor
    func testAnyRealProgressCounts() {
        let app = AppState()
        app.totalXP = 0; app.completedLessons = []; app.completedChallenges = []

        app.totalXP = 10
        XCTAssertTrue(app.hasMeaningfulProgress)

        app.totalXP = 0
        app.completedLessons = ["intro"]
        XCTAssertTrue(app.hasMeaningfulProgress)

        app.completedLessons = []
        app.completedChallenges = ["c1"]
        XCTAssertTrue(app.hasMeaningfulProgress)
    }
}

// MARK: - SessionChatStore per-account scoping

final class SessionChatStoreAccountScopingTests: XCTestCase {

    private func accountDir(_ uid: String) -> URL {
        SessionChatStore.fileURL(forUID: uid).deletingLastPathComponent()
    }

    @MainActor
    func testActivateIsolatesHistoryPerAccount() {
        let uidA = "test-\(UUID().uuidString)"
        let uidB = "test-\(UUID().uuidString)"
        defer {
            try? FileManager.default.removeItem(at: accountDir(uidA))
            try? FileManager.default.removeItem(at: accountDir(uidB))
        }

        let store = SessionChatStore(saveDebounce: 0)

        // Account A writes a thread.
        store.activate(uid: uidA)
        store.append(ChatMessage(id: UUID(), role: .user, text: "secret-A", createdAt: Date()), to: "s1")
        store.flushForTests()

        // Switching to B must NOT surface A's in-memory threads or A's file.
        store.activate(uid: uidB)
        XCTAssertEqual(store.messages(for: "s1"), [], "B must not see A's chat history")

        store.append(ChatMessage(id: UUID(), role: .user, text: "secret-B", createdAt: Date()), to: "s1")
        store.flushForTests()

        // Switching back to A restores A's history, not B's.
        store.activate(uid: uidA)
        XCTAssertEqual(store.messages(for: "s1").map(\.text), ["secret-A"])

        store.activate(uid: uidB)
        XCTAssertEqual(store.messages(for: "s1").map(\.text), ["secret-B"])
    }

    @MainActor
    func testActivateDropsUnsavedThreadsOnSwitch() {
        let uidA = "test-\(UUID().uuidString)"
        let uidB = "test-\(UUID().uuidString)"
        defer {
            try? FileManager.default.removeItem(at: accountDir(uidA))
            try? FileManager.default.removeItem(at: accountDir(uidB))
        }

        let store = SessionChatStore(saveDebounce: 0)
        store.activate(uid: uidA)
        // Append WITHOUT flushing, then switch accounts.
        store.append(ChatMessage(id: UUID(), role: .user, text: "in-memory-A", createdAt: Date()), to: "s1")

        store.activate(uid: uidB)
        XCTAssertEqual(store.messages(for: "s1"), [], "unsaved in-memory threads must not leak across a switch")
    }
}

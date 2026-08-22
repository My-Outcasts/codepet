import XCTest
@testable import codepet

final class ProjectIdentityMapTests: XCTestCase {

    /// A third bug, on top of the two `teardown` documents below, and this one has no
    /// synchronous fix: `cfprefsd` flushes a suite's plist to disk on ITS OWN schedule, not
    /// on ours. `synchronize()` is a hint, not a guarantee, and the flush can land after
    /// `teardown`'s `removeItem` already ran — recreating the exact file we just deleted.
    /// Measured directly: three consecutive runs of this 11-test suite, with `teardown`'s
    /// delete in place, left 0, then 8, then 8-more (24 total, not capped at 8) `cp.tests.
    /// *.plist` files behind, because each run's late flush lands after that run's process
    /// has already moved on. There is no in-process call that makes the flush synchronous,
    /// so a per-test defer cannot be made to win that race every time.
    ///
    /// What IS fixable is unbounded growth: the ~140 files this bug produced were rounds of
    /// leftovers accumulating across MANY suite runs over time. Sweeping at the START of
    /// this class's run deletes whatever the PREVIOUS run's late flush left — every such
    /// file is guaranteed orphaned (the UUID it's named for was minted and abandoned in an
    /// earlier process), so sweeping it is always safe. Combined with `teardown`'s
    /// best-effort immediate delete, growth is now bounded to at most one run's worth of
    /// stragglers rather than accumulating indefinitely.
    override class func setUp() {
        super.setUp()
        let prefs = FileManager.default
            .urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Preferences")
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: prefs, includingPropertiesForKeys: nil) else { return }
        for f in files where f.lastPathComponent.hasPrefix("cp.tests.") {
            try? FileManager.default.removeItem(at: f)
        }
    }

    /// Its own suite, never `.standard`. A test that wrote to the real key could have its
    /// cleanup clobbered by a running app — i.e. eat the founder's real project bindings.
    private func makeMap(account: String? = "co-1") -> (ProjectIdentityMap, UserDefaults, String) {
        let name = "cp.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        let map = ProjectIdentityMap(defaults: defaults, key: "cp_project_ids_test")
        map.account = account
        return (map, defaults, name)
    }

    /// Two bugs stacked, and both had to be fixed to actually stop the leak.
    ///
    /// First: `removePersistentDomain(forName:)` has to run on the SAME
    /// `UserDefaults(suiteName:)` instance that wrote the data, not a fresh `UserDefaults()`
    /// — a fresh instance removes a domain Foundation's CFPreferences layer treats as
    /// separate from the one the suite instance is still holding in memory, so the
    /// fresh-instance call (the code before this fix) silently did nothing.
    ///
    /// Second, and this is the one that survives fixing the first: even called on the right
    /// instance and followed by `synchronize()`, `removePersistentDomain` does not delete
    /// the backing `~/Library/Preferences/<name>.plist` file — it only empties its content
    /// to `{}`. Verified empirically: a run of this suite after only the first fix left 8
    /// zero-byte-content `cp.tests.*.plist` files behind (one per test that actually called
    /// `bind`, which is the only thing that makes `UserDefaults` write the file at all; the
    /// 3 tests that never bind never created one). So the file itself has to be removed
    /// directly.
    private func teardown(_ defaults: UserDefaults, name: String) {
        defaults.removePersistentDomain(forName: name)
        defaults.synchronize()
        let path = FileManager.default
            .urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Preferences")
            .appendingPathComponent("\(name).plist")
        try? FileManager.default.removeItem(at: path)
    }

    func test_unknownPathHasNoId() {
        let (map, defaults, name) = makeMap()
        defer { teardown(defaults, name: name) }
        XCTAssertNil(map.id(forPath: "/Users/a/work/codepet"))
    }

    func test_bindThenLookup() {
        let (map, defaults, name) = makeMap()
        defer { teardown(defaults, name: name) }
        let id = ProjectIdentity.mint()
        map.bind(path: "/Users/a/work/codepet", to: id)
        XCTAssertEqual(map.id(forPath: "/Users/a/work/codepet"), id)
    }

    // The whole point of the indirection: one project, two machines, two paths, one id.
    // If this ever fails, repo-tier facts have gone back to being machine-local.
    func test_twoPathsCanShareOneId() {
        let (map, defaults, name) = makeMap()
        defer { teardown(defaults, name: name) }
        let id = ProjectIdentity.mint()
        map.bind(path: "/Users/a/work/codepet", to: id)
        map.bind(path: "/Users/b/src/codepet", to: id)
        XCTAssertEqual(map.id(forPath: "/Users/a/work/codepet"), id)
        XCTAssertEqual(map.id(forPath: "/Users/b/src/codepet"), id)
        XCTAssertEqual(map.paths(for: id).sorted(),
                       ["/Users/a/work/codepet", "/Users/b/src/codepet"])
    }

    func test_rebindingAPathReplacesItsId() {
        let (map, defaults, name) = makeMap()
        defer { teardown(defaults, name: name) }
        let first = ProjectIdentity.mint(), second = ProjectIdentity.mint()
        map.bind(path: "/p", to: first)
        map.bind(path: "/p", to: second)
        XCTAssertEqual(map.id(forPath: "/p"), second)
        XCTAssertEqual(map.paths(for: first), [])
    }

    func test_bindingSurvivesReload() {
        let (map, defaults, name) = makeMap()
        defer { teardown(defaults, name: name) }
        let id = ProjectIdentity.mint()
        map.bind(path: "/p", to: id)

        let fresh = ProjectIdentityMap(defaults: defaults, key: "cp_project_ids_test")
        fresh.account = "co-1"
        XCTAssertEqual(fresh.id(forPath: "/p"), id)
    }

    // THE test this revision exists for. Signing out must not destroy a binding the same
    // founder needs on the way back in. If it did, re-linking the folder would mint a new
    // id and silently orphan every fact scoped to the old one.
    func test_signOutThenBackInRestoresTheBinding() {
        let (map, defaults, name) = makeMap()
        defer { teardown(defaults, name: name) }
        let id = ProjectIdentity.mint()
        map.bind(path: "/p", to: id)

        map.account = nil                         // sign out
        XCTAssertNil(map.id(forPath: "/p"), "nothing resolves while nobody is signed in")

        map.account = "co-1"                      // same founder signs back in
        XCTAssertEqual(map.id(forPath: "/p"), id)
    }

    // One founder's bindings are not another's: the ids live under companies/{uid}.
    func test_accountsAreIsolated() {
        let (map, defaults, name) = makeMap(account: "co-1")
        defer { teardown(defaults, name: name) }
        let id = ProjectIdentity.mint()
        map.bind(path: "/p", to: id)

        map.account = "co-2"
        XCTAssertNil(map.id(forPath: "/p"))
        XCTAssertEqual(map.paths(for: id), [])

        let other = ProjectIdentity.mint()
        map.bind(path: "/p", to: other)
        XCTAssertEqual(map.id(forPath: "/p"), other)

        map.account = "co-1"
        XCTAssertEqual(map.id(forPath: "/p"), id, "the first founder's binding is untouched")
    }

    func test_bindDoesNothingWithNoAccount() {
        let (map, defaults, name) = makeMap(account: nil)
        defer { teardown(defaults, name: name) }
        map.bind(path: "/p", to: ProjectIdentity.mint())
        map.account = "co-1"
        XCTAssertNil(map.id(forPath: "/p"), "a bind with nobody signed in must not land anywhere")
    }

    func test_resetAllClearsEveryAccount() {
        let (map, defaults, name) = makeMap()
        defer { teardown(defaults, name: name) }
        map.bind(path: "/p", to: ProjectIdentity.mint())
        map.account = "co-2"
        map.bind(path: "/q", to: ProjectIdentity.mint())

        map.resetAll()
        XCTAssertNil(map.id(forPath: "/q"))
        map.account = "co-1"
        XCTAssertNil(map.id(forPath: "/p"))

        let fresh = ProjectIdentityMap(defaults: defaults, key: "cp_project_ids_test")
        fresh.account = "co-1"
        XCTAssertNil(fresh.id(forPath: "/p"))
    }

    func test_blankPathIsIgnored() {
        let (map, defaults, name) = makeMap()
        defer { teardown(defaults, name: name) }
        map.bind(path: "   ", to: ProjectIdentity.mint())
        XCTAssertNil(map.id(forPath: "   "))
    }

    func test_trailingSlashDoesNotMakeASecondBinding() {
        let (map, defaults, name) = makeMap()
        defer { teardown(defaults, name: name) }
        let id = ProjectIdentity.mint()
        map.bind(path: "/Users/a/work/codepet/", to: id)
        XCTAssertEqual(map.id(forPath: "/Users/a/work/codepet"), id)
    }
}

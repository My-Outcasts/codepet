import XCTest
@testable import codepet

final class ProjectIdentityMapTests: XCTestCase {

    /// Its own suite, never `.standard`. A test that wrote to the real key could have its
    /// cleanup clobbered by a running app — i.e. eat the founder's real project bindings.
    private func makeMap(account: String? = "co-1") -> (ProjectIdentityMap, UserDefaults, String) {
        let name = "cp.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        let map = ProjectIdentityMap(defaults: defaults, key: "cp_project_ids_test")
        map.account = account
        return (map, defaults, name)
    }

    func test_unknownPathHasNoId() {
        let (map, _, name) = makeMap()
        defer { UserDefaults().removePersistentDomain(forName: name) }
        XCTAssertNil(map.id(forPath: "/Users/a/work/codepet"))
    }

    func test_bindThenLookup() {
        let (map, _, name) = makeMap()
        defer { UserDefaults().removePersistentDomain(forName: name) }
        let id = ProjectIdentity.mint()
        map.bind(path: "/Users/a/work/codepet", to: id)
        XCTAssertEqual(map.id(forPath: "/Users/a/work/codepet"), id)
    }

    // The whole point of the indirection: one project, two machines, two paths, one id.
    // If this ever fails, repo-tier facts have gone back to being machine-local.
    func test_twoPathsCanShareOneId() {
        let (map, _, name) = makeMap()
        defer { UserDefaults().removePersistentDomain(forName: name) }
        let id = ProjectIdentity.mint()
        map.bind(path: "/Users/a/work/codepet", to: id)
        map.bind(path: "/Users/b/src/codepet", to: id)
        XCTAssertEqual(map.id(forPath: "/Users/a/work/codepet"), id)
        XCTAssertEqual(map.id(forPath: "/Users/b/src/codepet"), id)
        XCTAssertEqual(map.paths(for: id).sorted(),
                       ["/Users/a/work/codepet", "/Users/b/src/codepet"])
    }

    func test_rebindingAPathReplacesItsId() {
        let (map, _, name) = makeMap()
        defer { UserDefaults().removePersistentDomain(forName: name) }
        let first = ProjectIdentity.mint(), second = ProjectIdentity.mint()
        map.bind(path: "/p", to: first)
        map.bind(path: "/p", to: second)
        XCTAssertEqual(map.id(forPath: "/p"), second)
        XCTAssertEqual(map.paths(for: first), [])
    }

    func test_bindingSurvivesReload() {
        let (map, defaults, name) = makeMap()
        defer { UserDefaults().removePersistentDomain(forName: name) }
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
        let (map, _, name) = makeMap()
        defer { UserDefaults().removePersistentDomain(forName: name) }
        let id = ProjectIdentity.mint()
        map.bind(path: "/p", to: id)

        map.account = nil                         // sign out
        XCTAssertNil(map.id(forPath: "/p"), "nothing resolves while nobody is signed in")

        map.account = "co-1"                      // same founder signs back in
        XCTAssertEqual(map.id(forPath: "/p"), id)
    }

    // One founder's bindings are not another's: the ids live under companies/{uid}.
    func test_accountsAreIsolated() {
        let (map, _, name) = makeMap(account: "co-1")
        defer { UserDefaults().removePersistentDomain(forName: name) }
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
        let (map, _, name) = makeMap(account: nil)
        defer { UserDefaults().removePersistentDomain(forName: name) }
        map.bind(path: "/p", to: ProjectIdentity.mint())
        map.account = "co-1"
        XCTAssertNil(map.id(forPath: "/p"), "a bind with nobody signed in must not land anywhere")
    }

    func test_resetAllClearsEveryAccount() {
        let (map, defaults, name) = makeMap()
        defer { UserDefaults().removePersistentDomain(forName: name) }
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
        let (map, _, name) = makeMap()
        defer { UserDefaults().removePersistentDomain(forName: name) }
        map.bind(path: "   ", to: ProjectIdentity.mint())
        XCTAssertNil(map.id(forPath: "   "))
    }

    func test_trailingSlashDoesNotMakeASecondBinding() {
        let (map, _, name) = makeMap()
        defer { UserDefaults().removePersistentDomain(forName: name) }
        let id = ProjectIdentity.mint()
        map.bind(path: "/Users/a/work/codepet/", to: id)
        XCTAssertEqual(map.id(forPath: "/Users/a/work/codepet"), id)
    }
}

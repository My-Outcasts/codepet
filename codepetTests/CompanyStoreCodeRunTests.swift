import XCTest
@testable import codepet

@MainActor
final class CompanyStoreCodeRunTests: XCTestCase {
    // Never hydrates, so `account` stays nil and `linkProject`'s bind is a no-op — but an
    // injected suite (the `CompanyStoreProjectIdentityTests.makeStore` pattern) keeps that
    // safe rather than lucky, and keeps this test off the app's real `cp_project_ids_v1`.
    private func makeIdentityMap() -> ProjectIdentityMap {
        let suite = UserDefaults(suiteName: "cp.tests.\(UUID().uuidString)")!
        return ProjectIdentityMap(defaults: suite, key: "cp_project_ids_test")
    }

    // Same mitigation as `CompanyStoreProjectIdentityTests`, and needed for the same reason:
    // this suite pre-existingly failed to execute (0 tests, "Restarting after unexpected
    // exit, crash, or test timeout") even before this fix wave — `CompanyStore` is a
    // `@MainActor ObservableObject` with an isolated deinit, and letting one deallocate
    // during the test body aborts the host on this toolchain. Never cleared, for the same
    // reason: clearing it would deallocate everything it holds at exactly the point this
    // exists to avoid.
    private var retained: [CompanyStore] = []

    func test_linkProject_setsActiveLink() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("store-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = CompanyStore(identityMap: makeIdentityMap())
        retained.append(store)
        store.linkProject(path: dir.path, bootstrapClaudeMd: false)
        XCTAssertNotNil(store.activeProjectLink)
    }

    func test_startCodeRun_appendsAskAndProposes() {
        let store = CompanyStore()
        retained.append(store)
        let before = store.chatMessages.count
        store.startCodeRun(ask: "add a health check endpoint")
        XCTAssertEqual(store.chatMessages.count, before + 1)
        XCTAssertEqual(store.chatMessages.last?.role, .me)
        XCTAssertNotNil(store.codingRun.run)                 // a run was staged
        XCTAssertEqual(store.codingRunAnchorId, store.chatMessages.last?.id)
    }
}

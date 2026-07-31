import XCTest
@testable import codepet

@MainActor
final class CompanyStoreCodeRunTests: XCTestCase {
    func test_linkProject_setsActiveLink() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("store-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = CompanyStore()
        store.linkProject(path: dir.path, bootstrapClaudeMd: false)
        XCTAssertNotNil(store.activeProjectLink)
    }

    func test_startCodeRun_appendsAskAndProposes() {
        let store = CompanyStore()
        let before = store.chatMessages.count
        store.startCodeRun(ask: "add a health check endpoint")
        XCTAssertEqual(store.chatMessages.count, before + 1)
        XCTAssertEqual(store.chatMessages.last?.role, .me)
        XCTAssertNotNil(store.codingRun.run)                 // a run was staged
        XCTAssertEqual(store.codingRunAnchorId, store.chatMessages.last?.id)
    }
}

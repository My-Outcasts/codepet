import XCTest
@testable import codepet

@MainActor
final class SessionEndStoreTests: XCTestCase {
    private var tmpURL: URL!

    override func setUp() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("session-end-store-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        tmpURL = dir.appendingPathComponent("session_ends.jsonl")
        FileManager.default.createFile(atPath: tmpURL.path, contents: nil)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tmpURL.deletingLastPathComponent())
    }

    // MARK: - Helpers

    private func append(_ line: String) {
        let data = (line + "\n").data(using: .utf8)!
        let handle = try! FileHandle(forWritingTo: tmpURL)
        defer { try? handle.close() }
        try? handle.seekToEnd()
        try? handle.write(contentsOf: data)
    }

    private func endLine(sessionId: String) -> String {
        let obj: [String: Any] = [
            "session_id": sessionId,
            "time": "2026-05-05T09:00:00Z"
        ]
        let data = try! JSONSerialization.data(withJSONObject: obj)
        return String(data: data, encoding: .utf8)!
    }

    // MARK: - Tests

    func testReadsExistingEnds() async {
        append(endLine(sessionId: "session-A"))
        append(endLine(sessionId: "session-B"))

        let store = SessionEndStore(fileURL: tmpURL, pollInterval: 0.1)
        store.start()
        try? await Task.sleep(nanoseconds: 250_000_000)

        XCTAssertTrue(store.endedSessionIds.contains("session-A"))
        XCTAssertTrue(store.endedSessionIds.contains("session-B"))
        store.stop()
    }

    func testIncrementalReadOnNewLines() async {
        let store = SessionEndStore(fileURL: tmpURL, pollInterval: 0.1)
        store.start()
        try? await Task.sleep(nanoseconds: 150_000_000)

        XCTAssertTrue(store.endedSessionIds.isEmpty, "Store should start empty")

        append(endLine(sessionId: "session-live"))
        try? await Task.sleep(nanoseconds: 250_000_000)

        XCTAssertTrue(store.endedSessionIds.contains("session-live"),
                      "Store should pick up newly appended line via polling")
        store.stop()
    }

    func testSeedMockEndedInMemoryOnly() async throws {
        let store = SessionEndStore(fileURL: tmpURL, pollInterval: 0.1)
        store.seedMockEnded("mock-session")

        XCTAssertTrue(store.endedSessionIds.contains("mock-session"))

        let contents = try String(contentsOf: tmpURL, encoding: .utf8)
        XCTAssertTrue(contents.isEmpty, "seedMockEnded should not write to file")
    }
}

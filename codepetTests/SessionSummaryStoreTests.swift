import XCTest
@testable import codepet

@MainActor
final class SessionSummaryStoreTests: XCTestCase {
    private var tmpURL: URL!

    override func setUp() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("session-summary-store-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        tmpURL = dir.appendingPathComponent("session_summaries.jsonl")
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

    private func sampleLine(sessionId: String, summary: String = "Test summary", lesson: String = "Test lesson") -> String {
        let n: [String: Any] = [
            "session_id": sessionId,
            "summary": summary,
            "lesson": lesson,
            "generated_at": "2026-05-05T09:18:42Z",
            "model": "claude-haiku-4-5-20251001",
            "schema_version": 1
        ]
        let data = try! JSONSerialization.data(withJSONObject: n)
        return String(data: data, encoding: .utf8)!
    }

    private func makeSummary(sessionId: String) -> SessionSummary {
        SessionSummary(
            sessionId: sessionId,
            summary: "A test session summary for \(sessionId)",
            lesson: "A test lesson for \(sessionId)",
            generatedAt: Date(timeIntervalSince1970: 0),
            model: "claude-haiku-4-5-20251001",
            schemaVersion: 1
        )
    }

    // MARK: - Tests

    func testReadsExistingLinesOnStart() async {
        append(sampleLine(sessionId: "session-A", summary: "Summary A"))
        append(sampleLine(sessionId: "session-B", summary: "Summary B"))

        let store = SessionSummaryStore(fileURL: tmpURL, pollInterval: 0.1)
        store.start()
        try? await Task.sleep(nanoseconds: 250_000_000)

        XCTAssertEqual(store.summaries.count, 2)
        XCTAssertEqual(store.summaries["session-A"]?.summary, "Summary A")
        XCTAssertEqual(store.summaries["session-B"]?.summary, "Summary B")
        store.stop()
    }

    func testAppendSummaryWritesToFile() async throws {
        let store = SessionSummaryStore(fileURL: tmpURL, pollInterval: 1.0)
        let s = makeSummary(sessionId: "session-write-test")
        try store.appendSummary(s)

        let contents = try String(contentsOf: tmpURL, encoding: .utf8)
        XCTAssertTrue(contents.contains("\"session_id\":\"session-write-test\""),
                      "File should contain the session_id key")
        XCTAssertTrue(contents.contains("\"summary\":\"A test session summary for session-write-test\""),
                      "File should contain the summary text")
        // In-memory update should be immediate
        XCTAssertEqual(store.summaries["session-write-test"]?.sessionId, "session-write-test")
    }

    func testIncrementalReadOnNewLines() async {
        let store = SessionSummaryStore(fileURL: tmpURL, pollInterval: 0.1)
        store.start()
        try? await Task.sleep(nanoseconds: 150_000_000)

        XCTAssertEqual(store.summaries.count, 0, "Store should start empty")

        append(sampleLine(sessionId: "session-live", summary: "Live summary"))
        try? await Task.sleep(nanoseconds: 250_000_000)

        XCTAssertEqual(store.summaries["session-live"]?.summary, "Live summary",
                       "Store should pick up newly appended line via polling")
        store.stop()
    }

    func testCorruptLineSkippedAndContinues() async {
        append(sampleLine(sessionId: "session-good-1", summary: "Good 1"))
        append("{not valid json at all")
        append(sampleLine(sessionId: "session-good-2", summary: "Good 2"))

        let store = SessionSummaryStore(fileURL: tmpURL, pollInterval: 0.1)
        store.start()
        try? await Task.sleep(nanoseconds: 250_000_000)

        XCTAssertEqual(store.summaries.count, 2,
                       "Corrupt line should be skipped; valid lines before and after should be read")
        XCTAssertEqual(store.summaries["session-good-1"]?.summary, "Good 1")
        XCTAssertEqual(store.summaries["session-good-2"]?.summary, "Good 2")
        store.stop()
    }

    func testSeedMockSummaryIsInMemoryOnly() async throws {
        let store = SessionSummaryStore(fileURL: tmpURL, pollInterval: 0.1)
        let s = makeSummary(sessionId: "mock-session")
        store.seedMockSummary(s)

        // In-memory immediately available
        XCTAssertEqual(store.summaries["mock-session"]?.sessionId, "mock-session")

        // File should remain empty (seedMock is in-memory only)
        let contents = try String(contentsOf: tmpURL, encoding: .utf8)
        XCTAssertTrue(contents.isEmpty, "seedMockSummary should not write to file")
    }
}

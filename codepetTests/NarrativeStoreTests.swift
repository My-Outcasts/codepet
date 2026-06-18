import XCTest
@testable import codepet

@MainActor
final class NarrativeStoreTests: XCTestCase {
    private var tmpURL: URL!

    override func setUp() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("narrative-store-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        tmpURL = dir.appendingPathComponent("narratives.jsonl")
        FileManager.default.createFile(atPath: tmpURL.path, contents: nil)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tmpURL.deletingLastPathComponent())
    }

    private func append(_ line: String) {
        let data = (line + "\n").data(using: .utf8)!
        let handle = try! FileHandle(forWritingTo: tmpURL)
        defer { try? handle.close() }
        try? handle.seekToEnd()
        try? handle.write(contentsOf: data)
    }

    /// Number of distinct narratives held by the store. NarrativeStore mirrors
    /// each narrative under TWO dictionary keys — a language-qualified one
    /// ("t1:en") and the plain turn_id ("t1") for backward compat — so the raw
    /// `narratives.count` is doubled. We count only the language-keyed entries,
    /// which is exactly the canonical set consumers use (e.g. GuidanceEnricher
    /// filters `narratives` for keys containing ":").
    private func canonicalCount(_ store: NarrativeStore) -> Int {
        store.narratives.keys.filter { $0.contains(":") }.count
    }

    private func sampleLine(turnId: String, title: String) -> String {
        let n: [String: Any] = [
            "turn_id": turnId,
            "session_id": "s",
            "generated_at": "2026-05-05T09:18:42Z",
            "title": title,
            "what_you_wanted": "w",
            "what_happened": "h",
            "lesson": "l",
            "model": "claude-haiku-4-5-20251001",
            "schema_version": 1
        ]
        let data = try! JSONSerialization.data(withJSONObject: n)
        return String(data: data, encoding: .utf8)!
    }

    func testReadsExistingLinesOnStart() async {
        append(sampleLine(turnId: "t1", title: "First"))
        append(sampleLine(turnId: "t2", title: "Second"))

        let store = NarrativeStore(fileURL: tmpURL, pollInterval: 0.1)
        store.start()
        try? await Task.sleep(nanoseconds: 200_000_000)

        XCTAssertEqual(canonicalCount(store), 2)
        XCTAssertEqual(store.narrative(forTurnId: "t1", language: "en")?.title, "First")
        XCTAssertEqual(store.narrative(forTurnId: "t2", language: "en")?.title, "Second")
        store.stop()
    }

    func testIncrementalReadOnNewLines() async {
        let store = NarrativeStore(fileURL: tmpURL, pollInterval: 0.1)
        store.start()
        try? await Task.sleep(nanoseconds: 150_000_000)

        XCTAssertEqual(store.narratives.count, 0)

        append(sampleLine(turnId: "t1", title: "Live"))
        try? await Task.sleep(nanoseconds: 200_000_000)

        XCTAssertEqual(store.narratives["t1"]?.title, "Live")
        store.stop()
    }

    func testSkipsCorruptLinesAndContinues() async {
        append(sampleLine(turnId: "t1", title: "Good"))
        append("{not valid json")
        append(sampleLine(turnId: "t2", title: "AlsoGood"))

        let store = NarrativeStore(fileURL: tmpURL, pollInterval: 0.1)
        store.start()
        try? await Task.sleep(nanoseconds: 200_000_000)

        XCTAssertEqual(canonicalCount(store), 2)
        store.stop()
    }

    func testDuplicateTurnIDLastWriteWins() async {
        append(sampleLine(turnId: "t1", title: "First"))
        append(sampleLine(turnId: "t1", title: "Second"))

        let store = NarrativeStore(fileURL: tmpURL, pollInterval: 0.1)
        store.start()
        try? await Task.sleep(nanoseconds: 200_000_000)

        XCTAssertEqual(canonicalCount(store), 1)
        XCTAssertEqual(store.narrative(forTurnId: "t1", language: "en")?.title, "Second")
        store.stop()
    }

    func testFileMissingIsCreated() async {
        try? FileManager.default.removeItem(at: tmpURL)

        let store = NarrativeStore(fileURL: tmpURL, pollInterval: 0.1)
        store.start()
        try? await Task.sleep(nanoseconds: 200_000_000)

        XCTAssertTrue(FileManager.default.fileExists(atPath: tmpURL.path))
        store.stop()
    }

    func testFileShrinkResetsOffset() async {
        append(sampleLine(turnId: "t1", title: "Early"))

        let store = NarrativeStore(fileURL: tmpURL, pollInterval: 0.1)
        store.start()
        try? await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertEqual(canonicalCount(store), 1)

        // Truncate then write fresh content
        try? FileManager.default.removeItem(at: tmpURL)
        FileManager.default.createFile(atPath: tmpURL.path, contents: nil)
        append(sampleLine(turnId: "t99", title: "New"))
        try? await Task.sleep(nanoseconds: 200_000_000)

        XCTAssertNotNil(store.narrative(forTurnId: "t99", language: "en"))
        store.stop()
    }

    func testAppendNarrativeWritesToFile() async throws {
        let store = NarrativeStore(fileURL: tmpURL, pollInterval: 1.0)

        let n = Narrative(
            title: "T",
            whatYouWanted: "w",
            whatHappened: "h",
            lesson: "l",
            nextSteps: "",
            model: "claude-haiku-4-5-20251001",
            generatedAt: Date(timeIntervalSince1970: 0),
            schemaVersion: 1
        )
        try store.appendNarrative(turnId: "t1", sessionId: "s", language: "en", narrative: n)

        let contents = try String(contentsOf: tmpURL, encoding: .utf8)
        XCTAssertTrue(contents.contains("\"turn_id\":\"t1\""))
        XCTAssertTrue(contents.contains("\"title\":\"T\""))
    }
}

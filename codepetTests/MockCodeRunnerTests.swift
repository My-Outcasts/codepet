import XCTest
@testable import codepet

final class MockCodeRunnerTests: XCTestCase {
    func test_run_makesRealEditAndReportsDiff() async throws {
        // Arrange a temp working dir with one editable file.
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("mockrun-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("main.swift")
        try "let x = 1\n".write(to: file, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: dir) }

        // Act
        var steps: [ExecStep] = []
        let outcome = await MockCodeRunner().run(
            prompt: "tweak the file", workingDir: dir.path, onStep: { steps.append($0) })

        // Assert: no failure, a real diff, and the file actually changed on disk.
        XCTAssertNil(outcome.failure)
        XCTAssertFalse(outcome.diffs.isEmpty, "mock should produce at least one file diff")
        let after = try String(contentsOf: file, encoding: .utf8)
        XCTAssertNotEqual(after, "let x = 1\n", "mock must make a real on-disk edit")
    }
}

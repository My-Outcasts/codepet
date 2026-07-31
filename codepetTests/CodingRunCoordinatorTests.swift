import XCTest
@testable import codepet

@MainActor
final class CodingRunCoordinatorTests: XCTestCase {
    /// A temp git repo with one committed file, so the git backend engages.
    private func makeRepo() throws -> ProjectLink {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("coord-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try "let x = 1\n".write(to: dir.appendingPathComponent("main.swift"), atomically: true, encoding: .utf8)
        _ = GitRunner.run(["init"], in: dir.path)
        _ = GitRunner.run(["add", "."], in: dir.path)
        _ = GitRunner.run(["-c", "user.email=t@t.co", "-c", "user.name=t", "commit", "-m", "init"], in: dir.path)
        return ProjectProbe.probe(path: dir.path)
    }

    func test_propose_multiFile_entersPreviewing() throws {
        let c = CodingRunCoordinator(runner: MockCodeRunner())
        c.propose(ask: "do a thing", plannedFiles: 2, needsBash: false, link: try makeRepo())
        XCTAssertEqual(c.run?.phase, .previewing)
    }

    func test_propose_noLink_entersNoProject() {
        let c = CodingRunCoordinator(runner: MockCodeRunner())
        c.propose(ask: "do a thing", plannedFiles: 2, needsBash: false, link: nil)
        XCTAssertEqual(c.run?.phase, .noProject)
    }

    func test_execute_thenApprove_reachesCommitted() async throws {
        let c = CodingRunCoordinator(runner: MockCodeRunner())
        c.propose(ask: "tweak main", plannedFiles: 1, needsBash: false, link: try makeRepo())
        await c.execute()
        XCTAssertEqual(c.run?.phase, .reviewing)
        await c.approve(acceptedPaths: c.run?.acceptedPaths ?? [])
        XCTAssertEqual(c.run?.phase, .committed)
    }
}

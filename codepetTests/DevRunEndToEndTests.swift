// codepetTests/DevRunEndToEndTests.swift
import XCTest
@testable import codepet

/// Drives a whole coding run — propose → confirm → execute → approve — over the
/// mock runner and REAL backends, in a scratch directory.
///
/// **Why this is not another pure-model test.** Everything the work pane got wrong
/// was in the seams: `execute()` had no caller, and Approve passed absolute paths to
/// an apply step that joins them onto the project root. Both compile, both type-check,
/// both pass every model test — and the second one turns the gate's one button into
/// "Couldn't apply all the changes." A test that never touches the filesystem cannot
/// see either.
///
/// `CodingRunCoordinator` is `@MainActor` + `ObservableObject`, which Landmine 3 says
/// can crash the XCTest host on dealloc. It is one object per test and it has behaved;
/// if this suite ever starts taking the host down, that is the known bug and not a
/// regression in the code under test.
@MainActor
final class DevRunEndToEndTests: XCTestCase {

    private var dir: URL!

    override func setUp() async throws {
        try await super.setUp()
        dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("codepet-e2e-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try "let greeting = \"Hi \" + name\n"
            .write(to: dir.appendingPathComponent("greeting.js"), atomically: true, encoding: .utf8)
    }

    override func tearDown() async throws {
        if let dir { try? FileManager.default.removeItem(at: dir) }
        try await super.tearDown()
    }

    private func gitInit() {
        _ = GitRunner.run(["init", "-b", "main"], in: dir.path)
        _ = GitRunner.run(["add", "."], in: dir.path)
        _ = GitRunner.run(["-c", "user.name=T", "-c", "user.email=t@t.local",
                           "commit", "-m", "base"], in: dir.path)
    }

    private func coordinator() -> CodingRunCoordinator {
        CodingRunCoordinator(runner: MockCodeRunner())
    }

    /// **The bug the founder saw.** A two-file proposal parks in `.previewing` and
    /// stays there until something calls `execute()` — which, in Developer, nothing
    /// did. This asserts the phase the pane must now drive out of, so the dead end is
    /// described rather than rediscovered.
    func testAMultiFileProposalWaitsForAConfirmation() {
        let c = coordinator()
        c.propose(ask: "Fix the signup validation", plannedFiles: 2, needsBash: false,
                  link: ProjectProbe.probe(path: dir.path))
        XCTAssertEqual(c.run?.phase, .previewing)
        XCTAssertFalse(DevRunStage.startsItself(c.run?.phase),
                       "nothing may start this on its own — the founder has not agreed to the plan")
        XCTAssertTrue(c.steps.isEmpty, "no work may have happened before the confirmation")
    }

    /// The full walk on a git repo: it runs, it produces a diff, and approving puts a
    /// real commit on a `codepet/*` branch — which is the claim the walkthrough's
    /// loudest caption makes.
    func testAGitRunLandsOnItsOwnBranchAndNowhereElse() async {
        gitInit()
        let c = coordinator()
        c.propose(ask: "Fix the signup validation", plannedFiles: 2, needsBash: false,
                  link: ProjectProbe.probe(path: dir.path))

        await c.execute()
        XCTAssertEqual(c.run?.phase, .reviewing, "the run never reached the gate")
        XCTAssertFalse(c.run?.diffs.isEmpty ?? true, "reviewing with nothing to review")
        XCTAssertFalse(c.steps.isEmpty, "no exec log — the pane would show a blank process")

        guard let accepted = c.run?.acceptedPaths else { return XCTFail("no accepted paths") }
        await c.approve(acceptedPaths: accepted)
        XCTAssertEqual(c.run?.phase, .committed, "approve did not commit")

        let branch = GitRunner.run(["rev-parse", "--abbrev-ref", "HEAD"], in: dir.path)
            .stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertTrue(branch.hasPrefix("codepet/"), "landed on \(branch), not a session branch")
        // The ceiling: `main` must not have moved.
        let mainCount = GitRunner.run(["rev-list", "--count", "main"], in: dir.path)
            .stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertEqual(mainCount, "1", "the run reached main — the one thing it must never do")
    }

    /// The same walk on a plain folder, where there is no branch and the shadow copy
    /// is applied back over the files. This is the path the absolute-path bug broke.
    func testAShadowRunAppliesToTheFilesOnDisk() async {
        let c = coordinator()
        c.propose(ask: "Fix the signup validation", plannedFiles: 2, needsBash: false,
                  link: ProjectProbe.probe(path: dir.path))
        await c.execute()
        XCTAssertEqual(c.run?.phase, .reviewing)
        XCTAssertEqual(c.run?.backend, .shadow, "a non-git folder must not claim a branch")

        guard let accepted = c.run?.acceptedPaths else { return XCTFail("no accepted paths") }
        await c.approve(acceptedPaths: accepted)
        XCTAssertEqual(c.run?.phase, .committed)

        let after = (try? String(contentsOf: dir.appendingPathComponent("greeting.js"),
                                 encoding: .utf8)) ?? ""
        XCTAssertTrue(after.contains("Hello, "),
                      "approve reported success but the file on disk is unchanged")
    }

    /// **The falsification, kept as a test.** `acceptedPaths` are relative to the
    /// commit root and `applyShadow` re-joins them to it; the gate's Approve button
    /// passed `diffs.map(\.path)`, which are absolute. The join produced
    /// `/project//private/var/…`, every copy threw, and the founder got "Couldn't
    /// apply all the changes" from a run that had worked perfectly.
    ///
    /// If someone "simplifies" the button back to the diff paths, this goes red —
    /// and it also proves the fix above is load-bearing rather than cosmetic.
    func testAbsolutePathsAreNotWhatTheApplyStepWants() async {
        let c = coordinator()
        c.propose(ask: "Fix the signup validation", plannedFiles: 2, needsBash: false,
                  link: ProjectProbe.probe(path: dir.path))
        await c.execute()
        guard let diffs = c.run?.diffs, !diffs.isEmpty else { return XCTFail("no diffs") }

        // What the pane used to send.
        for path in diffs.map(\.path) {
            XCTAssertTrue(path.hasPrefix("/"), "the diff path is absolute")
        }
        XCTAssertNotEqual(Set(diffs.map(\.path)), c.run?.acceptedPaths,
                          "if these are ever the same set, the distinction this guards is gone")

        await c.approve(acceptedPaths: Set(diffs.map(\.path)))
        guard case .failed = c.run?.phase else {
            return XCTFail("absolute paths now apply cleanly — re-check whether the "
                           + "relative-path fix is still necessary")
        }
    }
}

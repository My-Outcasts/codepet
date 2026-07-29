import Foundation
import Combine

/// Drives one coding run through its lifecycle over a `CodeRunning` seam and the
/// real `CodeCommitService`. UI (2C-2) renders from `run`; nothing here draws.
@MainActor
final class CodingRunCoordinator: ObservableObject {
    @Published private(set) var run: EditCodeRun?
    /// Live tool-use steps for the run card (appended as the runner streams).
    @Published private(set) var steps: [ExecStep] = []

    private let runner: CodeRunning
    // Live backend session handles, set during `execute`.
    private var gitSession: GitSession?
    private var shadowSession: CodeCommitService.ShadowSession?
    private var proposedLink: ProjectLink?

    init(runner: CodeRunning) {
        self.runner = runner
    }

    /// Stage a run: no linked project → `.noProject`; else pick the backend and
    /// decide whether the plan-preview is needed. Does not execute.
    func propose(ask: String, plannedFiles: Int, needsBash: Bool, link: ProjectLink?) {
        // Don't clobber a run that's actively executing.
        if run?.phase == .running { return }
        // A new proposal supersedes any un-resolved prior run — tear down its live
        // session so no branch/shadow is orphaned (no-op when there's none).
        teardownSession()
        steps = []
        guard let link else {
            run = EditCodeRun(ask: ask, backend: .shadow, phase: .noProject)
            proposedLink = nil
            return
        }
        proposedLink = link
        let backend = EditCodePlanner.backend(for: link, ask: ask)
        let phase: EditCodePhase = EditCodePlanner.needsPreview(plannedFiles: plannedFiles, needsBash: needsBash)
            ? .previewing : .readyToRun
        run = EditCodeRun(ask: ask, backend: backend, phase: phase)
    }

    /// Begin the backend session, run the agent in its working dir, land in
    /// `.reviewing` (diffs) or `.failed`. A failure tears the session down so no
    /// dangling branch / shadow remains.
    func execute() async {
        guard var current = run, let link = proposedLink,
              current.phase == .readyToRun || current.phase == .previewing else { return }
        current.phase = .running
        run = current

        let workingDir: String
        switch current.backend {
        case .git:
            guard let s = CodeCommitService.beginGit(projectPath: link.path, taskTitle: current.ask) else {
                current.phase = .failed("Couldn't start a git branch for this run.")
                run = current
                return
            }
            gitSession = s
            workingDir = link.path
        case .shadow:
            guard let s = CodeCommitService.beginShadow(projectPath: link.path) else {
                current.phase = .failed("Couldn't prepare a safe copy for this run.")
                run = current
                return
            }
            shadowSession = s
            workingDir = s.shadowDir
        }

        let outcome = await runner.run(prompt: current.ask, workingDir: workingDir,
                                       onStep: { [weak self] step in self?.steps.append(step) })
        guard var after = run else { return }
        if let failure = outcome.failure {
            teardownSession()
            after.phase = .failed(failure)
            run = after
            return
        }
        after.diffs = outcome.diffs
        after.acceptedPaths = Set(outcome.diffs.map {
            relPath($0.path, projectRoot: link.path, shadow: shadowSession?.shadowDir)
        })
        after.phase = .reviewing
        run = after
    }

    func approve(acceptedPaths: Set<String>) async {
        guard var current = run, current.phase == .reviewing else { return }
        switch current.backend {
        case .git:
            guard let s = gitSession else {
                current.phase = .failed("No active session to commit."); run = current; return
            }
            let result = CodeCommitService.commitGit(s, files: Array(acceptedPaths),
                                                     message: "codepet: \(current.ask)")
            guard result.committed else {
                CodeCommitService.abortGit(s)   // restore the founder's stash / clean up
                current.phase = .failed("Couldn't commit the changes.")
                run = current; clearSessions(); return
            }
            // NOTE: result.stashRestored == false → the founder's overlapping work is
            // retained in `git stash` for recovery; 2C-2 surfaces that.
        case .shadow:
            guard let s = shadowSession else {
                current.phase = .failed("No active session to apply."); run = current; return
            }
            let ok = CodeCommitService.applyShadow(s, acceptedRelPaths: Array(acceptedPaths))
            CodeCommitService.discardShadow(s)
            guard ok else {
                current.phase = .failed("Couldn't apply all the changes."); run = current; clearSessions(); return
            }
        }
        current.phase = .committed
        run = current
        clearSessions()
    }

    func reject() async {
        guard var current = run, current.phase == .reviewing else { return }
        switch current.backend {
        case .git: if let s = gitSession { CodeCommitService.abortGit(s) }
        case .shadow: if let s = shadowSession { CodeCommitService.discardShadow(s) }
        }
        current.phase = .discarded
        run = current
        clearSessions()
    }

    /// Dismiss a run that hasn't started executing — the founder tapped Cancel on
    /// the plan-preview, or dismissed a `.noProject`/`.failed`/`.committed` card.
    /// Tears down any live backend session so no branch/shadow is orphaned, then
    /// clears the card. No-op WHILE running: an in-flight subprocess must resolve
    /// (or fail) on its own before the card can be cleared.
    func cancel() {
        guard let phase = run?.phase, phase != .running else { return }
        teardownSession()
        steps = []
        run = nil
    }

    // MARK: - Helpers

    /// Abort/discard any live backend session (no-op when there's none). Used on a
    /// run failure and when a new `propose` supersedes an un-resolved run.
    private func teardownSession() {
        if let s = gitSession { CodeCommitService.abortGit(s) }
        if let s = shadowSession { CodeCommitService.discardShadow(s) }
        clearSessions()
    }

    private func clearSessions() {
        gitSession = nil
        shadowSession = nil
        proposedLink = nil
    }

    /// Absolute diff path → path relative to the commit root (project root for git,
    /// shadow dir for shadow — both map to the same relative layout).
    private func relPath(_ abs: String, projectRoot: String, shadow: String?) -> String {
        // Standardize the root so a tilde/non-canonical link path still prefix-matches
        // the runner's standardized absolute diff paths (else nested paths flatten).
        let root = URL(fileURLWithPath: shadow ?? projectRoot).standardizedFileURL.path
        if abs.hasPrefix(root + "/") { return String(abs.dropFirst(root.count + 1)) }
        return (abs as NSString).lastPathComponent
    }
}

#if DEBUG
/// Preview/fixture support so `CodeRunCardView`'s `#Preview` can render each phase
/// without spawning a real `claude` subprocess. DEBUG-only — never shipped.
extension CodingRunCoordinator {
    static func preview(_ run: EditCodeRun, steps: [ExecStep] = []) -> CodingRunCoordinator {
        let c = CodingRunCoordinator(runner: _NoopCodeRunner())
        c.run = run
        c.steps = steps
        return c
    }
}

private final class _NoopCodeRunner: CodeRunning {
    func run(prompt: String, workingDir: String, onStep: @escaping (ExecStep) -> Void) async -> CodeRunOutcome {
        CodeRunOutcome(diffs: [], failure: nil)
    }
}
#endif

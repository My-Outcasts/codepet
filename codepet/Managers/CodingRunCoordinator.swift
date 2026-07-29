import Foundation
import Combine

/// Drives one coding run through its lifecycle over a `CodeRunning` seam and the
/// real `CodeCommitService`. UI (2C-2) renders from `run`; nothing here draws.
@MainActor
final class CodingRunCoordinator: ObservableObject {
    @Published private(set) var run: EditCodeRun?

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
        guard var current = run, let link = proposedLink else { return }
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

        let outcome = await runner.run(prompt: current.ask, workingDir: workingDir)
        guard var after = run else { return }
        if let failure = outcome.failure {
            teardownOnFailure()
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
        guard var current = run else { return }
        switch current.backend {
        case .git:
            if let s = gitSession {
                _ = CodeCommitService.commitGit(s, files: Array(acceptedPaths), message: "codepet: \(current.ask)")
            }
        case .shadow:
            if let s = shadowSession {
                _ = CodeCommitService.applyShadow(s, acceptedRelPaths: Array(acceptedPaths))
                CodeCommitService.discardShadow(s)
            }
        }
        current.phase = .committed
        run = current
        clearSessions()
    }

    func reject() async {
        guard var current = run else { return }
        switch current.backend {
        case .git: if let s = gitSession { CodeCommitService.abortGit(s) }
        case .shadow: if let s = shadowSession { CodeCommitService.discardShadow(s) }
        }
        current.phase = .discarded
        run = current
        clearSessions()
    }

    // MARK: - Helpers

    private func teardownOnFailure() {
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
        let root = shadow ?? projectRoot
        if abs.hasPrefix(root + "/") { return String(abs.dropFirst(root.count + 1)) }
        return (abs as NSString).lastPathComponent
    }
}

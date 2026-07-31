import Foundation

/// Which safe-commit backend a coding run uses (chosen from the linked project).
enum CodeBackend: Equatable {
    case git(branch: String)   // throwaway codepet/<slug> branch
    case shadow                // temp shadow copy + apply-with-backup
}

/// The lifecycle phase of a coding run (spec §2). UI (2C-2) renders from this.
enum EditCodePhase: Equatable {
    case noProject          // no linked project → can't run; UI offers to link
    case previewing         // multi-file/Bash → show the plan-preview, await confirm
    case readyToRun         // small/safe → run immediately
    case running
    case reviewing          // diffs ready, awaiting Approve/Reject
    case committed
    case discarded
    case failed(String)     // honest reason (e.g. "claude not installed")
}

/// The state of one coding run. Pure value type — the coordinator mutates `phase`,
/// `diffs`, and `acceptedPaths` as the run progresses.
struct EditCodeRun: Equatable {
    let ask: String
    let backend: CodeBackend
    var phase: EditCodePhase
    var diffs: [ClaudeCodeRunner.FileDiff]
    var acceptedPaths: Set<String>

    init(ask: String, backend: CodeBackend, phase: EditCodePhase,
         diffs: [ClaudeCodeRunner.FileDiff] = [], acceptedPaths: Set<String> = []) {
        self.ask = ask; self.backend = backend; self.phase = phase
        self.diffs = diffs; self.acceptedPaths = acceptedPaths
    }
}

/// Pure decisions for a coding run.
enum EditCodePlanner {
    /// Show the plan-preview for a multi-file change or anything that may run Bash;
    /// skip it for a single-file, no-Bash edit (the diff review is the real gate).
    static func needsPreview(plannedFiles: Int, needsBash: Bool) -> Bool {
        needsBash || plannedFiles > 1
    }

    static func backend(for link: ProjectLink, ask: String = "") -> CodeBackend {
        link.isGitRepo ? .git(branch: "codepet/" + CommitSlug.make(from: ask)) : .shadow
    }
}

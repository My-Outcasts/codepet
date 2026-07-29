import Foundation
import Combine

/// The final outcome of a coding-agent run. Streaming is a UI concern (2C-2); the
/// coordinator only needs the resulting diffs or an honest failure reason.
struct CodeRunOutcome: Equatable {
    let diffs: [ClaudeCodeRunner.FileDiff]
    let failure: String?   // nil = success
}

/// Seam over the code-editing runner so the coordinator is testable without the
/// real `claude` subprocess. Production conformer is `ClaudeCodeRunAdapter`.
protocol CodeRunning {
    func run(prompt: String, workingDir: String) async -> CodeRunOutcome
}

/// Bridges `ClaudeCodeRunner` (an ObservableObject that streams to `@Published`
/// state) to the async `CodeRunning` seam: kicks off the run and resolves once the
/// runner reaches a terminal state, returning its computed `fileDiffs` (or the
/// failure reason). Build-verified glue — not unit-tested (needs the CLI).
@MainActor
final class ClaudeCodeRunAdapter: CodeRunning {
    private let runner = ClaudeCodeRunner()
    private var cancellable: AnyCancellable?

    func run(prompt: String, workingDir: String) async -> CodeRunOutcome {
        await withCheckedContinuation { (cont: CheckedContinuation<CodeRunOutcome, Never>) in
            var resumed = false
            let finish: (CodeRunOutcome) -> Void = { [weak self] outcome in
                guard !resumed else { return }
                resumed = true
                self?.cancellable = nil
                cont.resume(returning: outcome)
            }
            cancellable = runner.$state.sink { [weak runner] state in
                switch state {
                case .finished:
                    finish(CodeRunOutcome(diffs: runner?.fileDiffs ?? [], failure: nil))
                case .failed(let reason):
                    finish(CodeRunOutcome(diffs: [], failure: reason))
                default:
                    break
                }
            }
            runner.run(prompt: prompt, projectDir: workingDir)
        }
    }
}

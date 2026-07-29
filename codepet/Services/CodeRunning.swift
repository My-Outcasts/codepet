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

    func run(prompt: String, workingDir: String) async -> CodeRunOutcome {
        // A FRESH runner per call: reusing one instance would replay its last
        // `.finished` on the new subscription (resuming instantly with stale diffs
        // and orphaning the new subprocess). The local `runner` is retained by the
        // sink closure (held by `cancellable`, captured by the continuation) until
        // the run resolves, then released. A fresh runner starts `.idle`, so the
        // replayed initial value is ignored by the switch below.
        let runner = ClaudeCodeRunner()
        var cancellable: AnyCancellable?
        return await withCheckedContinuation { (cont: CheckedContinuation<CodeRunOutcome, Never>) in
            var resumed = false
            let finish: (CodeRunOutcome) -> Void = { outcome in
                guard !resumed else { return }
                resumed = true
                cancellable?.cancel()
                cancellable = nil
                cont.resume(returning: outcome)
            }
            cancellable = runner.$state.sink { state in
                switch state {
                case .finished:
                    // Diffs are guaranteed published before `.finished` (see
                    // ClaudeCodeRunner.computeDiffs), so this read is complete.
                    finish(CodeRunOutcome(diffs: runner.fileDiffs, failure: nil))
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

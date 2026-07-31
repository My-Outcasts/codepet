import Foundation

/// Maps the coding runner's stream events to display steps for the run card.
/// Only tool-use events (Edit/Write/Bash/Read/…) become steps; system meta,
/// plain assistant prose, tool results, and the final summary are not shown as
/// checklist rows. Each surfaced step is already `done` (the tool call completed).
enum CodeExecSteps {
    static func step(for event: ClaudeCodeRunner.StreamEvent) -> ExecStep? {
        switch event.kind {
        case .toolUse:
            let label = event.text.trimmingCharacters(in: .whitespacesAndNewlines)
            return label.isEmpty ? nil : ExecStep(label: label, done: true)
        default:
            return nil
        }
    }
}

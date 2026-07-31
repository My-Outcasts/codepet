// codepet/Models/ExecStep.swift
import Foundation

/// One line in a run's execute-log — the "how the agent is working" transparency
/// shown while a task runs. `done` flips as the step completes.
struct ExecStep: Identifiable, Equatable, Codable {
    let id: String
    let label: String
    var done: Bool
    init(id: String = UUID().uuidString, label: String, done: Bool = false) {
        self.id = id; self.label = label; self.done = done
    }
}

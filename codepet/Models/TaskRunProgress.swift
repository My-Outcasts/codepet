import Foundation

/// One task run in flight, for the surfaces outside chat.
///
/// Chat carries its run on a `CopilotMessage` (`execSteps` + `companionId` + `deptName`), which
/// works because a chat run belongs to a turn. A run started from a CARD belongs to the card, so
/// it is keyed by task id in `CompanyStore.taskRuns` instead and every surface showing that task
/// can render the same agent — the Tasks board, a department, a roadmap card, the beacon.
struct TaskRunProgress: Equatable, Identifiable {
    let taskId: String
    /// The department's pet. `nil` only for a task with no department, or a department with no
    /// character mapped (`product` today).
    let companionId: String?
    let deptName: String?
    var steps: [ExecStep]

    var id: String { taskId }

    /// The step being worked — the first not-yet-done one. `nil` once every step has landed.
    var currentStep: ExecStep? { steps.first { !$0.done } }
    var doneCount: Int { steps.filter(\.done).count }
}

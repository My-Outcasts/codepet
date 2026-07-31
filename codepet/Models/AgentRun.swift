// codepet/Models/AgentRun.swift
import Foundation

/// Status of one concurrent department-agent run.
enum AgentRunStatus: String, Equatable, Codable, CaseIterable {
    case working, reviewing, done, failed

    func label(_ lang: AppLanguage) -> String {
        switch (self, lang) {
        case (.working, .vi):   return "Đang làm"
        case (.working, _):     return "Working"
        case (.reviewing, .vi): return "Đang duyệt"
        case (.reviewing, _):   return "Reviewing"
        case (.done, .vi):      return "Xong"
        case (.done, _):        return "Done"
        case (.failed, .vi):    return "Lỗi"
        case (.failed, _):      return "Failed"
        }
    }
}

/// One department agent working on a task, for the inline multi-agent exec-log.
/// A multi-agent analogue of what `ExecLogRow` shows for a single run.
struct AgentRun: Identifiable, Equatable {
    let id: String
    let companionId: String   // resolves avatar + accent via PetCharacter.all
    let deptName: String      // "Engineering", "Design", …
    let taskTitle: String
    var steps: [ExecStep]     // reuses the existing ExecStep type
    var status: AgentRunStatus
    let startedAt: Date       // for elapsed display

    init(id: String = UUID().uuidString, companionId: String, deptName: String,
         taskTitle: String, steps: [ExecStep], status: AgentRunStatus, startedAt: Date) {
        self.id = id
        self.companionId = companionId
        self.deptName = deptName
        self.taskTitle = taskTitle
        self.steps = steps
        self.status = status
        self.startedAt = startedAt
    }

    /// "4/7" — done steps over total.
    var stepCounter: String { "\(steps.filter { $0.done }.count)/\(steps.count)" }

    /// The first not-done step (the spinning one); nil when all are done.
    var currentStepIndex: Int? { steps.firstIndex { !$0.done } }

    /// "m:ss" elapsed since `startedAt`. `now` is injected so it is testable and
    /// preview-stable (no `Date()` read inside the view).
    func elapsedString(now: Date) -> String {
        let secs = max(0, Int(now.timeIntervalSince(startedAt)))
        return String(format: "%d:%02d", secs / 60, secs % 60)
    }
}

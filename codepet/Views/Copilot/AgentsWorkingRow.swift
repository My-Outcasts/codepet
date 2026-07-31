import SwiftUI

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

/// Inline, in-chat view of MULTIPLE department agents working at once — a
/// multi-agent sibling of `ExecLogRow`, modeled on Codex's run list. One card
/// holds a stacked row per active agent; left-aligned like a companion message.
struct AgentsWorkingRow: View {
    let runs: [AgentRun]
    /// Injected clock for elapsed display — stable in previews/tests.
    var now: Date = Date()

    @Environment(\.uiLanguage) private var lang

    var body: some View {
        HStack {
            MessageCard(hue: CodepetTheme.accentPurple) {
                VStack(alignment: .leading, spacing: 12) {
                    Text((lang == .vi ? "Đang làm việc" : "Agents at work")
                            + " · \(runs.count)")
                        .font(CodepetTheme.inter(10, weight: .semibold))
                        .tracking(0.5)
                        .foregroundColor(CodepetTheme.mutedText)
                    ForEach(Array(runs.enumerated()), id: \.element.id) { idx, run in
                        if idx > 0 { Divider().overlay(CodepetTheme.hairline) }
                        agentRow(run)
                    }
                }
            }
            Spacer(minLength: 24)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private func agentRow(_ run: AgentRun) -> some View {
        let persona = PetCharacter.all[run.companionId]
        let accent = persona?.color ?? CodepetTheme.accentPurple
        let name = persona?.name ?? "Codepet"
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 8) {
                CompanionAvatar(companionId: run.companionId, size: 22,
                                isWorking: run.status == .working)
                Text("\(name) · \(run.deptName)")
                    .font(CodepetTheme.inter(13, weight: .semibold))
                    .foregroundColor(accent)
                Spacer(minLength: 8)
                statusPill(run.status)
                Text(run.elapsedString(now: now))
                    .font(CodepetTheme.inter(11))
                    .foregroundColor(CodepetTheme.mutedText)
                Text(run.stepCounter)
                    .font(CodepetTheme.inter(11, weight: .medium))
                    .foregroundColor(CodepetTheme.mutedText)
            }
            Text(run.taskTitle)
                .font(CodepetTheme.inter(14))
                .foregroundColor(CodepetTheme.primaryText)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(Array(run.steps.enumerated()), id: \.element.id) { idx, step in
                HStack(spacing: 8) {
                    stepIcon(done: step.done, isCurrent: idx == run.currentStepIndex)
                        .frame(width: 15, height: 15)
                    Text(step.label)
                        .font(CodepetTheme.inter(12))
                        .foregroundColor(step.done ? CodepetTheme.bodyText
                            : (idx == run.currentStepIndex ? CodepetTheme.primaryText
                                                           : CodepetTheme.mutedText))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func statusPill(_ status: AgentRunStatus) -> some View {
        let fg: Color
        let bg: Color
        switch status {
        case .working:   fg = CodepetTheme.accentPurple; bg = CodepetTheme.accentPurple.opacity(0.14)
        case .reviewing: fg = CodepetTheme.accentGold;   bg = CodepetTheme.accentGold.opacity(0.16)
        case .done:      fg = CodepetTheme.accentTeal;   bg = CodepetTheme.accentTeal.opacity(0.16)
        case .failed:    fg = Color.red;                 bg = Color.red.opacity(0.14)
        }
        return Text(status.label(lang))
            .font(CodepetTheme.inter(10, weight: .semibold))
            .foregroundColor(fg)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(Capsule().fill(bg))
    }

    // Mirrors ExecLogRow's step icon: done → teal check, current → spinner, else dim ring.
    @ViewBuilder private func stepIcon(done: Bool, isCurrent: Bool) -> some View {
        if done {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 13)).foregroundColor(CodepetTheme.accentTeal)
        } else if isCurrent {
            ProgressView().controlSize(.small).scaleEffect(0.7)
        } else {
            Image(systemName: "circle")
                .font(.system(size: 12)).foregroundColor(CodepetTheme.mutedText.opacity(0.45))
        }
    }
}

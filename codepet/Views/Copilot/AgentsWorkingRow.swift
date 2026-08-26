import SwiftUI

/// Inline, in-chat view of MULTIPLE department agents working at once — a
/// multi-agent sibling of `ExecLogRow`, modeled on Codex's run list. One card
/// holds a stacked row per active agent; left-aligned like a companion message.
///
/// DOCK ADAPTATION (380pt): PR #39's full-width chat version put avatar,
/// name·dept, status pill, elapsed, AND step counter all on a single line.
/// That doesn't fit at the 380pt dock width, so each `agentRow` here splits
/// into two lines — avatar + Name·Dept + status pill on top, elapsed + step
/// counter below — and the task title is line-limited so a long title can't
/// blow out the row. `AgentRun`'s math (`elapsedString`, `stepCounter`,
/// `currentStepIndex`) is untouched; only this view's layout changed.
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
        VStack(alignment: .leading, spacing: 4) {
            // Line 1: avatar + Name·Dept + status pill.
            HStack(alignment: .center, spacing: 8) {
                CompanionAvatar(companionId: run.companionId, size: 20,
                                isWorking: run.status == .working)
                Text("\(name) · \(run.deptName)")
                    .font(CodepetTheme.inter(12, weight: .semibold))
                    .foregroundColor(accent)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 6)
                statusPill(run.status)
            }
            // Line 2: elapsed + step counter (moved off line 1 to fit 380pt).
            HStack(spacing: 6) {
                Text(run.elapsedString(now: now))
                    .font(CodepetTheme.inter(11))
                    .foregroundColor(CodepetTheme.mutedText)
                Text("·")
                    .font(CodepetTheme.inter(11))
                    .foregroundColor(CodepetTheme.mutedText)
                Text(run.stepCounter)
                    .font(CodepetTheme.inter(11, weight: .medium))
                    .foregroundColor(CodepetTheme.mutedText)
            }
            Text(run.taskTitle)
                .font(CodepetTheme.inter(13))
                .foregroundColor(CodepetTheme.primaryText)
                .lineLimit(2)
                .truncationMode(.tail)
            ForEach(Array(run.steps.enumerated()), id: \.element.id) { idx, step in
                HStack(spacing: 6) {
                    stepIcon(done: step.done, isCurrent: idx == run.currentStepIndex)
                        .frame(width: 13, height: 13)
                    Text(step.label)
                        .font(CodepetTheme.inter(11))
                        .foregroundColor(step.done ? CodepetTheme.bodyText
                            : (idx == run.currentStepIndex ? CodepetTheme.primaryText
                                                           : CodepetTheme.mutedText))
                        .lineLimit(1)
                        .truncationMode(.tail)
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
            .font(CodepetTheme.inter(9, weight: .semibold))
            .foregroundColor(fg)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(Capsule().fill(bg))
    }

    // Mirrors ExecLogRow's step icon: done → teal check, current → spinner, else dim ring.
    @ViewBuilder private func stepIcon(done: Bool, isCurrent: Bool) -> some View {
        if done {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 12)).foregroundColor(CodepetTheme.accentTeal)
        } else if isCurrent {
            ProgressView().controlSize(.small).scaleEffect(0.6)
        } else {
            Image(systemName: "circle")
                .font(.system(size: 11)).foregroundColor(CodepetTheme.mutedText.opacity(0.45))
        }
    }
}

#if DEBUG
#Preview("AgentsWorkingRow — dock (380pt)") {
    let now = Date()
    let runs = [
        AgentRun(companionId: "nova", deptName: "Frontend",
                 taskTitle: "Rebuild the pricing page hero section with the new companion accent",
                 steps: [ExecStep(label: "Read pricing.tsx", done: true),
                         ExecStep(label: "Draft new hero layout", done: false),
                         ExecStep(label: "Wire accent theming", done: false)],
                 status: .working, startedAt: now.addingTimeInterval(-95)),
        AgentRun(companionId: "crash", deptName: "Backend",
                 taskTitle: "Add retry logic to the billing webhook",
                 steps: [ExecStep(label: "Read webhook handler", done: true),
                         ExecStep(label: "Add retry + backoff", done: true)],
                 status: .reviewing, startedAt: now.addingTimeInterval(-210)),
        AgentRun(companionId: "nova", deptName: "Marketing",
                 taskTitle: "Draft the W1 roadmap update",
                 steps: [ExecStep(label: "Summarize shipped items", done: true)],
                 status: .done, startedAt: now.addingTimeInterval(-300)),
    ]
    return ScrollView {
        AgentsWorkingRow(runs: runs, now: now)
            .padding()
    }
    .frame(width: 380, height: 520)
    .environmentObject(CompanyStore())
}
#endif

import SwiftUI

/// The run "execute-log" — how the agent is working, styled like the web: the
/// specialist's pet avatar + name, then a titled card ("<task>" / "DEPT") with a
/// "<Name> is doing the work…" header + an honest "N steps" counter, over a live
/// checklist. Done steps get a teal check, the current step spins, pending sit dim.
struct ExecLogRow: View {
    let taskTitle: String
    let deptName: String?
    let steps: [ExecStep]
    /// The specialist working (department handoff); nil → the global/host companion.
    var companionId: String? = nil

    @EnvironmentObject private var companyStore: CompanyStore

    private var resolvedId: String { companionId ?? companyStore.company.companionId }
    private var persona: PetCharacter? { PetCharacter.all[resolvedId] }
    private var name: String { persona?.name ?? "Codepet" }
    // The web's producing card uses the brand violet throughout (kicker, checks,
    // spinner, border) regardless of the specialist's department color.
    private var accent: Color { CodepetTheme.accentPurple }

    var body: some View {
        HStack {
            card
            Spacer(minLength: 24)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Title + "DEPT" kicker in the brand accent (web: "<task>" / "DEPT · TYPE").
            VStack(alignment: .leading, spacing: 3) {
                Text(taskTitle)
                    .font(CodepetTheme.inter(16.5, weight: .semibold))
                    .foregroundColor(CodepetTheme.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
                Text((deptName ?? "Codepet").uppercased())
                    .font(CodepetTheme.inter(11, weight: .semibold))
                    .tracking(0.6)
                    .foregroundColor(accent)
            }
            // Status sub-bar: spinner + "<Name> is doing the work…" + step count.
            HStack(spacing: 8) {
                ProgressView().controlSize(.small).scaleEffect(0.7).tint(accent)
                    .frame(width: 16, height: 16)
                Text("\(name) is doing the work…")
                    .font(CodepetTheme.inter(14.5, weight: .semibold))
                    .foregroundColor(CodepetTheme.primaryText)
                Spacer(minLength: 8)
                Text("\(steps.count) steps")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(CodepetTheme.mutedText)
            }
            .padding(.horizontal, 10).padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(CodepetTheme.pageBackground.opacity(0.6)))
            // Step checklist: violet check (done), amber dot (a "Checkpoint" step),
            // dim ring (pending).
            VStack(alignment: .leading, spacing: 7) {
                ForEach(steps) { step in stepRow(step) }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(CodepetTheme.surface))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
            .stroke(accent.opacity(0.35), lineWidth: 1))
    }

    @ViewBuilder private func stepRow(_ step: ExecStep) -> some View {
        let isCheckpoint = step.label.lowercased().hasPrefix("checkpoint")
        HStack(alignment: .top, spacing: 8) {
            Group {
                if isCheckpoint {
                    Circle().fill(CodepetTheme.accentGold).frame(width: 10, height: 10)
                } else if step.done {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 14)).foregroundColor(accent)
                } else {
                    Image(systemName: "circle")
                        .font(.system(size: 13)).foregroundColor(CodepetTheme.mutedText.opacity(0.45))
                }
            }
            .frame(width: 16, height: 16)
            Text(step.label)
                .font(CodepetTheme.inter(14))
                .foregroundColor(isCheckpoint ? CodepetTheme.accentGold
                                 : (step.done ? CodepetTheme.bodyText : CodepetTheme.mutedText))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

#if DEBUG
#Preview("ExecLogRow") {
    ExecLogRow(taskTitle: "Draft your positioning statement", deptName: "Marketing", steps: [
        ExecStep(label: "Reading your brief — mission, audience, your voice", done: true),
        ExecStep(label: "Pulling in the Marketing playbook", done: true),
        ExecStep(label: "Drafting Draft your positioning statement", done: false),
        ExecStep(label: "Matching your tone and past decisions", done: false),
    ], companionId: "nova")
    .padding(40)
    .environmentObject(CompanyStore())
}
#endif

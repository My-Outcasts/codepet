import SwiftUI

/// The run "execute-log": a breathing specialist orb + a live checklist of the
/// steps the agent is working through, so the founder can see HOW a deliverable
/// is being produced (not just a spinner). Done steps get a teal check, the
/// current step spins, pending steps sit dim. Replaces the plain producing row
/// when the run carries `execSteps`.
struct ExecLogRow: View {
    let steps: [ExecStep]
    /// The specialist working (department handoff); nil → the global companion.
    var companionId: String? = nil

    private var currentIndex: Int? { steps.firstIndex { !$0.done } }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            CompanionOrb(size: 28, glow: false, isWorking: true, companionId: companionId)
            VStack(alignment: .leading, spacing: 7) {
                ForEach(Array(steps.enumerated()), id: \.element.id) { idx, step in
                    HStack(spacing: 8) {
                        icon(done: step.done, isCurrent: idx == currentIndex)
                            .frame(width: 15, height: 15)
                        Text(step.label)
                            .font(CodepetTheme.inter(13))
                            .foregroundColor(step.done ? CodepetTheme.bodyText
                                             : (idx == currentIndex ? CodepetTheme.primaryText : CodepetTheme.mutedText))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            Spacer(minLength: 24)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private func icon(done: Bool, isCurrent: Bool) -> some View {
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

#if DEBUG
#Preview("ExecLogRow") {
    ExecLogRow(steps: [
        ExecStep(label: "Reading your brief and 3 decisions", done: true),
        ExecStep(label: "Applying Marketing expertise", done: true),
        ExecStep(label: "Drafting Write landing copy", done: false),
        ExecStep(label: "Reviewing the draft", done: false),
    ])
    .padding(40)
    .environmentObject(CompanyStore())
}
#endif

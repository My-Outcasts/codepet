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
    private var accent: Color { persona?.color ?? CodepetTheme.accentPurple }
    private var currentIndex: Int? { steps.firstIndex { !$0.done } }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            CompanionAvatar(companionId: companionId, size: 28, isWorking: true)
            VStack(alignment: .leading, spacing: 6) {
                Text(name)
                    .font(CodepetTheme.inter(13, weight: .semibold))
                    .foregroundColor(accent)
                card
            }
            Spacer(minLength: 24)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var card: some View {
        MessageCard(hue: accent) {
            VStack(alignment: .leading, spacing: 8) {
                // Title + department kicker (matches the web's "<task>" / "DEPT").
                VStack(alignment: .leading, spacing: 2) {
                    Text(taskTitle)
                        .font(CodepetTheme.inter(15, weight: .semibold))
                        .foregroundColor(CodepetTheme.primaryText)
                        .fixedSize(horizontal: false, vertical: true)
                    Text((deptName ?? "Codepet").uppercased())
                        .font(CodepetTheme.inter(10, weight: .semibold))
                        .tracking(0.5)
                        .foregroundColor(CodepetTheme.mutedText)
                }
                Divider().overlay(CodepetTheme.hairline)
                // "<Name> is doing the work…" + honest step counter.
                HStack(spacing: 8) {
                    Text("\(name) is doing the work…")
                        .font(CodepetTheme.inter(13, weight: .medium))
                        .foregroundColor(CodepetTheme.bodyText)
                    Spacer(minLength: 8)
                    Text("\(steps.count) steps")
                        .font(CodepetTheme.inter(11))
                        .foregroundColor(CodepetTheme.mutedText)
                }
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
        }
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

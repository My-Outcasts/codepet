import SwiftUI

/// The run "execute-log" — how the agent is working, styled like the web: a
/// titled card ("<task>" / "DEPT") with a "<Name> is doing the work…" header +
/// an honest "N steps" counter, over a live checklist. Done steps get a violet
/// check, a "Checkpoint" step gets an amber dot, pending steps sit dim.
///
/// DOCK ADAPTATION (380pt): ported from PR #39's full-width chat card. That
/// version free-floated its own `RoundedRectangle` surface + border; here it's
/// wrapped in the shared `MessageCard` (hue-tinted surface + same-hue border)
/// so it matches every other card in the dock chat (see `AgentsWorkingRow`,
/// the multi-agent sibling this view was built to pair with). Title and step
/// labels keep `.fixedSize(horizontal: false, vertical: true)` so they wrap
/// instead of clipping at the narrow dock width; the status sub-bar's step
/// counter is line-limited so a long companion name can't push it off-card.
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
            MessageCard(hue: accent) { card }
            Spacer(minLength: 24)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Title + "DEPT" kicker in the brand accent (web: "<task>" / "DEPT · TYPE").
            VStack(alignment: .leading, spacing: 3) {
                Text(taskTitle)
                    .font(CodepetTheme.inter(15.5, weight: .semibold))
                    .foregroundColor(CodepetTheme.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
                Text((deptName ?? "Codepet").uppercased())
                    .font(CodepetTheme.inter(11, weight: .semibold))
                    .tracking(0.6)
                    .foregroundColor(accent)
            }
            // Status sub-bar: spinner + "<Name> is doing the work…" + step count.
            // Wraps to two lines at the dock width rather than clipping the label.
            HStack(alignment: .top, spacing: 8) {
                ProgressView().controlSize(.small).scaleEffect(0.7).tint(accent)
                    .frame(width: 16, height: 16)
                Text("\(name) is doing the work…")
                    .font(CodepetTheme.inter(13.5, weight: .semibold))
                    .foregroundColor(CodepetTheme.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 6)
                Text("\(steps.count) steps")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(CodepetTheme.mutedText)
                    .lineLimit(1)
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
                .font(CodepetTheme.inter(13.5))
                .foregroundColor(isCheckpoint ? CodepetTheme.accentGold
                                 : (step.done ? CodepetTheme.bodyText : CodepetTheme.mutedText))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

#if DEBUG
#Preview("ExecLogRow — dock (380pt)") {
    ScrollView {
        ExecLogRow(taskTitle: "Draft your positioning statement", deptName: "Marketing", steps: [
            ExecStep(label: "Reading your brief — mission, audience, your voice", done: true),
            ExecStep(label: "Pulling in the Marketing playbook", done: true),
            ExecStep(label: "Drafting your positioning statement so it reads like it came from your team",
                     done: false),
            ExecStep(label: "Checkpoint: confirm tone before this goes out", done: false),
        ], companionId: "nova")
        .padding()
    }
    .frame(width: 380, height: 520)
    .environmentObject(CompanyStore())
}
#endif

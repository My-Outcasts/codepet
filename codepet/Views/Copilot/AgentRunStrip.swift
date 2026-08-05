import SwiftUI

/// The agent working, shown on the card the founder pressed.
///
/// A compact sibling of `ExecLogRow`: same script, same pacing, same department character — but
/// sized for a task card rather than a chat transcript, because it appears inside the Tasks
/// board, a department row, a roadmap card and the Overview beacon. `ExecLogRow` stays the chat
/// version; this is the one for everywhere else.
///
/// Deliberately one line of status plus a progress rail rather than the full checklist. A task
/// card is a list item — a six-row log inside one would push its siblings off screen — and the
/// founder pressing Run on a card wants to know it started, who has it, and roughly how far it
/// is. The full log is one tap away afterwards on the deliverable ("What Nova did · N steps").
struct AgentRunStrip: View {
    let progress: TaskRunProgress

    @Environment(\.uiLanguage) private var lang

    private var pet: PetCharacter? { progress.companionId.flatMap { PetCharacter.all[$0] } }
    private var accent: Color { pet?.color ?? CodepetTheme.accentPurple }

    /// "Nova · Marketing is on it" — the department's character, named. Falls back to the product
    /// when a task has no department, or a department has no pet mapped (`product` today), rather
    /// than inventing a character for it.
    private var who: String {
        guard let pet else { return CodepetBrand.name }
        guard let dept = progress.deptName, !dept.isEmpty else { return pet.name }
        return "\(pet.name) · \(dept)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 7) {
                CompanionAvatar(companionId: progress.companionId, size: 18)
                Text(who)
                    .font(CodepetTheme.inter(11.5, weight: .semibold))
                    .foregroundColor(CodepetTheme.primaryText)
                Text(lang == .vi ? "đang làm" : "is on it")
                    .font(CodepetTheme.inter(11))
                    .foregroundColor(CodepetTheme.mutedText)
                Spacer(minLength: 6)
                Text("\(progress.doneCount)/\(progress.steps.count)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(CodepetTheme.mutedText)
                    .monospacedDigit()
            }
            // The step being worked, by name — the whole point of the transparency: the founder
            // sees WHAT is happening, not just that something is.
            if let step = progress.currentStep {
                Text(step.label)
                    .font(step.kind == .mono ? .system(size: 10.5, design: .monospaced)
                                             : CodepetTheme.inter(11))
                    .foregroundColor(step.kind == .checkpoint ? CodepetTheme.accentGold
                                                              : CodepetTheme.mutedText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .transition(.opacity)
            }
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(CodepetTheme.hairline.opacity(0.6))
                    Capsule().fill(accent)
                        .frame(width: g.size.width * fraction)
                }
            }
            .frame(height: 3)
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(accent.opacity(0.10)))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
            .stroke(accent.opacity(0.45), lineWidth: 1))
        .animation(.easeOut(duration: 0.2), value: progress.doneCount)
    }

    /// Never 0 — a rail with nothing in it reads as stalled — and never 1 until the run is
    /// actually finished, so the last step doesn't claim completion before the deliverable lands.
    private var fraction: CGFloat {
        guard !progress.steps.isEmpty else { return 0.08 }
        return max(0.08, CGFloat(progress.doneCount) / CGFloat(progress.steps.count))
    }
}

#if DEBUG
#Preview("AgentRunStrip") {
    VStack(spacing: 12) {
        AgentRunStrip(progress: TaskRunProgress(
            taskId: "t", companionId: "nova", deptName: "Marketing",
            steps: [ExecStep(label: "Reading your brief — mission, audience, your voice", done: true),
                    ExecStep(label: "Pulling in the Marketing playbook", done: true),
                    ExecStep(label: "Drafting Write your landing page copy …"),
                    ExecStep(label: "Checkpoint — sanity-checked claims", kind: .checkpoint),
                    ExecStep(label: "Writing the deliverable ↓")]))
        AgentRunStrip(progress: TaskRunProgress(
            taskId: "u", companionId: "crash", deptName: "Engineering",
            steps: [ExecStep(label: "Reading project context", done: true),
                    ExecStep(label: "claude  edited CompanyStore.swift  +34 −11", kind: .mono)]))
    }
    .frame(width: 320)
    .padding()
    .environmentObject(CompanyStore())
}
#endif

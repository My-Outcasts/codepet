// codepet/Views/Onboarding/OnboardingRevealView.swift
import SwiftUI

/// Step 7 — the reveal. Task-based (native has no departments); falls back to the
/// generic value-props when the fail-open scaffold produced nothing (`!reveal.ok`).
struct OnboardingRevealView: View {
    let name: String
    let roleLabel: String
    let stageIndex: Int
    let reveal: OnboardingReveal

    private var role: String { (roleLabel.isEmpty ? "founder" : roleLabel).lowercased() }
    private var stage: String { OnboardingContent.stages[stageIndex].lowercased() }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Here's your company\(name.isEmpty ? "" : ", \(name)").")
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(CodepetTheme.primaryText)
            (Text("You're a ") + Text(role).bold()
             + Text(" at the ") + Text(stage).bold()
             + Text(reveal.ok && reveal.taskCount > 0
                    ? " stage. I built your roadmap — \(reveal.taskCount) tasks already prepped:"
                    : " stage. I built your roadmap and staffed your departments — here's what I'll take off your plate:"))
                .font(CodepetTheme.body(14)).foregroundColor(CodepetTheme.bodyText)
                .padding(.top, 9)

            VStack(alignment: .leading, spacing: 9) {
                if reveal.ok && !reveal.sampleTasks.isEmpty {
                    ForEach(reveal.sampleTasks, id: \.self) { title in
                        valueRow(title, bold: true)
                    }
                } else {
                    valueRow("A living roadmap", suffix: " — staged from \"\(OnboardingContent.stages[stageIndex])\" to launch.")
                    valueRow("Real work, done with you", suffix: " — tasks prepped across your departments.")
                    valueRow("You stay in control", suffix: " — I draft & build; you approve.")
                }
            }
            .padding(.top, 16)
        }
    }

    private func valueRow(_ head: String, suffix: String = "", bold: Bool = false) -> some View {
        HStack(alignment: .top, spacing: 11) {
            Text("✦")
                .font(.system(size: 11))
                .foregroundColor(OnboardingContent.Palette.accentDeep)
                .frame(width: 26, height: 26)
                .background(RoundedRectangle(cornerRadius: 8).fill(OnboardingContent.Palette.accentTint))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(OnboardingContent.Palette.accentLine, lineWidth: 1))
            (Text(head).bold().foregroundColor(CodepetTheme.primaryText) + Text(suffix).foregroundColor(CodepetTheme.bodyText))
                .font(CodepetTheme.body(13))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

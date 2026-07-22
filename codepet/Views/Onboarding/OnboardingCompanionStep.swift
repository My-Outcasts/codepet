// codepet/Views/Onboarding/OnboardingCompanionStep.swift
import SwiftUI

/// Onboarding step 8 — pick the companion that rides along for the project.
/// Reuses the native PetCharacter roster; the selected one is highlighted with
/// its accent. Matches the web's "Choose your companion." step.
struct OnboardingCompanionStep: View {
    @Binding var pickedId: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Choose your companion.")
                .font(CodepetTheme.body(20, weight: .semibold))
                .foregroundColor(CodepetTheme.primaryText)
            Text("Pick who'll accompany you as you build. You can change this anytime in the sidebar.")
                .font(CodepetTheme.body(14)).foregroundColor(CodepetTheme.bodyText)
                .padding(.top, 9)

            ChipFlowLayout(spacing: 12) {
                ForEach(PetCharacter.starters, id: \.self) { id in
                    let c = PetCharacter.all[id]
                    let sel = pickedId == id
                    let accent = c?.color ?? CodepetTheme.accentPurple
                    Button { pickedId = id } label: {
                        VStack(spacing: 6) {
                            CharacterImage(id, size: 44)
                            Text(c?.name ?? id)
                                .font(CodepetTheme.body(11, weight: .medium))
                                .foregroundColor(sel ? accent : CodepetTheme.mutedText)
                        }
                        .fixedSize()
                        .padding(10)
                        .background(RoundedRectangle(cornerRadius: 12)
                            .fill(sel ? accent.opacity(0.14) : CodepetTheme.surface))
                        .overlay(RoundedRectangle(cornerRadius: 12)
                            .stroke(sel ? accent : CodepetTheme.hairline, lineWidth: sel ? 2 : 1))
                    }.buttonStyle(.plain)
                }
            }
            .padding(.top, 18)
        }
    }
}

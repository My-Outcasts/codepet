// codepet/Views/Onboarding/OnboardingAnalysisView.swift
import SwiftUI

/// Step 6 body — "Codepet is reading {project}…" with streaming analysis lines.
/// The controller drives `shown` (how many lines revealed) and `done`.
struct OnboardingAnalysisView: View {
    let projectName: String
    let shown: Int
    let done: Bool
    @State private var spin = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Codepet is reading \(projectName.isEmpty ? "your project" : projectName)…")
                .font(CodepetTheme.body(20, weight: .semibold))
                .foregroundColor(CodepetTheme.primaryText)
            Text("Turning what you told me into a full company plan.")
                .font(CodepetTheme.body(14)).foregroundColor(CodepetTheme.bodyText)
                .padding(.top, 9)

            VStack(alignment: .leading, spacing: 0) {
                ForEach(0..<max(0, min(shown, OnboardingContent.analysisLines.count)), id: \.self) { i in
                    let live = !done && i == shown - 1
                    HStack(spacing: 10) {
                        ZStack {
                            if live {
                                Circle().stroke(OnboardingContent.Palette.accentLine, lineWidth: 2)
                                    .frame(width: 16, height: 16)
                                Circle().trim(from: 0, to: 0.25)
                                    .stroke(CodepetTheme.accentPurple, lineWidth: 2)
                                    .frame(width: 16, height: 16)
                                    .rotationEffect(.degrees(spin ? 360 : 0))
                            } else {
                                Circle().fill(CodepetTheme.accentPurple).frame(width: 16, height: 16)
                                Image(systemName: "checkmark").font(.system(size: 9, weight: .bold)).foregroundColor(.white)
                            }
                        }
                        Text(OnboardingContent.analysisLines[i])
                            .font(CodepetTheme.body(13)).foregroundColor(CodepetTheme.mutedText)
                    }
                    .padding(.vertical, 6)
                }
            }
            .padding(.top, 8)
        }
        .onAppear {
            guard !reduceMotion else { return }   // leave the ring static under Reduce Motion
            withAnimation(.linear(duration: 0.7).repeatForever(autoreverses: false)) { spin = true }
        }
    }
}

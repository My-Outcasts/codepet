// codepet/Views/Onboarding/OnboardingOptionList.swift
import SwiftUI

/// Numbered single-select list (web `.obopts`/`.obopt`), used by the role and
/// tech steps. Selection is by stable key.
struct OnboardingOptionList: View {
    let options: [(label: String, key: String)]
    @Binding var selectedKey: String

    var body: some View {
        VStack(spacing: 8) {
            ForEach(Array(options.enumerated()), id: \.offset) { i, opt in
                let sel = selectedKey == opt.key
                Button { selectedKey = opt.key } label: {
                    HStack(spacing: 13) {
                        Text(String(format: "%02d", i + 1))
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(sel ? OnboardingContent.Palette.accentDeep : OnboardingContent.Palette.faint)
                            .frame(width: 16, alignment: .leading)
                        Text(opt.label)
                            .font(CodepetTheme.body(14))
                            .fontWeight(.medium)
                            .foregroundColor(CodepetTheme.primaryText)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        ZStack {
                            Circle()
                                .stroke(sel ? Color.clear : CodepetTheme.hairline, lineWidth: 1.5)
                                .background(Circle().fill(sel ? CodepetTheme.accentPurple : Color.clear))
                                .frame(width: 20, height: 20)
                            if sel {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(.white)
                            }
                        }
                    }
                    .padding(.horizontal, 15)
                    .padding(.vertical, 12)
                    .background(RoundedRectangle(cornerRadius: 12)
                        .fill(sel ? OnboardingContent.Palette.accentTint : CodepetTheme.surface))
                    .overlay(RoundedRectangle(cornerRadius: 12)
                        .stroke(sel ? CodepetTheme.accentPurple : CodepetTheme.hairline, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

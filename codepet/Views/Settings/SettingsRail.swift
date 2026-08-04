// codepet/Views/Settings/SettingsRail.swift
import SwiftUI

/// The modal's fixed 220pt nav column. Carries its own "Settings" title and never
/// scrolls, so the founder always sees where they are.
struct SettingsRail: View {
    @Binding var selection: SettingsSection
    @Environment(\.uiLanguage) private var lang

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(lang == .vi ? "Cài đặt" : "Settings")
                .font(CodepetTheme.inter(14, weight: .semibold))
                .foregroundColor(CodepetTheme.primaryText)
                .padding(.horizontal, 12)
                .padding(.top, 18)
                .padding(.bottom, 10)

            ForEach(SettingsSection.allCases) { section in
                Button { selection = section } label: {
                    HStack(spacing: 10) {
                        Image(systemName: section.icon)
                            .font(.system(size: 12))
                            .frame(width: 16)
                        Text(section.title(lang))
                            .font(CodepetTheme.inter(13, weight: .medium))
                        Spacer(minLength: 0)
                    }
                    .foregroundColor(selection == section
                                     ? CodepetTheme.primaryText
                                     : CodepetTheme.bodyText)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(selection == section
                                  ? CodepetTheme.hairline
                                  : Color.clear)
                    )
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .frame(width: ShellLayout.settingsRailWidth, alignment: .leading)
    }
}

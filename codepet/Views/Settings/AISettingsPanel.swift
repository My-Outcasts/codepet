// codepet/Views/Settings/AISettingsPanel.swift
import SwiftUI

/// How the founder's team talks to them. Deliberately no "Headers & Lists" knob:
/// `companyChatCore.ts` tells the companion to write plain text because the chat
/// transcript has no markdown renderer, so a structure setting would print literal
/// asterisks into replies.
///
/// The dropdowns commit immediately on change (one Firestore write per change). The
/// three text fields commit on Return or on leaving the panel, never per keystroke —
/// same commit-on-blur policy as `PreferencesPanel`'s Preferred Name field, so the two
/// panels behave the same way and neither drops an edit when the founder just clicks ✕.
struct AISettingsPanel: View {
    @EnvironmentObject var companyStore: CompanyStore
    @Environment(\.uiLanguage) private var lang

    @State private var style = AIStyle()
    @State private var loaded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            SettingsGroup {
                SettingsRow(
                    label: lang == .vi ? "Giọng điệu cơ bản" : "Base style and tone",
                    description: lang == .vi
                        ? "Cách đội của bạn trả lời. Không ảnh hưởng khả năng."
                        : "How your team answers. Doesn't change what they can do."
                ) {
                    Picker("", selection: $style.baseTone) {
                        Text(lang == .vi ? "Mặc định" : "Default").tag(AIStyle.BaseTone.default)
                        Text(lang == .vi ? "Thẳng thắn" : "Direct").tag(AIStyle.BaseTone.direct)
                        Text(lang == .vi ? "Động viên" : "Encouraging").tag(AIStyle.BaseTone.encouraging)
                        Text(lang == .vi ? "Phân tích" : "Analytical").tag(AIStyle.BaseTone.analytical)
                    }
                    .labelsHidden().frame(width: 160)
                }
            }

            SettingsGroupLabel(lang == .vi ? "Đặc điểm" : "Characteristics")
            SettingsGroup {
                levelRow(lang == .vi ? "Ấm áp" : "Warm", $style.warmth)
                SettingsDivider()
                levelRow(lang == .vi ? "Nhiệt tình" : "Enthusiastic", $style.enthusiasm)
                SettingsDivider()
                levelRow("Emoji", $style.emoji)
            }

            SettingsGroupLabel(lang == .vi ? "Về bạn" : "About you")
            SettingsGroup {
                SettingsRow(label: lang == .vi ? "Vai trò" : "Role") {
                    field($style.role, placeholder: lang == .vi ? "nhà sáng lập" : "solo founder")
                }
                SettingsDivider()
                SettingsRow(
                    label: lang == .vi ? "Thêm về bạn" : "More about you",
                    description: lang == .vi ? "Sở thích, giá trị, điều cần nhớ."
                                             : "Interests, values, or preferences to keep in mind."
                ) {
                    field($style.moreAboutYou, placeholder: "")
                }
                SettingsDivider()
                SettingsRow(label: lang == .vi ? "Hướng dẫn riêng" : "Custom instructions") {
                    field($style.customInstructions,
                          placeholder: lang == .vi ? "Hành vi, phong cách…"
                                                   : "Additional behavior, style, and tone")
                }
            }
        }
        .onAppear {
            guard !loaded else { return }
            style = companyStore.company.founderPrefs.style
            loaded = true
        }
        // One `onChange` per dropdown property, not one on the whole `style` struct —
        // the struct also holds the three text fields, and a single `onChange(of: style)`
        // would fire (and write to Firestore) on every keystroke in those fields too.
        .onChange(of: style.baseTone) { _, _ in commit() }
        .onChange(of: style.warmth) { _, _ in commit() }
        .onChange(of: style.enthusiasm) { _, _ in commit() }
        .onChange(of: style.emoji) { _, _ in commit() }
        // Text fields commit on Return (`onSubmit` in `field(_:placeholder:)`) or here,
        // when the panel leaves the tree (modal closes or another section is picked) —
        // the same two triggers `PreferencesPanel` uses for its Preferred Name field.
        .onDisappear { commit() }
    }

    @ViewBuilder private func levelRow(_ label: String, _ binding: Binding<AIStyle.Level>) -> some View {
        SettingsRow(label: label) {
            Picker("", selection: binding) {
                Text(lang == .vi ? "Ít hơn" : "Less").tag(AIStyle.Level.less)
                Text(lang == .vi ? "Mặc định" : "Default").tag(AIStyle.Level.default)
                Text(lang == .vi ? "Nhiều hơn" : "More").tag(AIStyle.Level.more)
            }
            .labelsHidden().frame(width: 130)
        }
    }

    @ViewBuilder private func field(_ binding: Binding<String>, placeholder: String) -> some View {
        TextField(placeholder, text: binding)
            .textFieldStyle(.plain)
            .font(CodepetTheme.inter(12))
            .frame(width: 240)
            .padding(8)
            .background(RoundedRectangle(cornerRadius: CodepetTheme.inputRadius)
                .fill(CodepetTheme.hairline.opacity(0.5)))
            .onSubmit { commit() }
    }

    private func commit() {
        guard loaded else { return }
        var prefs = companyStore.company.founderPrefs
        guard prefs.style != style else { return }
        prefs.style = style
        Task { await companyStore.setFounderPrefs(prefs) }
    }
}

// codepet/Views/Settings/PreferencesPanel.swift
import SwiftUI
// `authManager.currentUser` is a Firebase `User`, so reading `.email` needs the
// defining module in scope — same import `AccountMenuView` carries for the same reason.
import FirebaseAuth

/// Profile, appearance and language. This pass MOVES the controls; theme and language
/// keep their existing homes on `AppState`.
struct PreferencesPanel: View {
    /// Still an `@EnvironmentObject` because the Theme and Language pickers bind
    /// straight into it (`$appState.appTheme` / `$appState.uiLanguage`); the display
    /// language itself is read from the environment like everywhere else in the shell.
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var companyStore: CompanyStore
    @EnvironmentObject var authManager: AuthManager
    @Environment(\.uiLanguage) private var lang

    /// Same source `AccountMenuView` reads, so the avatar initial and greeting follow it.
    private var founderName: String {
        let n = (companyStore.company.brief.founderName ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return n.isEmpty ? (lang == .vi ? "Bạn" : "You") : n
    }
    private var email: String? { authManager.currentUser?.email }

    @State private var draftName: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            SettingsGroupLabel(lang == .vi ? "Hồ sơ" : "Profile")
            SettingsGroup {
                HStack(spacing: 12) {
                    Text(String(founderName.prefix(1)).uppercased())
                        .font(CodepetTheme.inter(16, weight: .semibold))
                        .foregroundColor(CodepetTheme.onAccent(CodepetTheme.accentPurple))
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(CodepetTheme.accentPurple))
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 14)

                SettingsDivider()
                SettingsRow(label: lang == .vi ? "Tên gọi" : "Preferred Name") {
                    TextField("", text: $draftName)
                        .textFieldStyle(.plain)
                        .font(CodepetTheme.inter(13))
                        .frame(width: 220)
                        .padding(8)
                        .background(RoundedRectangle(cornerRadius: CodepetTheme.inputRadius)
                            .fill(CodepetTheme.hairline.opacity(0.5)))
                        .onSubmit { commitName() }
                }
                SettingsDivider()
                SettingsRow(label: "Email") {
                    Text(email ?? "—")
                        .font(CodepetTheme.inter(12))
                        .foregroundColor(CodepetTheme.mutedText)
                }
            }

            SettingsGroupLabel(lang == .vi ? "Giao diện" : "Appearance")
            SettingsGroup {
                SettingsRow(label: lang == .vi ? "Chủ đề" : "Theme") {
                    Picker("", selection: $appState.appTheme) {
                        Text(lang == .vi ? "Sáng" : "Light").tag(AppTheme.light)
                        Text(lang == .vi ? "Tự động" : "System").tag(AppTheme.system)
                        Text(lang == .vi ? "Tối" : "Dark").tag(AppTheme.dark)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 240)
                }
                SettingsDivider()
                SettingsRow(label: lang == .vi ? "Ngôn ngữ" : "Language") {
                    Picker("", selection: $appState.uiLanguage) {
                        Text("English").tag(AppLanguage.en)
                        Text("Tiếng Việt").tag(AppLanguage.vi)
                    }
                    .labelsHidden()
                    .frame(width: 160)
                }
            }
        }
        .onAppear { draftName = companyStore.company.brief.founderName ?? "" }
    }

    private func commitName() {
        let trimmed = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              trimmed != companyStore.company.brief.founderName else { return }
        Task { await companyStore.setFounderName(trimmed) }
    }
}

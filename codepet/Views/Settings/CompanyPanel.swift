// codepet/Views/Settings/CompanyPanel.swift
import SwiftUI

/// Pure naming for the companion row, so the fallback is testable without a view.
enum CompanionRowModel {
    /// Canonical narrative order (`PetCharacter.starters`), the order every other Codepet
    /// surface uses — NOT alphabetical by id. The deleted `SettingsView` sorted by id,
    /// which put crash and glitch before nova; founder's call, Aug 4. Any id present in
    /// the catalogue but absent from `starters` is appended rather than silently dropped.
    static var all: [PetCharacter] {
        let canonical = PetCharacter.starters.compactMap { PetCharacter.all[$0] }
        let extras = PetCharacter.all.values
            .filter { !PetCharacter.starters.contains($0.id) }
            .sorted { $0.id < $1.id }
        return canonical + extras
    }

    static func summary(companionId: String, lang: AppLanguage) -> String {
        if let c = PetCharacter.all[companionId] { return c.name }
        return lang == .vi ? "Mặc định" : "Default"
    }
}

/// Companion choice and the company brief.
struct CompanyPanel: View {
    /// Kept only because choosing a companion also sets `appState.activeChar`,
    /// the same field the app reads everywhere else for the live sprite.
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var companyStore: CompanyStore
    @Environment(\.uiLanguage) private var lang

    @State private var pickingCompanion = false
    @State private var editingBrief = false
    @State private var confirmStartOver = false
    @State private var startingOver = false

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            SettingsGroup {
                SettingsRow(
                    label: CompanionRowModel.summary(
                        companionId: companyStore.company.companionId, lang: lang),
                    description: lang == .vi
                        ? "Chọn bạn đồng hành làm việc cùng bạn."
                        : "Choose a companion that works alongside you."
                ) {
                    Button {
                        pickingCompanion.toggle()
                    } label: {
                        HStack(spacing: 4) {
                            Text(lang == .vi ? "Chọn" : "Select")
                            Image(systemName: pickingCompanion ? "chevron.down" : "chevron.right").font(.system(size: 10))
                        }
                        .font(CodepetTheme.inter(12, weight: .medium))
                        .foregroundColor(CodepetTheme.mutedText)
                    }
                    .buttonStyle(.plain)
                }
                SettingsDivider()
                SettingsRow(label: lang == .vi ? "Hồ sơ công ty" : "Company brief") {
                    Button(lang == .vi ? "Chỉnh sửa" : "Edit") { editingBrief = true }
                        .buttonStyle(.plain)
                        .font(CodepetTheme.inter(12, weight: .semibold))
                        .foregroundColor(CodepetTheme.accentPurple)
                }
                SettingsDivider()
                SettingsRow(
                    label: StartOverCopy.rowLabel(lang),
                    description: companyStore.startOverBlockedByTeamRun
                        ? StartOverCopy.blockedByTeamBuild(lang) : StartOverCopy.rowDescription(lang)
                ) {
                    Button(StartOverCopy.button(lang)) { confirmStartOver = true }
                        .buttonStyle(.plain)
                        .font(CodepetTheme.inter(12, weight: .semibold))
                        .foregroundColor(companyStore.startOverBlockedByTeamRun
                                         ? CodepetTheme.mutedText : CodepetTheme.accentPurple)
                        .disabled(companyStore.startOverBlockedByTeamRun)
                }
            }

            if pickingCompanion { companionList }
        }
        .confirmationDialog(StartOverCopy.question(lang), isPresented: $confirmStartOver) {
            Button(StartOverCopy.button(lang)) { startingOver = true }
        } message: {
            Text(StartOverCopy.explainer(lang))
        }
        .sheet(isPresented: $startingOver) {
            // The founder's name and role carry over; the business does not.
            CompanyOnboardingView(prefillBrief: CompanyBrief(founderName: companyStore.company.brief.founderName,
                                                             role: companyStore.company.brief.role),
                                  onDone: { startingOver = false },
                                  startsNewBusiness: { await companyStore.startNewBusiness(brief: $0, language: lang) })
        }
        .sheet(isPresented: $editingBrief) {
            // The same editor the deleted SettingsView opened — not a second brief form.
            CompanyOnboardingView(prefillBrief: companyStore.company.brief,
                                  onDone: { editingBrief = false })
        }
    }

    private var companionList: some View {
        SettingsGroup {
            ForEach(Array(CompanionRowModel.all.enumerated()), id: \.element.id) { idx, c in
                if idx > 0 { SettingsDivider() }
                Button {
                    Task { await companyStore.setCompanion(id: c.id) }
                    appState.activeChar = c.id
                    pickingCompanion = false
                } label: {
                    SettingsRow(label: c.name) {
                        if companyStore.company.companionId == c.id {
                            Image(systemName: "checkmark")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(c.color)
                        } else {
                            CharacterImage(c.id, size: 24)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// The words around "Start a different business". The explainer lists every consequence, since
/// the action replaces the roadmap and cannot be undone from the app.
enum StartOverCopy {
    static func rowLabel(_ lang: AppLanguage) -> String {
        lang == .vi ? "Công ty khác" : "A different business"
    }
    static func rowDescription(_ lang: AppLanguage) -> String {
        lang == .vi ? "Bắt đầu lại với một công ty mới — lộ trình mới từ đầu."
                    : "Start over with a new business — a fresh roadmap from scratch."
    }
    static func button(_ lang: AppLanguage) -> String {
        lang == .vi ? "Bắt đầu công ty khác" : "Start a different business"
    }
    static func blockedByTeamBuild(_ lang: AppLanguage) -> String {
        lang == .vi ? "Hãy duyệt hoặc dừng Team build đang chạy trước."
                    : "Approve or stop your team build first."
    }
    static func question(_ lang: AppLanguage) -> String {
        lang == .vi ? "Bắt đầu một công ty khác?" : "Start a different business?"
    }
    static func explainer(_ lang: AppLanguage) -> String {
        lang == .vi
            ? "Lộ trình và các quyết định hiện tại sẽ được thay bằng công ty mới, và thư mục dự án được gỡ liên kết. Thư viện cũ vẫn xem được ở mục \"Từ công ty trước\". Lịch sử chat được giữ nguyên."
            : "Your current roadmap and decisions are replaced by the new business, and the project folder is unlinked. Your old Library stays viewable under \"From your previous business\". Chat history is kept."
    }
}

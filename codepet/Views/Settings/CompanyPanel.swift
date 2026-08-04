// codepet/Views/Settings/CompanyPanel.swift
import SwiftUI

/// Pure naming for the companion row, so the fallback is testable without a view.
enum CompanionRowModel {
    /// Stable ordering, hoisted out of the deleted `SettingsView`'s private
    /// `companions` property so both this panel and any future picker share one list.
    static var all: [PetCharacter] { PetCharacter.all.values.sorted { $0.id < $1.id } }

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
                        pickingCompanion = true
                    } label: {
                        HStack(spacing: 4) {
                            Text(lang == .vi ? "Chọn" : "Select")
                            Image(systemName: "chevron.right").font(.system(size: 10))
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
            }

            if pickingCompanion { companionList }
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

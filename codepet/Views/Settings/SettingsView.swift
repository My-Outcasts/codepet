// codepet/Views/Settings/SettingsView.swift
import SwiftUI

/// The Settings view — Account (companion / language / edit brief / sign out),
/// Plan (static Trial + Pro cards), and About. CF-free; no live billing.
struct SettingsView: View {
    @EnvironmentObject var companyStore: CompanyStore
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var authManager: AuthManager
    @Environment(\.uiLanguage) private var lang
    @State private var editingBrief = false

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }
    private var companions: [PetCharacter] {
        PetCharacter.all.values.sorted { $0.id < $1.id }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                account
                // Plan/billing moved to BillingView (reached via the account menu).
                about
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sheet(isPresented: $editingBrief) {
            CompanyOnboardingView(prefillBrief: companyStore.company.brief,
                                  onDone: { editingBrief = false })
        }
    }

    // MARK: Account

    private var account: some View {
        section(lang == .vi ? "Tài khoản" : "Account") {
            Text(lang == .vi ? "Bạn đồng hành" : "Companion")
                .font(.pixelSystem(size: 11, weight: .medium))
                .foregroundColor(CodepetTheme.mutedText)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(companions) { c in
                        let selected = companyStore.company.companionId == c.id
                        Button {
                            Task { await companyStore.setCompanion(id: c.id) }
                            appState.activeChar = c.id
                        } label: {
                            VStack(spacing: 4) {
                                CharacterImage(c.id, size: 34)
                                Text(c.name)
                                    .font(.pixelSystem(size: 9, weight: .medium))
                                    .foregroundColor(selected ? c.color : CodepetTheme.mutedText)
                            }
                            .padding(6)
                            .background(RoundedRectangle(cornerRadius: 10)
                                .fill(selected ? c.color.opacity(0.14) : Color.clear))
                        }.buttonStyle(.plain)
                    }
                }
            }
            CodepetCard {
                VStack(spacing: 0) {
                    row(lang == .vi ? "Ngôn ngữ" : "Language") {
                        Button(appState.uiLanguage == .vi ? "Tiếng Việt" : "English") {
                            appState.uiLanguage = (appState.uiLanguage == .vi) ? .en : .vi
                        }
                        .buttonStyle(.plain)
                        .font(.pixelSystem(size: 12, weight: .semibold))
                        .foregroundColor(CodepetTheme.accentPurple)
                    }
                    Divider()
                    row(lang == .vi ? "Giao diện" : "Theme") {
                        Button(appState.appTheme.label(lang)) {
                            appState.appTheme = appState.appTheme.next
                        }
                        .buttonStyle(.plain)
                        .font(.pixelSystem(size: 12, weight: .semibold))
                        .foregroundColor(CodepetTheme.accentPurple)
                    }
                    Divider()
                    Button { editingBrief = true } label: {
                        rowLabel(lang == .vi ? "Chỉnh sửa hồ sơ công ty" : "Edit company brief",
                                 icon: "square.and.pencil", tint: CodepetTheme.primaryText)
                    }.buttonStyle(.plain)
                    Divider()
                    Button { authManager.signOut() } label: {
                        rowLabel(lang == .vi ? "Đăng xuất" : "Sign out",
                                 icon: "rectangle.portrait.and.arrow.right", tint: CodepetTheme.accentOrange)
                    }.buttonStyle(.plain)
                }
                .padding(.horizontal, 12)
            }
        }
    }

    // Plan/billing moved to BillingView (reached via the account menu).

    // MARK: About

    private var about: some View {
        section(lang == .vi ? "Giới thiệu" : "About") {
            CodepetCard {
                row("Codepet") {
                    Text("v\(appVersion)")
                        .font(.pixelSystem(size: 11))
                        .foregroundColor(CodepetTheme.mutedText)
                }
                .padding(.horizontal, 12)
            }
        }
    }

    // MARK: Helpers

    private func section<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.pixelSystem(size: 11, weight: .bold))
                .foregroundColor(CodepetTheme.bodyText)
            content()
        }
    }

    private func row<Trailing: View>(_ title: String, @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack {
            Text(title)
                .font(.pixelSystem(size: 12))
                .foregroundColor(CodepetTheme.primaryText)
            Spacer()
            trailing()
        }
        .padding(.vertical, 10)
    }

    private func rowLabel(_ title: String, icon: String, tint: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon).foregroundColor(tint).frame(width: 18)
            Text(title).font(.pixelSystem(size: 12)).foregroundColor(tint)
            Spacer()
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }
}

// codepet/Views/Shell/AccountMenuView.swift
import SwiftUI
import FirebaseAuth

/// The top-bar account menu (web AccountMenu.tsx): identity + Settings / Billing /
/// Support / Appearance / Log out. Uses a native macOS `Menu`.
struct AccountMenuView: View {
    @EnvironmentObject var companyStore: CompanyStore
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var authManager: AuthManager
    @Environment(\.uiLanguage) private var lang

    private var founderName: String {
        let n = (companyStore.company.brief.founderName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return n.isEmpty ? (lang == .vi ? "Bạn" : "You") : n
    }
    private var email: String? { authManager.currentUser?.email }

    var body: some View {
        Menu {
            Section {
                Text(founderName)
                if let e = email { Text(e) }
            }
            Button(lang == .vi ? "Cài đặt" : "Settings") { companyStore.select(.settings) }
            Button(lang == .vi ? "Thanh toán & sử dụng" : "Billing & Usage") { companyStore.select(.billing) }
            Button(lang == .vi ? "Hỗ trợ" : "Support") { companyStore.select(.support) }
            Menu(lang == .vi ? "Giao diện" : "Appearance") {
                Button(lang == .vi ? "Tự động" : "System") { appState.appTheme = .system }
                Button(lang == .vi ? "Sáng" : "Light") { appState.appTheme = .light }
                Button(lang == .vi ? "Tối" : "Dark") { appState.appTheme = .dark }
            }
            Divider()
            Button(lang == .vi ? "Đăng xuất" : "Log out", role: .destructive) { authManager.signOut() }
        } label: {
            HStack(spacing: 6) {
                CharacterImage(companyStore.company.companionId, size: 22)
                Text(founderName).font(CodepetTheme.inter(13, weight: .medium)).foregroundColor(CodepetTheme.bodyText)
                Image(systemName: "chevron.down").font(.system(size: 9)).foregroundColor(CodepetTheme.mutedText)
            }
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }
}

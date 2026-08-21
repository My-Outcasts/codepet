// codepet/Views/Shell/AccountMenuView.swift
import SwiftUI
import FirebaseAuth

/// The top-bar account menu (web AccountMenu.tsx): a purple initial-avatar + account
/// name + chevron opening a grouped dropdown — identity, Upgrade, Settings, Appearance,
/// Log out.
///
/// It is the ONLY control on the right of the top bar (founder call, Aug 5). It used to
/// sit between the wordmark and the tabs, with an Upgrade pill out here; the pill is
/// gone, so this menu now carries the app's only upgrade prompt — hence Upgrade leading,
/// in accent. Billing, Usage and Support are sections of the settings modal rather than
/// destinations, so Upgrade deep-links to Billing and Settings covers the rest.
///
/// Built as a Button + popover rather than a native `Menu`, because a borderless `Menu`
/// mis-renders a rich custom label on macOS (the avatar/name collapse to a bare
/// disclosure). This gives web-exact chrome.
struct AccountMenuView: View {
    /// True in the left rail (64 pt wide): renders only the avatar, omitting the
    /// name text + chevron that would otherwise overflow the rail. Defaults false
    /// so existing call sites (the old top bar) render unchanged.
    var compact: Bool = false

    @EnvironmentObject var companyStore: CompanyStore
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var authManager: AuthManager
    @Environment(\.uiLanguage) private var lang

    private var founderName: String {
        let n = (companyStore.company.brief.founderName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return n.isEmpty ? (lang == .vi ? "Bạn" : "You") : n
    }
    private var email: String? { authManager.currentUser?.email }
    @State private var showMenu = false
    @State private var confirmLogout = false

    var body: some View {
        Button { showMenu.toggle() } label: {
            HStack(spacing: 7) {
                Text(String(founderName.prefix(1)).uppercased())
                    .font(CodepetTheme.inter(11, weight: .bold)).foregroundColor(.white)
                    .frame(width: 24, height: 24)
                    .background(Circle().fill(CodepetTheme.accentPurple))
                if !compact {
                    Text(founderName).font(CodepetTheme.inter(14, weight: .medium)).foregroundColor(CodepetTheme.bodyText)
                    Image(systemName: "chevron.down").font(.system(size: 10, weight: .semibold)).foregroundColor(CodepetTheme.mutedText)
                }
            }
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showMenu, arrowEdge: .bottom) { menuContent }
        .confirmationDialog(lang == .vi ? "Đăng xuất khỏi Codepet?" : "Sign out of Codepet?",
                            isPresented: $confirmLogout, titleVisibility: .visible) {
            Button(lang == .vi ? "Đăng xuất" : "Log out", role: .destructive) { authManager.signOut() }
            Button(lang == .vi ? "Huỷ" : "Cancel", role: .cancel) { }
        }
    }

    private var menuContent: some View {
        VStack(alignment: .leading, spacing: 4) {
            VStack(alignment: .leading, spacing: 2) {
                Text(founderName).font(CodepetTheme.inter(13, weight: .semibold)).foregroundColor(CodepetTheme.primaryText)
                if let e = email {
                    Text(e).font(CodepetTheme.inter(11)).foregroundColor(CodepetTheme.mutedText).lineLimit(1)
                }
            }
            .padding(.horizontal, 10).padding(.top, 8).padding(.bottom, 4)
            Divider()
            // Upgrade leads, in accent: with the top-bar pill removed this menu carries
            // the only upgrade prompt in the app, so it should not read as one more
            // neutral row. It opens the settings modal's Billing section — the same
            // destination the pill had — where Billing and Usage are adjacent sections,
            // so a founder after their usage rather than a plan still finds it.
            menuRow(lang == .vi ? "Nâng cấp" : "Upgrade", tint: CodepetTheme.accentPurple) {
                companyStore.openSettings(.billing)
            }
            menuRow(lang == .vi ? "Cài đặt" : "Settings") { companyStore.openSettings() }
            Divider()
            Text(lang == .vi ? "GIAO DIỆN" : "APPEARANCE")
                .font(CodepetTheme.inter(9, weight: .bold)).foregroundColor(CodepetTheme.mutedText)
                .padding(.horizontal, 10).padding(.top, 2)
            HStack(spacing: 6) {
                themeButton(.system, lang == .vi ? "Tự động" : "System")
                themeButton(.light, lang == .vi ? "Sáng" : "Light")
                themeButton(.dark, lang == .vi ? "Tối" : "Dark")
            }.padding(.horizontal, 10).padding(.bottom, 2)
            #if DEBUG
            Divider()
            PrototypeModeToggle()
                .padding(.horizontal, 10).padding(.vertical, 4)
            #endif
            Divider()
            menuRow(lang == .vi ? "Đăng xuất" : "Log out", destructive: true) { confirmLogout = true }
        }
        .padding(.vertical, 4)
        .frame(width: 230)
    }

    /// `tint` overrides the row's ink — used by Upgrade, which is a call to action rather
    /// than a neutral destination. `destructive` is the same idea for Log out and stays
    /// separate so call sites read as intent, not colour.
    private func menuRow(_ title: String, destructive: Bool = false, tint: Color? = nil,
                         _ action: @escaping () -> Void) -> some View {
        Button { showMenu = false; action() } label: {
            Text(title).font(CodepetTheme.inter(13, weight: tint == nil ? .medium : .semibold))
                .foregroundColor(tint ?? (destructive ? CodepetTheme.accentOrange : CodepetTheme.bodyText))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10).padding(.vertical, 6)
                .contentShape(Rectangle())
        }.buttonStyle(.plain)
    }

    private func themeButton(_ theme: AppTheme, _ label: String) -> some View {
        let on = appState.appTheme == theme
        return Button { appState.appTheme = theme } label: {
            Text(label).font(CodepetTheme.inter(11, weight: .medium))
                .foregroundColor(on ? .white : CodepetTheme.bodyText)
                .frame(maxWidth: .infinity).padding(.vertical, 5)
                .background(RoundedRectangle(cornerRadius: 7).fill(on ? CodepetTheme.accentPurple : CodepetTheme.surface))
        }.buttonStyle(.plain)
    }
}

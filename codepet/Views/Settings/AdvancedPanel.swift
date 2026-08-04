// codepet/Views/Settings/AdvancedPanel.swift
import SwiftUI

/// Sign-out and the version row.
///
/// Export and Delete are deferred, not stubbed: both need real Firestore work (a full
/// account read-out, and a chat-tree delete that can't half-finish) and land in their own
/// task. A button that silently does nothing would be worse than an absent one — so the
/// section subtitle promises only sign-out and the version, and nothing here claims an
/// action the app can't perform.
struct AdvancedPanel: View {
    @EnvironmentObject var authManager: AuthManager
    @Environment(\.uiLanguage) private var lang

    @State private var confirmSignOut = false

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            SettingsGroup {
                SettingsDestructiveRow(
                    label: lang == .vi ? "Đăng xuất" : "Sign out",
                    description: lang == .vi ? "Tiến trình của bạn vẫn được lưu trên đám mây."
                                             : "Your progress stays saved in the cloud.",
                    actionTitle: lang == .vi ? "Đăng xuất" : "Sign out"
                ) { confirmSignOut = true }
            }
            SettingsGroup {
                SettingsRow(label: "Codepet") {
                    Text("v\(appVersion)")
                        .font(CodepetTheme.inter(11))
                        .foregroundColor(CodepetTheme.mutedText)
                }
            }
        }
        .confirmationDialog(
            lang == .vi ? "Đăng xuất khỏi Codepet?" : "Sign out of Codepet?",
            isPresented: $confirmSignOut,
            titleVisibility: .visible
        ) {
            Button(lang == .vi ? "Đăng xuất" : "Sign out", role: .destructive) {
                authManager.signOut()
            }
            Button(lang == .vi ? "Huỷ" : "Cancel", role: .cancel) { }
        }
    }
}

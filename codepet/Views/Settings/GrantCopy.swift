// codepet/Views/Settings/GrantCopy.swift
import Foundation

/// What the Permission rows in `ClaudeCodePanel` actually say.
///
/// **Extracted from the view because the copy was wrong and untestable.** It said "turn it
/// off and Codepet goes back to the old route". There is no old route: `ChatTransportRouter`
/// and `LocalTransportRouter` each document that they have deliberately no hosted case, and
/// `CloudAIBlock.blockedPaths` refuses those endpoints before they leave the app. The Claude
/// toggle is the product's on/off switch, and describing it as a preference with a safe
/// fallback is what made founders decline it and land in an app where nothing ran.
///
/// **The two rows are not symmetric and must stop being written as if they were.** Claude off
/// stops everything. Codex off sends the one-shot ops back to Claude
/// (`LocalTransportRouter.chooseProvider` falls through Claude → Codex) and never touched chat
/// or the department room at all, which are `.claudeOnly`.
///
/// Kept as a static on an enum, outside any `@MainActor ObservableObject` — landmine 3, the
/// XCTest host crash on Xcode 26.2 — so a test asserts the strings with no SwiftUI. Same
/// reasoning as `ProviderGrantRow` beside it.
enum GrantCopy {

    /// Written out per provider rather than templated. The plan name, the scope and the
    /// off-state are three provider-specific facts, not one sentence with a hole in it —
    /// the same rule `ProviderAuthorisation.key` follows.
    static func description(for provider: AIProvider, lang: AppLanguage) -> String {
        switch provider {
        case .claudeCode:
            return lang == .vi
                ? """
                  Mọi thứ chạy trên gói Claude của chính bạn, ngay trên máy bạn — chat, lộ trình, \
                  nhiệm vụ, brief, quyết định, phòng họp các bộ phận, và Build khi bạn đã liên kết \
                  thư mục. Mỗi lượt tiêu hạn mức Claude của bạn.

                  Codepet cần quyền này để hoạt động. Tắt đi là Codepet dừng cho tới khi bạn bật \
                  lại. Claude Code trong terminal của bạn không bị ảnh hưởng.
                  """
                : """
                  Everything runs on your own Claude plan, on your Mac — chat, your roadmap, \
                  tasks, briefs, decisions, the department room, and Build once a folder is \
                  linked. Each turn spends your Claude quota.

                  Codepet needs this to work. Turn it off and it stops until you turn it back \
                  on. Your terminal's Claude Code is unaffected.
                  """
        case .codex:
            // No chat, no department room: both are `.claudeOnly`.
            return lang == .vi
                ? """
                  Nhiệm vụ, brief, quyết định và Build có thể chạy trên gói Codex của bạn, ngay \
                  trên máy bạn. Mỗi lượt tiêu hạn mức Codex của bạn.

                  Tắt đi thì phần việc này quay lại Claude nếu bạn đã cấp quyền Claude. Codex \
                  trong terminal của bạn không bị ảnh hưởng.
                  """
                : """
                  Tasks, briefs, decisions and Build can run on your Codex plan, on your Mac. \
                  Each turn spends your Codex quota.

                  Turn it off and that work goes back to Claude, when Claude is granted. Your \
                  terminal's Codex is unaffected.
                  """
        }
    }
}

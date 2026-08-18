// codepet/Views/Shell/TwoModeShellView.swift
import SwiftUI

/// The two-mode shell: a rail, a conversation, and (later) an inspector.
///
/// Replaces `AppShellView` only when launched with `-CODEPET_TWO_MODE YES`, so
/// `main` keeps shipping the web-parity shell while this is built.
///
/// **Adapted, not ported.** The prototype is dark and hand-drawn; this uses
/// `CodepetTheme` so it follows the app's light/dark tokens, and it COMPOSES
/// what already exists — `CopilotChatView` is the conversation, the five
/// destinations are the same views the top nav shows today, and Developer's
/// review is `EngineeringWorkspaceView`. The only genuinely new furniture is the
/// rail and the mode switch.
///
/// Spec: `docs/superpowers/specs/2026-08-17-codepet-two-mode-product-design.md`.
struct TwoModeShellView: View {
    @EnvironmentObject var companyStore: CompanyStore
    @EnvironmentObject var appState: AppState
    @Environment(\.uiLanguage) private var lang

    @State private var mode: WorkspaceMode = .restore()

    private var accent: Color { CodepetTheme.accentPurple }

    var body: some View {
        HStack(spacing: 0) {
            TwoModeSidebar(mode: $mode)
                .frame(width: TwoModeLayout.railWidth)
            Divider()
            pane
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(CodepetTheme.pageBackground)
        .onChange(of: mode) { _, new in
            new.persist()
            // Switching INTO Developer while browsing a company page would leave
            // the founder looking at Roadmap with a Developer rail — the mode
            // change would appear to do nothing. Return them to the conversation,
            // which is the surface each mode is actually about.
            if !TwoModeLayout.showsConversation(for: companyStore.view) {
                companyStore.view = .chat
            }
        }
        .overlay {
            if let section = companyStore.settingsSection {
                SettingsModal(initial: section).transition(.opacity)
            }
        }
        .sheet(isPresented: Binding(
            get: { companyStore.engineeringRepoPrompt != nil },
            set: { if !$0 { companyStore.engineeringRepoPrompt = nil } }
        )) {
            ConnectRepoSheet(
                repos: EngineeringRepoClient(),
                onLinked: { _ in companyStore.engineeringRepoLinked() },
                onCancel: { companyStore.engineeringRepoPrompt = nil }
            )
        }
    }

    // MARK: - The pane

    @ViewBuilder private var pane: some View {
        if TwoModeLayout.showsConversation(for: companyStore.view) {
            switch mode {
            case .ask:       CopilotChatView()
            case .developer: developerPane
            }
        } else {
            destinationPage
        }
    }

    /// Developer: the run if there is one, otherwise an honest dormant state.
    /// An empty session would be a worse lie than an offer — without a repo there
    /// is no tree to read and no branch to commit to.
    @ViewBuilder private var developerPane: some View {
        if let runId = companyStore.engineeringReviewRunId, let store = companyStore.engineeringRunStore {
            EngineeringWorkspaceView(runId: runId, store: store,
                                     onClose: { companyStore.engineeringReviewRunId = nil })
        } else if companyStore.engineeringRunStore != nil {
            // A run exists but nothing is being reviewed yet — the conversation is
            // still where the run streams, so keep the founder in it.
            CopilotChatView()
        } else {
            dormantDeveloper
        }
    }

    private var dormantDeveloper: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(lang == .vi ? "Developer cần một nơi để làm việc"
                             : "Developer needs somewhere to work")
                .font(CodepetTheme.inter(17, weight: .semibold))
                .foregroundStyle(CodepetTheme.primaryText)
            Text(lang == .vi
                 ? "Trỏ nó vào mã của bạn và nó sẽ thức dậy. Trước đó, không có gì trung thực để hiển thị."
                 : "Point it at your code and it wakes up. Until then there is nothing honest for it to show you.")
                .font(CodepetTheme.body(13))
                .foregroundStyle(CodepetTheme.mutedText)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                companyStore.engineeringRepoPrompt = ""
            } label: {
                Text(lang == .vi ? "Kết nối một repo" : "Connect a repo")
                    .font(CodepetTheme.inter(13, weight: .semibold))
                    .padding(.horizontal, 14).padding(.vertical, 9)
                    .background(accent, in: RoundedRectangle(cornerRadius: 9))
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
            Text(lang == .vi
                 ? "Dù thế nào: không merge · không deploy · không xoá · không force-push"
                 : "Either way: no merge · no deploy · no delete · no force-push")
                .font(CodepetTheme.pixel(10))
                .foregroundStyle(CodepetTheme.mutedText)
                .padding(.top, 2)
        }
        .frame(maxWidth: 420, alignment: .leading)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(28)
    }

    /// The five company pages — the same views the top nav shows today, so this
    /// shell inherits every fix they have had rather than forking them.
    @ViewBuilder private var destinationPage: some View {
        switch companyStore.view {
        case .roadmap: RoadmapView()
        case .company:
            if let dept = companyStore.selectedDeptKey {
                DepartmentDetailView(deptKey: dept, onBack: { companyStore.selectedDeptKey = nil })
            } else {
                CompanyView(onOpen: { companyStore.selectedDeptKey = $0 })
            }
        case .tasks:       TasksView()
        case .library:     LibraryView()
        case .environment: EnvironmentView()
        case .chat, .secondBrain: CopilotChatView()
        }
    }
}

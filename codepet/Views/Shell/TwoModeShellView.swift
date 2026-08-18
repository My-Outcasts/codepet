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

    var body: some View {
        HStack(spacing: 0) {
            TwoModeSidebar(mode: $mode)
                .frame(width: TwoModeLayout.railWidth)
            Divider()
            pane
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(CodepetTheme.pageBackground)
        // Every chat this shell hosts is the pane's chat, not the dock's: no
        // collapse/history row, no composer mode pill, composer docked at the
        // bottom. Set once here so a future destination that shows the chat
        // cannot forget it.
        .environment(\.chatSurface, .twoMode)
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

    /// The prototype's dormant state: a title row with its own status dot, the
    /// honest line, BOTH doors, and the ceiling.
    ///
    /// Two doors, not one. Local (your own `claude` CLI against a folder on this
    /// Mac) is the **primary**, and it is tinted `accentGreen` rather than the
    /// companion violet — the prototype gives Local its own hue because the thing
    /// worth saying about it is that it costs **0 credits**. Offering only
    /// "Connect a repo" hides the free path behind the billed one.
    ///
    /// The ceiling here is the *pricing* one. `no merge · no deploy · no delete ·
    /// no force-push` is the tier ceiling and belongs to the READY state, where a
    /// tier can actually be chosen — printing it over a dormant pane answers a
    /// question nobody has asked yet.
    private var dormantDeveloper: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(lang == .vi ? "Developer cần một nơi để làm việc"
                                 : "Developer needs somewhere to work")
                    .font(CodepetTheme.inter(14.5, weight: .semibold))
                    .foregroundStyle(CodepetTheme.primaryText)
                stateDot(lang == .vi ? "Ngủ đông" : "Dormant", tint: CodepetTheme.mutedText)
            }
            Text(lang == .vi
                 ? "Trỏ nó vào mã và nó sẽ thức dậy. Trước đó, không có gì trung thực để hiển thị."
                 : "Point it at code and it wakes up. Until then there is nothing honest for it to show you.")
                .font(CodepetTheme.body(12.5))
                .foregroundStyle(CodepetTheme.mutedText)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                doorButton(lang == .vi ? "Liên kết một thư mục trên máy Mac này"
                                       : "Link a folder on this Mac",
                           filled: true) {
                    companyStore.select(.environment)
                }
                doorButton(lang == .vi ? "Kết nối một repo" : "Connect a repo",
                           filled: false) {
                    companyStore.engineeringRepoPrompt = ""
                }
            }
            ceiling(
                title: lang == .vi ? "Dù thế nào" : "Either way",
                body: lang == .vi
                    ? "0 tín dụng trên CLI của bạn · tính tín dụng trên đám mây · và trần giới hạn giữ nguyên từ lần chạy đầu tiên"
                    : "0 credits on your own CLI · credits in the cloud · and the ceiling holds from the first run")
        }
        .frame(maxWidth: 460, alignment: .leading)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.horizontal, 17).padding(.vertical, 15)
    }

    /// A run-state label with its dot — `● READY`, `● DORMANT`. Monospaced and
    /// tracked, so it reads as machine state rather than as a second heading.
    private func stateDot(_ label: String, tint: Color) -> some View {
        HStack(spacing: 6) {
            Circle().fill(tint).frame(width: 7, height: 7)
            Text(label.uppercased())
                .font(CodepetTheme.pixel(10)).tracking(1)
                .foregroundStyle(tint)
        }
    }

    private func doorButton(_ label: String, filled: Bool,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(CodepetTheme.inter(11.5, weight: .semibold))
                .padding(.horizontal, 12).padding(.vertical, 9)
                .background(RoundedRectangle(cornerRadius: 7)
                    .fill(filled ? CodepetTheme.accentGreen : CodepetTheme.surface))
                .overlay(filled ? nil : RoundedRectangle(cornerRadius: 7)
                    .stroke(CodepetTheme.hairline))
                .foregroundStyle(filled ? CodepetTheme.onAccent(CodepetTheme.accentGreen)
                                        : CodepetTheme.bodyText)
        }
        .buttonStyle(.plain)
    }

    /// The rule-above-the-fine-print block the prototype uses for anything that is
    /// a promise rather than a state.
    private func ceiling(title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Divider()
            Text(title.uppercased())
                .font(CodepetTheme.pixel(10)).tracking(1)
                .foregroundStyle(CodepetTheme.bodyText)
            Text(body)
                .font(CodepetTheme.pixel(10))
                .lineSpacing(3)
                .foregroundStyle(CodepetTheme.mutedText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 3)
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

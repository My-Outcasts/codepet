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
    /// Guards the one-time landing redirect in `onAppear`.
    @State private var landed = false

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
        // Open in the conversation. Once per appearance, and only from the store's
        // launch default — a founder who navigated to Tasks and came back must not
        // be yanked out of it by a re-render.
        .onAppear {
            if !landed {
                landed = true
                if companyStore.view == AppView.home {
                    companyStore.view = TwoModeLayout.launchDestination
                }
            }
        }
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
    ///
    /// **Dormant means BOTH doors are shut.** This used to test
    /// `engineeringRunStore` alone, which is the CLOUD path — so linking a local
    /// folder woke nothing up and Developer went on saying it had nowhere to work
    /// while pointed at a repo. The prototype's gate is `repoLinked`, which either
    /// door satisfies; `activeProjectLink` is the local half of it.
    @ViewBuilder private var developerPane: some View {
        if let runId = companyStore.engineeringReviewRunId, let store = companyStore.engineeringRunStore {
            EngineeringWorkspaceView(runId: runId, store: store,
                                     onClose: { companyStore.engineeringReviewRunId = nil })
        } else if TwoModeLayout.developerIsAwake(projectLink: companyStore.activeProjectLink != nil,
                                                 cloudRun: companyStore.engineeringRunStore != nil) {
            // Awake but nothing under review: the conversation is where a run is
            // described and where it streams (`EditCodeRouting` sends a code ask to
            // the coding run once a folder is linked), so keep the founder in it.
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
                // The picker, right here — not a trip to Environment to hunt for a
                // button with a different label. `ProjectLinker` is the shared flow
                // Environment and the chat card both use, so the CLAUDE.md consent
                // rule is the same one in all three places (it is never written
                // without an explicit yes).
                doorButton(lang == .vi ? "Liên kết một thư mục trên máy Mac này"
                                       : "Link a folder on this Mac",
                           filled: true) {
                    _ = ProjectLinker.pickAndLink(into: companyStore, language: lang)
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

    /// A run-state label with its dot — `● READY`, `● DORMANT`. Uppercase and
    /// tracked so it reads as machine state rather than as a second heading; the
    /// typeface is the app's sans, same as every other label in the shell.
    private func stateDot(_ label: String, tint: Color) -> some View {
        HStack(spacing: 6) {
            Circle().fill(tint).frame(width: 7, height: 7)
            Text(label.uppercased())
                .font(CodepetTheme.inter(10)).tracking(1)
                .foregroundStyle(tint)
        }
    }

    private func doorButton(_ label: String, filled: Bool,
                            action: @escaping () -> Void) -> some View {
        let hue = CodepetTheme.accentGreen
        let shape = RoundedRectangle(cornerRadius: 9, style: .continuous)
        return Button(action: action) {
            Text(label)
                .font(CodepetTheme.inter(11.5, weight: .semibold))
                .padding(.horizontal, 12).padding(.vertical, 9)
                .background(shape.fill(filled ? hue : CodepetTokens.cardRaised))
                .overlay(filled ? nil : shape.stroke(CodepetTokens.cardEdge))
                .foregroundStyle(filled ? CodepetTheme.onAccent(hue) : CodepetTheme.bodyText)
                .contentShape(shape)
                .hoverAffordance(shape, accent: hue)
        }
        .buttonStyle(.plain)
    }

    /// The rule-above-the-fine-print block the prototype uses for anything that is
    /// a promise rather than a state.
    private func ceiling(title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Rectangle().fill(CodepetTokens.cardEdge).frame(height: 1)
            Text(title.uppercased())
                .font(CodepetTheme.inter(10)).tracking(1)
                .foregroundStyle(CodepetTokens.faint)
                .padding(.top, 4)
            Text(body)
                .font(CodepetTheme.inter(11))
                .lineSpacing(3)
                .foregroundStyle(CodepetTheme.mutedText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 6)
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

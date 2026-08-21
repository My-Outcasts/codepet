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

    /// Rail geometry, persisted: a founder who narrows the rail means it, and having
    /// to redo it every launch is the kind of thing that makes a window feel rented.
    @AppStorage(TwoModeLayout.railWidthKey) private var railWidth = TwoModeLayout.railWidth
    @AppStorage(TwoModeLayout.railCollapsedKey) private var railCollapsed = false
    /// Drag bookkeeping. `dragStartWidth` is what makes the gesture absolute rather
    /// than incremental — see the divider's comment.
    @State private var dragStartWidth: CGFloat?
    @State private var handleDragging = false
    @State private var handleHovered = false

    #if DEBUG
    /// The self-driving walkthrough. Owned here because this is the only view that
    /// can adopt the mode it asks for — `mode` is `@State` and the player cannot
    /// reach into it.
    @StateObject private var player = MockFlowPlayer()
    #endif

    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 0) {
                if !railCollapsed {
                    TwoModeSidebar(mode: $mode)
                        .frame(width: TwoModeLayout.clampRailWidth(railWidth,
                                                                   windowWidth: geo.size.width))
                    railDivider(windowWidth: geo.size.width)
                }
                pane
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .overlay(alignment: .topLeading) { revealButton }
            }
        }
        .background(CodepetTheme.pageBackground)
        // Every chat this shell hosts is the pane's chat, not the dock's: no
        // collapse/history row, no composer mode pill, composer docked at the
        // bottom. Set once here so a future destination that shows the chat
        // cannot forget it.
        .environment(\.chatSurface, .twoMode)
        // ⌘B toggles the rail. Free on this surface: main binds it to collapsing the
        // dock, and this shell has no dock — the pane IS the conversation.
        .background {
            Button("") { railCollapsed.toggle() }
                .keyboardShortcut("b", modifiers: .command)
                .opacity(0)
                .accessibilityHidden(true)
        }
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
        #if DEBUG
        // The walkthrough sits over the pane, not inside it, so no beat can be
        // pushed off screen by the content it is narrating.
        .overlay(alignment: .bottom) {
            if MockFlowPlayer.enabled {
                MockFlowCaptionBar(player: player)
            }
        }
        .onAppear {
            guard MockFlowPlayer.enabled else { return }
            player.attach(store: companyStore, language: lang)
            player.play()
        }
        // The player cannot set `mode` — it publishes a request and the shell
        // adopts it, which also means a beat that changes mode goes through the
        // same `persist()`/redirect path a founder's tap does.
        .onChange(of: player.requestedMode) { _, requested in
            if let requested, requested != mode { mode = requested }
        }
        #endif
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

    // MARK: - Rail geometry

    /// Click to collapse, drag to resize — one control, the way Claude Code's is.
    ///
    /// `.global`, NOT the default `.local`, and the reason is already written down in
    /// this codebase: the gesture is attached to the divider and dragging it MOVES
    /// the divider, so in local space the reported translation is
    /// (pointer moved − handle moved) and each frame's new width feeds into the next
    /// frame's translation. Measured off a recording on 10 Aug for the dock's version
    /// of this handle: it tracked at ~half the pointer's speed and reversed direction
    /// 33 times in one drag, ending 90–115pt behind. It reads as lag; it is a
    /// feedback loop. Global space is fixed while the handle moves through it.
    private func railDivider(windowWidth: CGFloat) -> some View {
        Rectangle()
            .fill(CodepetTheme.hairline)
            .frame(width: 1)
            .overlay {
                Rectangle().fill(CodepetTheme.accentPurple.opacity(0.6))
                    .frame(width: 2)
                    .opacity(handleDragging || handleHovered ? 1 : 0)
            }
            // The visible line is 1pt; this is what makes it catchable.
            .overlay(Color.clear
                .frame(width: TwoModeLayout.railResizeHitWidth)
                .contentShape(Rectangle()))
            .help(lang == .vi ? "Nhấn để thu gọn (⌘B) · Kéo để đổi cỡ"
                              : "Click to collapse (⌘B) · Drag to resize")
            .cursorOnHover(.resizeLeftRight, held: handleDragging) { handleHovered = $0 }
            .gesture(
                DragGesture(minimumDistance: 3, coordinateSpace: .global)
                    .onChanged { value in
                        let start = dragStartWidth ?? railWidth
                        if dragStartWidth == nil { dragStartWidth = start }
                        handleDragging = true
                        // The divider sits to the RIGHT of the rail, so dragging right
                        // grows it — the opposite sign to the dock's handle, which sits
                        // to the left of what it moves.
                        railWidth = TwoModeLayout.clampRailWidth(start + value.translation.width,
                                                                windowWidth: windowWidth)
                    }
                    .onEnded { _ in
                        dragStartWidth = nil
                        handleDragging = false
                    }
            )
            // A tap that follows a drag must not also collapse the rail.
            .onTapGesture { if !handleDragging { railCollapsed = true } }
    }

    /// The way back. Collapsing a panel with no visible means of return is a trap,
    /// and ⌘B alone is not a means of return — it is a thing you have to already know.
    @ViewBuilder private var revealButton: some View {
        if railCollapsed {
            Button { railCollapsed = false } label: {
                Image(systemName: "sidebar.left")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(CodepetTheme.mutedText)
                    .padding(7)
                    .contentShape(Rectangle())
                    .hoverAffordance(RoundedRectangle(cornerRadius: 7, style: .continuous))
            }
            .buttonStyle(.plain)
            .help(lang == .vi ? "Hiện thanh bên (⌘B)" : "Show sidebar (⌘B)")
            .padding(.leading, 10).padding(.top, 8)
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
            // Developer's own surface, not the Ask transcript.
            //
            // This used to be `CopilotChatView()`, justified as "the conversation is
            // where a run is described and where it streams". Seen next to the
            // prototype that does not hold: a code run rendered as chat bubbles has no
            // exec log, no changed-file summary, no branch and no Review gate — the
            // founder was watching a transcript where the design has a work pane. The
            // composer stays underneath, because describing the task is still a
            // sentence you type.
            DeveloperWorkPane(coordinator: companyStore.codingRun)
        } else {
            dormantDeveloper
        }
    }

    /// The prototype's dormant state: a title row with its own status dot, the
    /// honest line, BOTH doors, and the ceiling.
    ///
    /// **Laid out like every other pane state**, which it was not: it sat at
    /// `.topLeading` with 17/15 of its own padding, so it began 23pt under the
    /// titlebar hard against the left edge while the hero and the transcript both
    /// run down a centred 620pt column with 44pt of head. It also collided with the
    /// rail's own reveal button, which lives at the pane's top-left when the sidebar
    /// is collapsed — the icon landed on top of the "D" of "Developer". Sharing the
    /// column and the head padding fixes the look and the collision in one move.
    ///
    /// Two doors, not one: offering only "Connect a repo" hides the free path behind
    /// the billed one.
    ///
    /// **The primary is violet, not green.** It was `accentGreen`, because the
    /// prototype gives Local its own hue and the thing worth saying is that it costs
    /// 0 credits. But green means STATUS in this app — energy level, a positive
    /// delta, Product's department accent — and it is a primary action nowhere, so a
    /// mint CTA read as a control borrowed from another product. The fact survives
    /// where it belongs, in the ceiling line: "0 credits on your own CLI".
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
                    .font(CodepetTheme.inter(CodepetType.title3, weight: .semibold))
                    .foregroundStyle(CodepetTheme.primaryText)
                stateDot(lang == .vi ? "Ngủ đông" : "Dormant", tint: CodepetTheme.mutedText)
            }
            Text(lang == .vi
                 ? "Trỏ nó vào mã và nó sẽ thức dậy. Trước đó, không có gì trung thực để hiển thị."
                 : "Point it at code and it wakes up. Until then there is nothing honest for it to show you.")
                .font(CodepetTheme.inter(CodepetType.body))
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
        // The same column and head the transcript uses, so Developer sits on the two
        // vertical lines every other pane state does.
        .readingColumn(ChatColumn.paneMeasureCap)
        .padding(.top, ChatRhythm.transcriptTop(.twoMode))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    /// A run-state label with its dot — `● READY`, `● DORMANT`. Uppercase and
    /// tracked so it reads as machine state rather than as a second heading; the
    /// typeface is the app's sans, same as every other label in the shell.
    private func stateDot(_ label: String, tint: Color) -> some View {
        HStack(spacing: 6) {
            Circle().fill(tint).frame(width: 7, height: 7)
            Text(label.uppercased())
                .font(CodepetTheme.inter(CodepetType.footnote)).tracking(1)
                .foregroundStyle(tint)
        }
    }

    private func doorButton(_ label: String, filled: Bool,
                            action: @escaping () -> Void) -> some View {
        // Violet, the app's primary. See `dormantDeveloper` for why this is not the
        // prototype's green.
        let hue = CodepetTheme.accentPurple
        let shape = RoundedRectangle(cornerRadius: 9, style: .continuous)
        return Button(action: action) {
            Text(label)
                .font(CodepetTheme.inter(CodepetType.body, weight: .semibold))
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
                .font(CodepetTheme.inter(CodepetType.footnote)).tracking(1)
                .foregroundStyle(CodepetTokens.faint)
                .padding(.top, 4)
            Text(body)
                .font(CodepetTheme.inter(CodepetType.subheadline))
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

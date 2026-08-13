// codepet/Views/Shell/AppShellView.swift
import SwiftUI

/// The app's top-level shell — a top nav bar (`TopNavView`), a content area
/// switching on the store's view, and a docked copilot (`CopilotChatView`) on the
/// right. The dock collapses to a circular logo button (`CollapsedCopilotButton`)
/// per `ShellLayout` when the window is narrow or the user collapses it.
///
/// The copilot appears on the OVERVIEW destination only (`ShellLayout.showsCopilot`)
/// — on Company, Tasks, Library, Environment and the account destinations the
/// content takes the full width and neither the dock nor its button is rendered.
///
/// Styled in CodepetTheme; the chrome accent is Codepet purple, not the companion's.
struct AppShellView: View {
    @EnvironmentObject var companyStore: CompanyStore
    @EnvironmentObject var appState: AppState
    @Environment(\.uiLanguage) private var uiLanguage

    /// Codepet's primary colour. Founder call (Aug 3): the PRODUCT chrome is purple
    /// — nav, pills, CTAs, the board — and does not repaint itself per companion.
    /// It used to read `PetCharacter.all[appState.activeChar]?.color`, so selecting
    /// Crash (`#E04040`) turned the whole app red. The companion still owns its own
    /// identity (name, sprite, voice, and its tint inside the chat); it no longer
    /// owns the brand.
    private var accent: Color { CodepetTheme.accentPurple }
    /// User-dragged copilot width (session-only). nil → the default half-window.
    @State private var manualDockWidth: CGFloat?
    /// Dock width captured at the start of a resize drag, so the drag delta is
    /// applied to a fixed base instead of the value we're mutating each frame.
    @State private var dragStartWidth: CGFloat?
    /// Hover state for the resize handle (brightens the divider on hover).
    @State private var handleHovered = false
    /// Whether a resize drag is in flight. The pointer leaves the handle's strip the
    /// instant the drag starts moving, so hover alone cannot carry the divider's
    /// highlight or its resize cursor through the drag — this does.
    ///
    /// Cleared in `onEnded`. If a gesture is ever cancelled without ending (app
    /// deactivated mid-drag), the resize cursor stays set — but only until the handle
    /// leaves the hierarchy, which `CursorOnHover.onDisappear` catches, and which ⌘B or
    /// any non-Overview destination does. Bounded, unlike the session-long leak that
    /// modifier was written to fix.
    @State private var handleDragging = false
    /// Message count as of the last time the dock was open — the baseline for the
    /// collapsed bar's unread dot, so reopening the dock always clears it.
    @State private var seenMessageCount = 0

    var body: some View {
        GeometryReader { geo in
            // The copilot is an Overview surface — everywhere else the content takes
            // the full width and neither the dock nor its button appears.
            let showsCopilot = ShellLayout.showsCopilot(in: companyStore.view)
            let collapsed = ShellLayout.dockCollapsed(forWidth: geo.size.width, manual: companyStore.dockCollapsed)
            // Expanded copilot defaults to half the window; a drag on the divider
            // resizes it (clamped so both panes stay usable), a click collapses it.
            let base = manualDockWidth ?? ShellLayout.dockWidth(forWidth: geo.size.width)
            let dockWidth = ShellLayout.clampDockWidth(base, windowWidth: geo.size.width)
            VStack(spacing: 0) {
                // Raised: the wordmark's hover tooltip hangs BELOW the bar, into the content's
                // band. Siblings paint in declaration order, so without this the view underneath
                // would draw straight over the plate and the tooltip would be invisible on every
                // surface except an empty one.
                TopNavView(accent: accent)
                    .zIndex(1)
                Divider()
                HStack(spacing: 0) {
                    // Collapsed, the copilot is a circular floating button in the
                    // content's bottom-right corner (web parity), replacing the old
                    // full-height reopen rail. An overlay, not a `safeAreaInset`: it
                    // floats over the board the way the web button does rather than
                    // reserving a strip of layout.
                    content
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .overlay(alignment: .bottomTrailing) {
                            if showsCopilot && collapsed {
                                CollapsedCopilotButton(
                                    needsYou: CollapsedCopilotState.needsYouCount(
                                        tasks: companyStore.company.tasks),
                                    unread: CollapsedCopilotState.showsUnreadDot(
                                        messageCount: companyStore.chatMessages.count,
                                        seen: seenMessageCount),
                                    onExpand: { companyStore.dockCollapsed = false }
                                )
                            }
                        }
                    if showsCopilot && !collapsed {
                        resizeHandle(windowWidth: geo.size.width, currentWidth: dockWidth)
                        // The collapse chevron lives in `CopilotChatView`'s single
                        // header row (next to History) — no separate strip here.
                        CopilotChatView()
                            .frame(width: dockWidth)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .background(CodepetTheme.pageBackground)
            // ⌘B toggles the copilot dock (collapse / reopen). Inert off Overview:
            // toggling a dock that isn't rendered would silently flip the state and
            // surprise you with a different dock next time you came back.
            .background(
                Button("") { if showsCopilot { companyStore.dockCollapsed.toggle() } }
                    .keyboardShortcut("b", modifiers: .command)
                    .opacity(0).frame(width: 0, height: 0).accessibilityHidden(true)
            )
            // Unread bookkeeping for the collapsed bar's dot: while the dock is
            // OPEN every message counts as seen, so the dot only ever reflects what
            // arrived after it closed — and reopening clears it.
            .onChange(of: companyStore.chatMessages.count, initial: true) { _, count in
                if !collapsed { seenMessageCount = count }
            }
            .onChange(of: collapsed) { _, isCollapsed in
                if !isCollapsed { seenMessageCount = companyStore.chatMessages.count }
            }
        }
        // Settings is an OVERLAY on whatever the founder was doing, not a destination —
        // it sits outside the GeometryReader's content so it covers the top nav too, and
        // measures the whole shell so the panel centres in the window.
        .overlay {
            if let section = companyStore.settingsSection {
                SettingsModal(initial: section)
                    .transition(.opacity)
            }
        }
        // A real `.sheet`, unlike Settings: this one is a question the founder
        // must answer before the ask they typed can go anywhere, and it has a
        // "Not now" that puts them back with the refusal and a way to reopen.
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

    /// The draggable divider between the content and the copilot: hover shows the
    /// resize cursor, a drag resizes the dock, a click collapses it (⌘B also
    /// toggles). Mirrors the "Click to collapse · Drag to resize" affordance.
    private func resizeHandle(windowWidth: CGFloat, currentWidth: CGFloat) -> some View {
        let active = handleHovered || handleDragging
        return Rectangle()
            .fill(CodepetTheme.hairline)
            // Fixed 1pt, always. This used to be `handleHovered ? 2 : 1`, which made the
            // handle's own LAYOUT width part of the hover state: every hover in and out
            // shoved the content pane sideways by a point, and during a drag — where hover
            // flickers — it added a wobble on top of the one below. The highlight is an
            // overlay now, so it costs no layout.
            .frame(width: 1)
            .overlay {
                Rectangle().fill(accent.opacity(0.6)).frame(width: 2).opacity(active ? 1 : 0)
            }
            .overlay(Color.clear.frame(width: ShellLayout.dockResizeHitWidth).contentShape(Rectangle()))
            .help(uiLanguage == .vi ? "Nhấn để thu gọn (⌘B) · Kéo để đổi cỡ"
                                    : "Click to collapse (⌘B) · Drag to resize")
            .cursorOnHover(.resizeLeftRight, held: handleDragging) { handleHovered = $0 }
            .gesture(
                // `.global`, NOT the default `.local`. This gesture is attached to the
                // divider, and dragging it MOVES the divider — so in local space the
                // reported translation is (pointer moved − handle moved), and each frame's
                // new width feeds straight back into the next frame's translation. Measured
                // off a screen recording on Aug 10: the divider tracked at ~half the
                // pointer's speed and alternated back and forth every frame (33 direction
                // reversals in one drag, lag-1 autocorrelation of the per-frame step −0.52),
                // ending up 90–115pt behind the pointer at speed. It reads as lag; it is a
                // feedback loop. Global space is fixed while the handle moves through it.
                DragGesture(minimumDistance: 3, coordinateSpace: .global)
                    .onChanged { v in
                        let start = dragStartWidth ?? currentWidth
                        if dragStartWidth == nil { dragStartWidth = start }
                        handleDragging = true
                        // Divider sits left of the dock → dragging left grows the dock.
                        manualDockWidth = ShellLayout.clampDockWidth(start - v.translation.width, windowWidth: windowWidth)
                    }
                    .onEnded { _ in
                        dragStartWidth = nil
                        handleDragging = false
                    }
            )
            .onTapGesture { companyStore.dockCollapsed = true }
    }

    @ViewBuilder private var content: some View {
        // Review takes over the content area WITHOUT touching `companyStore.view`
        // — see `ShellLayout.contentSurface`. That is what makes closing it free:
        // the destination below was never navigated away from, so there is no
        // previous page to remember and restore.
        switch ShellLayout.contentSurface(destination: companyStore.view,
                                          reviewingRunId: companyStore.engineeringReviewRunId) {
        case .engineeringReview(let runId):
            if let store = companyStore.engineeringRunStore {
                EngineeringWorkspaceView(
                    runId: runId,
                    store: store,
                    onClose: { companyStore.engineeringReviewRunId = nil }
                )
            } else {
                // Reviewing an id with no store behind it cannot render anything.
                // Clearing the flag is the honest recovery: it puts the founder
                // back on their page rather than on a blank pane.
                destinationContent.onAppear { companyStore.engineeringReviewRunId = nil }
            }
        case .destination:
            destinationContent
        }
    }

    @ViewBuilder private var destinationContent: some View {
        if companyStore.view == .roadmap {
            RoadmapView()
        } else if companyStore.view == .company {
            if let dept = companyStore.selectedDeptKey {
                DepartmentDetailView(deptKey: dept, onBack: { companyStore.selectedDeptKey = nil })
            } else {
                CompanyView(onOpen: { companyStore.selectedDeptKey = $0 })
            }
        } else if companyStore.view == .tasks {
            TasksView()
        } else if companyStore.view == .library {
            LibraryView()
        } else if companyStore.view == .environment {
            EnvironmentView()
        } else {
            // .chat and .secondBrain are no longer full-content destinations
            // (chat = docked copilot; second brain = Overview toggle).
            RoadmapView()
        }
    }
}

// codepet/Views/Shell/AppShellView.swift
import SwiftUI

/// The app's top-level shell — a top nav bar (`TopNavView`), a content area
/// switching on the store's view, and a docked copilot (`CopilotChatView`) on the
/// right. The dock collapses to a slim reopen handle per `ShellLayout` when the
/// window is narrow or the user manually collapses it. Styled in CodepetTheme;
/// accents follow the active companion's color.
struct AppShellView: View {
    @EnvironmentObject var companyStore: CompanyStore
    @EnvironmentObject var appState: AppState
    @Environment(\.uiLanguage) private var uiLanguage

    private var accent: Color { PetCharacter.all[appState.activeChar]?.color ?? CodepetTheme.accentPurple }
    /// Named on the collapsed bar's placeholder ("Ask Crash anything…") so the
    /// closed copilot still says who you'd be talking to.
    private var companionName: String {
        PetCharacter.all[companyStore.company.companionId]?.name ?? "Codepet"
    }

    /// User-dragged copilot width (session-only). nil → the default half-window.
    @State private var manualDockWidth: CGFloat?
    /// Dock width captured at the start of a resize drag, so the drag delta is
    /// applied to a fixed base instead of the value we're mutating each frame.
    @State private var dragStartWidth: CGFloat?
    /// Hover state for the resize handle (brightens the divider on hover).
    @State private var handleHovered = false
    /// Message count as of the last time the dock was open — the baseline for the
    /// collapsed bar's unread dot, so reopening the dock always clears it.
    @State private var seenMessageCount = 0

    var body: some View {
        GeometryReader { geo in
            let collapsed = ShellLayout.dockCollapsed(forWidth: geo.size.width, manual: companyStore.dockCollapsed)
            // Expanded copilot defaults to half the window; a drag on the divider
            // resizes it (clamped so both panes stay usable), a click collapses it.
            let base = manualDockWidth ?? ShellLayout.dockWidth(forWidth: geo.size.width)
            let dockWidth = ShellLayout.clampDockWidth(base, windowWidth: geo.size.width)
            VStack(spacing: 0) {
                TopNavView(accent: accent)
                Divider()
                HStack(spacing: 0) {
                    // Collapsed, the copilot becomes a composer strip along the bottom
                    // of the content (`safeAreaInset`, so scroll views clear it instead
                    // of hiding under it) rather than a full-height reopen rail.
                    content
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .safeAreaInset(edge: .bottom, spacing: 0) {
                            if collapsed {
                                CollapsedChatBar(
                                    accent: accent,
                                    companionName: companionName,
                                    needsYou: CollapsedChatBarState.needsYouCount(
                                        tasks: companyStore.company.tasks),
                                    unread: CollapsedChatBarState.showsUnreadDot(
                                        messageCount: companyStore.chatMessages.count,
                                        seen: seenMessageCount),
                                    onExpand: { companyStore.dockCollapsed = false }
                                )
                            }
                        }
                    if !collapsed {
                        resizeHandle(windowWidth: geo.size.width, currentWidth: dockWidth)
                        VStack(spacing: 0) {
                            HStack {
                                Spacer()
                                Button { companyStore.dockCollapsed = true } label: {
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundColor(CodepetTheme.mutedText)
                                        .padding(6)
                                }
                                .buttonStyle(.plain)
                                .help(uiLanguage == .vi ? "Thu gọn trợ lý (⌘B)" : "Collapse copilot (⌘B)")
                            }
                            .padding(.horizontal, 8).padding(.top, 6)
                            .background(CodepetTheme.surface)
                            CopilotChatView()
                        }
                        .frame(width: dockWidth)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .background(CodepetTheme.pageBackground)
            // ⌘B toggles the copilot dock (collapse / reopen).
            .background(
                Button("") { companyStore.dockCollapsed.toggle() }
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
    }

    /// The draggable divider between the content and the copilot: hover shows the
    /// resize cursor, a drag resizes the dock, a click collapses it (⌘B also
    /// toggles). Mirrors the "Click to collapse · Drag to resize" affordance.
    private func resizeHandle(windowWidth: CGFloat, currentWidth: CGFloat) -> some View {
        Rectangle()
            .fill(handleHovered ? accent.opacity(0.6) : CodepetTheme.hairline)
            .frame(width: handleHovered ? 2 : 1)
            .overlay(Color.clear.frame(width: 11).contentShape(Rectangle()))
            .help(uiLanguage == .vi ? "Nhấn để thu gọn (⌘B) · Kéo để đổi cỡ"
                                    : "Click to collapse (⌘B) · Drag to resize")
            .onHover { inside in
                handleHovered = inside
                if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
            }
            .gesture(
                DragGesture(minimumDistance: 3)
                    .onChanged { v in
                        let start = dragStartWidth ?? currentWidth
                        if dragStartWidth == nil { dragStartWidth = start }
                        // Divider sits left of the dock → dragging left grows the dock.
                        manualDockWidth = ShellLayout.clampDockWidth(start - v.translation.width, windowWidth: windowWidth)
                    }
                    .onEnded { _ in dragStartWidth = nil }
            )
            .onTapGesture { companyStore.dockCollapsed = true }
    }

    @ViewBuilder private var content: some View {
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
        } else if companyStore.view == .settings {
            SettingsView()
        } else if companyStore.view == .billing {
            BillingView()
        } else if companyStore.view == .support {
            SupportView()
        } else {
            // .chat and .secondBrain are no longer full-content destinations
            // (chat = docked copilot; second brain = Overview toggle).
            RoadmapView()
        }
    }
}

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
    private let dockWidth: CGFloat = 380

    var body: some View {
        GeometryReader { geo in
            let collapsed = ShellLayout.dockCollapsed(forWidth: geo.size.width, manual: companyStore.dockCollapsed)
            VStack(spacing: 0) {
                TopNavView(accent: accent)
                Divider()
                HStack(spacing: 0) {
                    content.frame(maxWidth: .infinity, maxHeight: .infinity)
                    Rectangle().fill(CodepetTheme.hairline).frame(width: 1)
                    if collapsed {
                        dockHandle
                    } else {
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
                                .help(uiLanguage == .vi ? "Thu gọn trợ lý" : "Collapse copilot")
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
        }
    }

    /// Collapsed dock: a slim reopen strip.
    private var dockHandle: some View {
        Button { companyStore.dockCollapsed = false } label: {
            VStack(spacing: 8) {
                Image(systemName: "bubble.left.and.bubble.right")
                    .font(.system(size: 15, weight: .medium)).foregroundColor(accent)
                Spacer()
            }
            .padding(.top, 12).frame(width: 44).frame(maxHeight: .infinity)
            .background(CodepetTheme.surface)
        }.buttonStyle(.plain)
        .help(uiLanguage == .vi ? "Mở trợ lý" : "Open copilot")
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

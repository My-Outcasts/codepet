// codepet/Views/Shell/AppShellView.swift
import SwiftUI

/// The app's top-level shell — a native port of the web AppRoot: the left
/// `SidebarView` (brand, New chat, Recent, Workspace nav, Upgrade/account) and a
/// full-width content area switching on the store's view (chat is the default).
/// Styled in CodepetTheme.
struct AppShellView: View {
    @EnvironmentObject var companyStore: CompanyStore
    @Environment(\.uiLanguage) private var uiLanguage

    @State private var sidebarCollapsed = false

    var body: some View {
        HStack(spacing: 0) {
            if !sidebarCollapsed {
                SidebarView(collapsed: $sidebarCollapsed)
                Divider()
            }
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay(alignment: .topLeading) {
                    if sidebarCollapsed {
                        Button { sidebarCollapsed = false } label: {
                            Image(systemName: "sidebar.left").font(.system(size: 15))
                                .foregroundColor(CodepetTheme.bodyText).padding(10)
                        }.buttonStyle(.plain).padding(8)
                    }
                }
        }
        .background(CodepetTheme.pageBackground)
    }

    @ViewBuilder private var content: some View {
        if companyStore.view == .chat {
            CopilotChatView(sidebarCollapsed: sidebarCollapsed)
        } else if companyStore.view == .roadmap {
            RoadmapView()
        } else if companyStore.view == .secondBrain {
            SecondBrainView()
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
            ShellPlaceholderView(view: companyStore.view)
        }
    }
}

/// Placeholder content per destination — the real views land in later phases.
struct ShellPlaceholderView: View {
    let view: AppView
    @Environment(\.uiLanguage) private var uiLanguage
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: view.icon).font(.system(size: 32)).foregroundColor(CodepetTheme.mutedText)
            Text(view.title(uiLanguage)).font(.pixelSystem(size: 18, weight: .bold)).foregroundColor(CodepetTheme.primaryText)
            Text(uiLanguage == .vi ? "Sắp có" : "Coming soon").font(.pixelSystem(size: 12)).foregroundColor(CodepetTheme.mutedText)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

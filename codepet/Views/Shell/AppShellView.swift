// codepet/Views/Shell/AppShellView.swift
import SwiftUI

/// The app's top-level shell — a native port of the web AppRoot: a sidebar of
/// AppView destinations, a content area switching on the store's view, and a
/// (placeholder) Copilot panel. Styled in CodepetTheme; the selected item and
/// accents follow the active companion's color.
struct AppShellView: View {
    @EnvironmentObject var companyStore: CompanyStore
    @EnvironmentObject var appState: AppState
    @Environment(\.uiLanguage) private var uiLanguage
    @State private var copilotCollapsed = false
    @State private var selectedDept: String?

    private var accent: Color { PetCharacter.all[appState.activeChar]?.color ?? CodepetTheme.accentPurple }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            Divider()
            GeometryReader { geo in
                HStack(spacing: 0) {
                    content.frame(maxWidth: .infinity, maxHeight: .infinity)
                    if !copilotCollapsed {
                        Divider()
                        copilot.frame(width: geo.size.width * 0.5)   // chat = 50% of the window
                    }
                }
            }
        }
        .background(CodepetTheme.pageBackground)
    }

    @ViewBuilder private var content: some View {
        if companyStore.view == .overview {
            OverviewView()
        } else if companyStore.view == .company {
            if let dept = selectedDept {
                DepartmentDetailView(deptKey: dept, onBack: { selectedDept = nil })
            } else {
                CompanyView(onOpen: { selectedDept = $0 })
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

    // Web-faithful top bar (Topbar.tsx): brand + account menu, center nav tabs, right controls.
    private var topBar: some View {
        HStack(spacing: 14) {
            Text("Codepet").font(CodepetTheme.pixel(15)).foregroundColor(CodepetTheme.primaryText)
            AccountMenuView()
            Spacer(minLength: 20)
            HStack(spacing: 4) {
                ForEach(AppView.navTabs) { v in navTab(v) }
            }
            Spacer(minLength: 20)
            HStack(spacing: 10) {
                wakePill
                Button { selectedDept = nil; companyStore.select(.billing) } label: {
                    Text(uiLanguage == .vi ? "Nâng cấp" : "Upgrade")
                        .font(CodepetTheme.inter(12, weight: .semibold)).foregroundColor(.white)
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(Capsule().fill(CodepetTheme.primaryText))
                }.buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
    }

    private func navTab(_ v: AppView) -> some View {
        let on = companyStore.view == v
        let count = tabCount(v)
        return Button { selectedDept = nil; companyStore.select(v) } label: {
            HStack(spacing: 6) {
                Text(v.title(uiLanguage)).font(CodepetTheme.navTab())
                    .foregroundColor(on ? accent : CodepetTheme.bodyText)
                if count > 0 {
                    Text("\(count)").font(CodepetTheme.inter(9, weight: .semibold)).foregroundColor(.white)
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(Capsule().fill(CodepetTheme.accentGold))
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 8)
            .overlay(alignment: .bottom) { if on { Rectangle().fill(accent).frame(height: 2) } }
        }.buttonStyle(.plain)
    }

    private func tabCount(_ v: AppView) -> Int {
        switch v {
        case .tasks:       return TopbarCounts.tasks(companyStore.company.tasks)
        case .library:     return TopbarCounts.library(companyStore.company.library)
        case .environment: return TopbarCounts.envPending(enabled: companyStore.company.enabledTools)
        default:           return 0
        }
    }

    private var companionName: String { PetCharacter.all[companyStore.company.companionId]?.name ?? "Codepet" }

    private var wakePill: some View {
        Button { selectedDept = nil; companyStore.select(.environment) } label: {
            HStack(spacing: 5) {
                Circle().fill(CodepetTheme.accentOrange).frame(width: 6, height: 6)
                Text("⚡ " + (uiLanguage == .vi ? "Đánh thức \(companionName)" : "Wake \(companionName) up"))
                    .font(CodepetTheme.inter(12, weight: .medium))
            }
            .foregroundColor(CodepetTheme.bodyText)
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(Capsule().fill(accent.opacity(0.1)))
        }.buttonStyle(.plain)
    }

    private var copilot: some View {
        CopilotChatView()   // width is set by the shell (50% of the window)
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

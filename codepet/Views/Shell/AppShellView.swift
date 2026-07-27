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

    private var accent: Color { PetCharacter.all[appState.activeChar]?.color ?? CodepetTheme.accentPurple }

    var body: some View {
        HStack(spacing: 0) {
            AppRailView(accent: accent)
            VStack(spacing: 0) {
                topBar
                Divider()
                content.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(CodepetTheme.pageBackground)
    }

    @ViewBuilder private var content: some View {
        if companyStore.view == .chat {
            CopilotChatView()
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

    /// Slim top bar: the destination title on the left, wake pill and Upgrade on
    /// the right. Navigation itself lives in the rail.
    private var topBar: some View {
        HStack(spacing: 14) {
            Text(companyStore.view.title(uiLanguage))
                .font(CodepetTheme.inter(15, weight: .semibold))
                .foregroundColor(CodepetTheme.primaryText)
            Spacer(minLength: 20)
            HStack(spacing: 10) {
                wakePill
                Button { companyStore.selectedDeptKey = nil; companyStore.select(.billing) } label: {
                    Text(uiLanguage == .vi ? "Nâng cấp" : "Upgrade")
                        .font(CodepetTheme.inter(13.5, weight: .semibold)).foregroundColor(.white)
                        .padding(.horizontal, 13).padding(.vertical, 7)
                        .background(Capsule().fill(CodepetTheme.primaryText))
                }.buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
    }

    private var companionName: String { PetCharacter.all[companyStore.company.companionId]?.name ?? "Codepet" }

    private var wakePill: some View {
        Button { companyStore.selectedDeptKey = nil; companyStore.select(.environment) } label: {
            HStack(spacing: 5) {
                Circle().fill(CodepetTheme.accentOrange).frame(width: 6, height: 6)
                Text("⚡ " + (uiLanguage == .vi ? "Đánh thức \(companionName)" : "Wake \(companionName) up"))
                    .font(CodepetTheme.inter(13.5, weight: .medium))
            }
            .foregroundColor(CodepetTheme.bodyText)
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(Capsule().fill(accent.opacity(0.1)))
        }.buttonStyle(.plain)
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

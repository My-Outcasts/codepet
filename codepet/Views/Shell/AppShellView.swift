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

    private var accent: Color { PetCharacter.all[appState.activeChar]?.color ?? CodepetTheme.accentPurple }
    private var companyName: String {
        let n = (companyStore.company.brief.projectName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return n.isEmpty ? (uiLanguage == .vi ? "Công ty của bạn" : "Your company") : n
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            Divider()
            HStack(spacing: 0) {
                sidebar
                Divider()
                Group {
                    if companyStore.view == .overview {
                        OverviewBoardView()
                    } else if companyStore.view == .library {
                        LibraryView()
                    } else if companyStore.view == .environment {
                        EnvironmentView()
                    } else {
                        ShellPlaceholderView(view: companyStore.view)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                if !copilotCollapsed {
                    Divider()
                    copilot
                }
            }
        }
        .background(CodepetTheme.pageBackground)
    }

    private var topBar: some View {
        HStack(spacing: 10) {
            CharacterImage(appState.activeChar, size: 26)
            Text(companyName).font(.pixelSystem(size: 14, weight: .bold)).foregroundColor(CodepetTheme.primaryText)
            Spacer()
            Button { copilotCollapsed.toggle() } label: {
                Image(systemName: "bubble.left.and.bubble.right").foregroundColor(accent)
            }.buttonStyle(.plain)
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(AppView.allCases) { v in
                Button { companyStore.select(v) } label: {
                    HStack(spacing: 10) {
                        Image(systemName: v.icon).frame(width: 18)
                        Text(v.title(uiLanguage)).font(.pixelSystem(size: 13, weight: .medium))
                        Spacer()
                    }
                    .foregroundColor(companyStore.view == v ? accent : CodepetTheme.bodyText)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 8)
                        .fill(companyStore.view == v ? accent.opacity(0.12) : Color.clear))
                }.buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(10)
        .frame(width: 210, alignment: .top)
    }

    private var copilot: some View {
        CopilotChatView()
            .frame(width: 300)
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

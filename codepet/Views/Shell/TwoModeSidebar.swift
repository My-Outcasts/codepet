// codepet/Views/Shell/TwoModeSidebar.swift
import SwiftUI

/// The rail: brand, the mode switch, `+ New`, the mode-specific group, and the
/// five company surfaces — open in Ask, collapsed to one row in Developer.
///
/// The gradient belongs to `Upgrade` alone, so `+ New` is a quiet outlined row:
/// it is frequent and low-stakes, and it must not compete with the one control
/// in the rail that sells something.
struct TwoModeSidebar: View {
    @Binding var mode: WorkspaceMode
    @EnvironmentObject var companyStore: CompanyStore
    @Environment(\.uiLanguage) private var lang

    /// Collapsed by default in Developer; the founder can open it in place.
    @State private var workspaceExpanded = false

    private var accent: Color { CodepetTheme.accentPurple }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            brand
            modeSwitch
            newButton
            group
            workspace
            Spacer(minLength: 8)
            account
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 12)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(CodepetTheme.surface)
    }

    // MARK: - Pieces

    private var brand: some View {
        Button {
            // The wordmark goes home, the way a site's logo does (founder call,
            // Aug 6) — which is also the Overview answer: it is what carries it.
            companyStore.view = AppView.home
        } label: {
            Text("Codepet")
                .font(CodepetTheme.pixel(14))
                .foregroundStyle(CodepetTheme.primaryText)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(lang == .vi ? "Về trang chủ" : "Home")
    }

    private var modeSwitch: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 3) {
                ForEach(WorkspaceMode.allCases) { m in
                    Button { mode = m } label: {
                        Text(m.title(lang).uppercased())
                            .font(CodepetTheme.pixel(10))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(mode == m ? CodepetTheme.pageBackground : .clear)
                            )
                            .foregroundStyle(mode == m ? CodepetTheme.primaryText : CodepetTheme.mutedText)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(mode == m ? [.isSelected] : [])
                }
            }
            .padding(3)
            .background(
                RoundedRectangle(cornerRadius: 9).stroke(CodepetTheme.hairline, lineWidth: 1)
            )
            // Retires once Developer has been opened — guidance that outstays its
            // welcome is clutter.
            if mode == .ask && companyStore.engineeringRunStore == nil {
                Text(WorkspaceMode.hint(lang))
                    .font(CodepetTheme.pixel(9))
                    .foregroundStyle(CodepetTheme.mutedText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var newButton: some View {
        Button {
            companyStore.newChat()
            companyStore.view = TwoModeLayout.newChatDestination
        } label: {
            Text(lang == .vi ? "+ Mới" : "+ New")
                .font(CodepetTheme.body(12.5))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 9).padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 7).fill(CodepetTheme.pageBackground))
                .overlay(RoundedRectangle(cornerRadius: 7).stroke(CodepetTheme.hairline, lineWidth: 1))
                .foregroundStyle(CodepetTheme.bodyText)
        }
        .buttonStyle(.plain)
    }

    /// Ask lists recent threads; Developer lists the repo and its sessions.
    @ViewBuilder private var group: some View {
        switch mode {
        case .ask:
            VStack(alignment: .leading, spacing: 3) {
                sectionLabel(lang == .vi ? "Gần đây" : "Recent")
                if companyStore.threads.isEmpty {
                    emptyLine(lang == .vi ? "Cuộc trò chuyện của bạn sẽ ở đây."
                                          : "Your conversations appear here.")
                } else {
                    ForEach(sortThreadsByRecent(companyStore.threads).prefix(4)) { thread in
                        row(icon: "›",
                            label: thread.title ?? (lang == .vi ? "Trò chuyện mới" : "New chat"),
                            selected: thread.id == companyStore.activeThreadId) {
                            companyStore.switchThread(thread.id)
                            companyStore.view = .chat
                        }
                    }
                }
            }
        case .developer:
            VStack(alignment: .leading, spacing: 3) {
                sectionLabel(lang == .vi ? "Kho mã" : "Repo")
                if companyStore.engineeringRunStore == nil {
                    emptyLine(lang == .vi ? "Chưa liên kết." : "Nothing linked yet.")
                    sectionLabel(lang == .vi ? "Phiên" : "Sessions").padding(.top, 6)
                    emptyLine(lang == .vi ? "Một phiên cần repo trước." : "A session needs a repo first.")
                } else {
                    row(icon: "▣", label: "codepet", selected: true) {}
                    sectionLabel(lang == .vi ? "Phiên" : "Sessions").padding(.top, 6)
                    row(icon: companyStore.engineeringReviewRunId == nil ? "○" : "●",
                        label: lang == .vi ? "Phiên hiện tại" : "Current session",
                        selected: companyStore.engineeringReviewRunId != nil) {
                        companyStore.view = .chat
                    }
                }
            }
        }
    }

    /// The five never move. Developer collapses them so a session gets the
    /// vertical space — reachable in one click, not gone.
    @ViewBuilder private var workspace: some View {
        if mode.collapsesWorkspace && !workspaceExpanded {
            row(icon: "▦", label: lang == .vi ? "Không gian" : "Workspace", selected: false) {
                workspaceExpanded = true
            }
        } else {
            VStack(alignment: .leading, spacing: 3) {
                sectionLabel(lang == .vi ? "Không gian" : "Workspace")
                ForEach(WorkspaceMode.workspaceSurfaces) { surface in
                    row(icon: icon(for: surface),
                        label: surface.title(lang),
                        count: count(for: surface),
                        selected: companyStore.view == surface) {
                        companyStore.view = surface
                    }
                }
            }
        }
    }

    private var account: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()
            Button { companyStore.settingsSection = .preferences } label: {
                HStack(spacing: 8) {
                    Circle().fill(accent).frame(width: 21, height: 21)
                    Text(founderName)
                        .font(CodepetTheme.body(12))
                        .foregroundStyle(CodepetTheme.bodyText)
                    Spacer(minLength: 0)
                }
            }
            .buttonStyle(.plain)
        }
    }

    /// The brief owns the founder's name — the same source the chat greeting reads,
    /// so the rail cannot disagree with the hero about who is signed in.
    private var founderName: String {
        let raw = (companyStore.company.brief.founderName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return raw.isEmpty ? (lang == .vi ? "Nhà sáng lập" : "Founder") : raw
    }

    // MARK: - Row furniture

    private func sectionLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(CodepetTheme.pixel(9))
            .foregroundStyle(CodepetTheme.mutedText)
            .padding(.leading, 4)
    }

    private func emptyLine(_ text: String) -> some View {
        Text(text)
            .font(CodepetTheme.pixel(9))
            .foregroundStyle(CodepetTheme.mutedText)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 4).padding(.vertical, 3)
    }

    private func row(icon: String, label: String, count: Int? = nil,
                     selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(icon)
                    .font(CodepetTheme.pixel(10))
                    .foregroundStyle(CodepetTheme.mutedText)
                    .frame(width: 13)
                Text(label)
                    .font(CodepetTheme.body(12.5))
                    .lineLimit(1)
                    .foregroundStyle(selected ? CodepetTheme.primaryText : CodepetTheme.bodyText)
                Spacer(minLength: 0)
                if let count, count > 0 {
                    Text("\(count)")
                        .font(CodepetTheme.pixel(9))
                        .padding(.horizontal, 6).padding(.vertical, 3)
                        .background(Capsule().fill(CodepetTheme.accentGold))
                        .foregroundStyle(.black)
                }
            }
            .padding(.horizontal, 7).padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(selected ? CodepetTheme.pageBackground : .clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func icon(for surface: AppView) -> String {
        switch surface {
        case .roadmap:     return "◈"
        case .company:     return "◍"
        case .tasks:       return "☰"
        case .library:     return "▤"
        case .environment: return "✳"
        default:           return "·"
        }
    }

    /// Counts read the same fields the destinations themselves read — an open
    /// task is one that is not `done`, and Library counts what has been filed.
    private func count(for surface: AppView) -> Int? {
        switch surface {
        case .tasks:   return companyStore.company.tasks.filter { !$0.done }.count
        case .library: return companyStore.company.library.count
        default:       return nil
        }
    }
}

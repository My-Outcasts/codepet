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

    /// Retires the hint under the switch. `@AppStorage`, not a plain read, so the
    /// line disappears the moment Developer is first opened instead of on the next
    /// launch.
    @AppStorage(WorkspaceMode.seenDeveloperKey) private var seenDeveloper = false

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
                            .font(CodepetTheme.inter(11, weight: .semibold))
                            .tracking(0.8)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            // The selected segment is a raised card sitting in a
                            // well — `cardRaised` on `well`, the pairing main uses
                            // wherever something is lifted out of a track.
                            .background(
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .fill(mode == m ? CodepetTokens.cardRaised : .clear)
                            )
                            .overlay(
                                mode == m
                                    ? RoundedRectangle(cornerRadius: 7, style: .continuous)
                                        .stroke(CodepetTokens.cardEdge, lineWidth: 1)
                                    : nil
                            )
                            .foregroundStyle(mode == m ? CodepetTheme.accentPurple : CodepetTheme.mutedText)
                            .contentShape(Rectangle())
                            .hoverAffordance(RoundedRectangle(cornerRadius: 7, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(mode == m ? [.isSelected] : [])
                }
            }
            .padding(3)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous).fill(CodepetTokens.well)
            )
            // Retires once Developer has been opened — guidance that outstays its
            // welcome is clutter. Deliberately NOT gated on `mode`: an Ask-only
            // hint made the rail two lines taller in one mode than the other, so
            // every switch bumped `+ New` and the whole nav down the sidebar.
            if seenDeveloper == false {
                Text(WorkspaceMode.hint(lang))
                    .font(CodepetTheme.inter(10.5))
                    .lineSpacing(2)
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
                .font(CodepetTheme.inter(12.5, weight: .medium))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 9).padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(CodepetTokens.cardRaised))
                .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(CodepetTokens.cardEdge, lineWidth: 1))
                .foregroundStyle(CodepetTheme.bodyText)
                .contentShape(Rectangle())
                .hoverAffordance(RoundedRectangle(cornerRadius: 9, style: .continuous))
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
                    // The account avatar is a gradient everywhere else it appears
                    // (`AccountMenuView`, the prototype's `.acct .av`); a flat disc
                    // was the one place it read as a placeholder.
                    Circle()
                        .fill(LinearGradient(colors: [CodepetTokens.accentDeep, accent],
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 21, height: 21)
                    Text(founderName)
                        .font(CodepetTheme.inter(12, weight: .medium))
                        .foregroundStyle(CodepetTheme.bodyText)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 5).padding(.vertical, 4)
                .contentShape(Rectangle())
                .hoverAffordance(RoundedRectangle(cornerRadius: 7, style: .continuous))
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

    /// `SectionEyebrow`'s exact type spec — inter(10) regular, 1pt tracking,
    /// `CodepetTokens.faint` — which is the app's ONE section label, used by
    /// Environment, the department page and everything since.
    ///
    /// Not the `SectionEyebrow` view itself: it carries the page rhythm's 36/10
    /// padding, which is right for a scrolling page and far too much air for a
    /// 208pt rail. The type is what has to agree; the spacing belongs to the
    /// surface.
    ///
    /// `inter`, NOT `pixel`. `main` spends pixel on exactly one thing — the
    /// wordmark (`TopNavView.swift:51`).
    private func sectionLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(CodepetTheme.inter(10))
            .tracking(1)
            .foregroundStyle(CodepetTokens.faint)
            .padding(.leading, 4)
    }

    private func emptyLine(_ text: String) -> some View {
        Text(text)
            .font(CodepetTheme.inter(11))
            .foregroundStyle(CodepetTokens.faint)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 4).padding(.vertical, 3)
    }

    private func row(icon: String, label: String, count: Int? = nil,
                     selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(icon)
                    .font(CodepetTheme.inter(11))
                    .foregroundStyle(selected ? CodepetTheme.accentPurple : CodepetTokens.faint)
                    .frame(width: 13)
                Text(label)
                    .font(CodepetTheme.inter(12.5, weight: selected ? .semibold : .regular))
                    .lineLimit(1)
                    .foregroundStyle(selected ? CodepetTheme.accentPurple : CodepetTheme.bodyText)
                Spacer(minLength: 0)
                if let count, count > 0 {
                    // `TopNavView`'s badge exactly: white on gold, 9pt semibold,
                    // 5/1 padding. The rail counts the same things the top nav
                    // counted, so they should not be two different objects.
                    Text("\(count)")
                        .font(CodepetTheme.inter(9, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(Capsule().fill(CodepetTheme.accentGold))
                }
            }
            .padding(.horizontal, 7).padding(.vertical, 5)
            // Selection is the violet tint, which is how `main` marks a chosen
            // thing everywhere (`RoadmapView:174`, the Overview chrome row). It
            // used the page colour, which on the rail's own fill is a hole rather
            // than a highlight.
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(selected ? CodepetTokens.accentTint : .clear)
            )
            .contentShape(Rectangle())
            .hoverAffordance(RoundedRectangle(cornerRadius: 7, style: .continuous))
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

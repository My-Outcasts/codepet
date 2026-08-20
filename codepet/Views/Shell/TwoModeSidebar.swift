// codepet/Views/Shell/TwoModeSidebar.swift
import SwiftUI

/// The rail: brand, the mode switch, `+ New`, the mode-specific group, and the
/// five company surfaces — open in Ask, collapsed to one row in Developer.
///
/// `+ New` is a quiet outlined row: it is frequent and low-stakes, and nothing in
/// the rail should shout louder than the work.
///
/// This used to say the gradient "belongs to `Upgrade` alone". There is no Upgrade
/// control and never was — `BillingPanel` records that the web view never had one
/// either, because there is no billing backend. The conclusion was right and the
/// reason was fiction, which is worse than no reason: the next person reads it,
/// looks for `Upgrade`, and finds nothing.
struct TwoModeSidebar: View {
    /// How many conversations the rail lists before offering the full history.
    ///
    /// 8, up from 4. The rail was leaving ~460pt of dead space below Environment
    /// while capping the one list that grows, and on this surface Recent is the ONLY
    /// thread switcher — the dock's history icon is hidden here.
    static let recentShown = 8

    @Binding var mode: WorkspaceMode
    @EnvironmentObject var companyStore: CompanyStore
    /// Carries the signed-in account's display name, the second source for who
    /// the founder is when the brief has no name.
    @EnvironmentObject var appState: AppState
    @Environment(\.uiLanguage) private var lang

    /// Collapsed by default in Developer; the founder can open it in place.
    @State private var workspaceExpanded = false

    /// Retires the hint under the switch. `@AppStorage`, not a plain read, so the
    /// line disappears the moment Developer is first opened instead of on the next
    /// launch.
    @AppStorage(WorkspaceMode.seenDeveloperKey) private var seenDeveloper = false

    /// The conversation search. View state, not company state — a query is not a
    /// decision and nothing should persist it.
    @State private var query = ""

    /// The shell owns the rail's geometry; this is the same key, so the collapse
    /// button in the brand row and the shell's divider drive one value.
    @AppStorage(TwoModeLayout.railCollapsedKey) private var railCollapsed = false

    private var accent: Color { CodepetTheme.accentPurple }

    /// Fixed block, then the list that grows, then the account.
    ///
    /// `group` (Recent in Ask, Sessions in Developer) used to sit ABOVE `workspace`,
    /// which is backwards for the one region that grows: every new conversation
    /// pushed the five fixed surfaces further down, and the rail still ended in
    /// ~460pt of dead space because the list was capped rather than allowed to fill
    /// it. Claude Code puts its fixed rows at the top and lets "Chats and tasks"
    /// take everything below, scrolling on its own — which is why its sidebar has no
    /// empty band. Same rule here, and it holds in Developer too: the collapsed
    /// Workspace row is fixed, the session list is what grows.
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            brand
            modeSwitch
            newButton
            if mode == .ask { searchField }
            workspace
            // The scroller owns the leftover height, so the list fills the rail
            // instead of leaving a band under it — and long lists scroll here rather
            // than pushing the account row off the bottom.
            ScrollView {
                group.frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: .infinity)
            .scrollBounceBehavior(.basedOnSize)
            account
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 12)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(CodepetTheme.surface)
    }

    /// Find a conversation by name — the magnifier Claude Code anchors its sidebar
    /// with, and the affordance this rail was missing most: it lists a slice of the
    /// threads and nothing else searched them.
    ///
    /// Ask only. Developer's list is sessions on one repo, which is short by
    /// construction — a session owns a branch — so a field there would be furniture.
    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11))
                .foregroundStyle(CodepetTokens.faint)
            TextField(lang == .vi ? "Tìm cuộc trò chuyện" : "Search conversations",
                      text: $query)
                .textFieldStyle(.plain)
                .font(CodepetTheme.inter(CodepetType.subheadline))
                .foregroundStyle(CodepetTheme.bodyText)
            if ThreadSearch.isSearching(query) {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(CodepetTokens.faint)
                }
                .buttonStyle(.plain)
                .help(lang == .vi ? "Xoá" : "Clear")
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(CodepetTokens.well))
    }

    // MARK: - Pieces

    /// The wordmark, and the collapse control beside it.
    ///
    /// The collapse button lives HERE, visible whenever the rail is open, because the
    /// alternatives are not discoverable: the divider is a 1pt line, and ⌘B is
    /// something you have to already know. Claude Code keeps its panel icon at the
    /// top of the sidebar permanently, and the prototype's brand row carries the same
    /// `◨` glyph — which I skipped when this was built, on the grounds that it would
    /// be decoration until the rail could actually collapse. It can now, so it isn't.
    private var brand: some View {
        HStack(spacing: 8) {
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

            Spacer(minLength: 0)

            // Same `@AppStorage` key the shell owns — AppStorage is shared by key, so
            // the two stay in step with no binding threaded through.
            Button { railCollapsed = true } label: {
                Image(systemName: "sidebar.left")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(CodepetTokens.faint)
                    .padding(4)
                    .contentShape(Rectangle())
                    .hoverAffordance(RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
            .buttonStyle(.plain)
            .help(lang == .vi ? "Thu gọn thanh bên (⌘B)" : "Collapse sidebar (⌘B)")
        }
    }

    private var modeSwitch: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 3) {
                ForEach(WorkspaceMode.allCases) { m in
                    Button { mode = m } label: {
                        Text(m.title(lang).uppercased())
                            .font(CodepetTheme.inter(CodepetType.subheadline, weight: .semibold))
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
                    .font(CodepetTheme.inter(CodepetType.footnote))
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
                .font(CodepetTheme.inter(CodepetType.body, weight: .medium))
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
                    let untitled = lang == .vi ? "Trò chuyện mới" : "New chat"
                    let searching = ThreadSearch.isSearching(query)
                    // Searching lifts the cap. Filtering a list that is already
                    // truncated to 8 would search the slice rather than the threads —
                    // the founder would type a title they can remember and be told it
                    // does not exist.
                    let all = ThreadSearch.matches(sortThreadsByRecent(companyStore.threads),
                                                   query: query, untitled: untitled)
                    if searching && all.isEmpty {
                        emptyLine(lang == .vi ? "Không có kết quả." : "No matches.")
                    }
                    // 8, not 4. The rail had ~460pt of dead space below Environment
                    // while capping the one list that could fill it — and this is the
                    // only thread switcher on this surface.
                    ForEach(searching ? all : Array(all.prefix(Self.recentShown))) { thread in
                        row(symbol: "bubble.left",
                            label: thread.title ?? untitled,
                            selected: thread.id == companyStore.activeThreadId) {
                            companyStore.switchThread(thread.id)
                            companyStore.view = .chat
                        }
                    }
                    // Without this, threads past the cap are UNREACHABLE: `showHistory`
                    // lives in `CopilotChatView` and was toggled only by the dock header
                    // this shell hides. Claude Code's sidebar has the same escape — its
                    // chat list ends in "Show more".
                    if !searching && all.count > Self.recentShown {
                        row(symbol: "clock.arrow.circlepath",
                            label: lang == .vi
                                ? "Tất cả (\(all.count))" : "All conversations (\(all.count))",
                            selected: false) {
                            companyStore.view = .chat
                            companyStore.historyRequested = true
                        }
                    }
                }
            }
        case .developer:
            VStack(alignment: .leading, spacing: 3) {
                sectionLabel(lang == .vi ? "Kho mã" : "Repo")
                // BOTH doors, via the same helper the pane uses. This checked
                // `engineeringRunStore` alone — the CLOUD path — so a folder linked
                // on this Mac left the rail insisting nothing was linked while the
                // pane beside it had already woken up. The identical defect was
                // fixed in `developerPane` days ago and `developerIsAwake` was
                // extracted for it; this call site was simply never updated, which
                // is the argument for the helper existing at all.
                if !TwoModeLayout.developerIsAwake(
                        projectLink: companyStore.activeProjectLink != nil,
                        cloudRun: companyStore.engineeringRunStore != nil) {
                    emptyLine(lang == .vi ? "Chưa liên kết." : "Nothing linked yet.")
                    sectionLabel(lang == .vi ? "Phiên" : "Sessions").padding(.top, 6)
                    emptyLine(lang == .vi ? "Một phiên cần repo trước." : "A session needs a repo first.")
                } else {
                    // The folder that is actually linked, not a hardcoded name. A
                    // rail that says "codepet" while pointed at someone else's
                    // directory is worse than saying nothing.
                    row(symbol: "folder",
                        label: companyStore.activeProjectLink
                            .map { Project.nameFromPath($0.path) } ?? "codepet",
                        selected: true) {
                        companyStore.select(.environment)
                    }
                    sectionLabel(lang == .vi ? "Phiên" : "Sessions").padding(.top, 6)
                    row(symbol: companyStore.engineeringReviewRunId == nil ? "circle" : "circle.fill",
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
            row(symbol: "square.grid.2x2", label: lang == .vi ? "Không gian" : "Workspace", selected: false) {
                workspaceExpanded = true
            }
        } else {
            VStack(alignment: .leading, spacing: 3) {
                sectionLabel(lang == .vi ? "Không gian" : "Workspace")
                ForEach(WorkspaceMode.workspaceSurfaces) { surface in
                    row(symbol: symbol(for: surface),
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
                        .font(CodepetTheme.inter(CodepetType.body, weight: .medium))
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

    /// Who is signed in, through the one resolver the hero also goes through — so
    /// the rail cannot disagree with it. It could before, and did: this returned
    /// "Founder" while the hero returned "there", both visible at once.
    private var founderName: String {
        FounderName.label(brief: companyStore.company.brief,
                          accountName: appState.displayName, language: lang)
    }

    // MARK: - Row furniture

    /// `SectionEyebrow`'s exact type spec — inter(CodepetType.footnote) regular, 1pt tracking,
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
            .font(CodepetTheme.inter(CodepetType.footnote))
            .tracking(1)
            .foregroundStyle(CodepetTokens.faint)
            .padding(.leading, 4)
    }

    private func emptyLine(_ text: String) -> some View {
        Text(text)
            .font(CodepetTheme.inter(CodepetType.subheadline))
            .foregroundStyle(CodepetTokens.faint)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 4).padding(.vertical, 3)
    }

    private func row(symbol: String, label: String, count: Int? = nil,
                     selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                // SF Symbols, not unicode glyphs. `◈ ◍ ☰ ▤ ✳` are TEXT characters
                // borrowed as icons, so each one carries its own font's stroke weight,
                // optical size and baseline — at rail size they read as five unrelated
                // shapes rather than one set. Claude Code's sidebar uses real icons, and
                // a symbol set is the only way the row's glyphs agree with each other.
                Image(systemName: symbol)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(selected ? CodepetTheme.accentPurple : CodepetTokens.faint)
                    .frame(width: 15)
                Text(label)
                    .font(CodepetTheme.inter(CodepetType.body, weight: selected ? .semibold : .regular))
                    .lineLimit(1)
                    .foregroundStyle(selected ? CodepetTheme.accentPurple : CodepetTheme.bodyText)
                Spacer(minLength: 0)
                if let count, count > 0 {
                    // `TopNavView`'s badge exactly: white on gold, 9pt semibold,
                    // 5/1 padding. The rail counts the same things the top nav
                    // counted, so they should not be two different objects.
                    Text("\(count)")
                        .font(CodepetTheme.inter(CodepetType.footnote, weight: .semibold))
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

    /// One SF Symbol per surface. Chosen for what the page IS, not for decoration:
    /// a roadmap is a map, Company is the departments, Tasks is a checklist, Library
    /// is what has been filed, Environment is the tooling.
    private func symbol(for surface: AppView) -> String {
        switch surface {
        case .roadmap:     return "map"
        case .company:     return "building.2"
        case .tasks:       return "checklist"
        case .library:     return "books.vertical"
        case .environment: return "wrench.and.screwdriver"
        default:           return "circle"
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

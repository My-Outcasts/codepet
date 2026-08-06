// codepet/Views/Environment/EnvironmentView.swift
import SwiftUI

/// The Environment = the company's toolkit, laid out like the web `EnvironmentView`:
/// the companion's recommendation strip (`.env-byte`), a grid of recommended cards
/// (`.erec`/`.rcard`), then "Browse all" — one card per category (`.env-card`) whose
/// items are hairline-separated rows (`.erow`).
struct EnvironmentView: View {
    @EnvironmentObject var companyStore: CompanyStore
    @Environment(\.uiLanguage) private var lang
    @Environment(\.colorScheme) private var scheme

    private var isDark: Bool { scheme == .dark }
    private var enabled: Set<String> { companyStore.company.enabledTools }
    /// web `recs` = every recommended item, on or off (an enabled one shows its
    /// "done" state in the card rather than dropping out of the grid).
    private var recs: [ToolItem] { Toolkit.recommended }
    // Recommended-but-off connectors — the accounts still needing a founder to connect
    // them (same "needs you" tag basis the recommendation cards show).
    private var needsYouCount: Int {
        recs.filter { $0.category == .connectors && !enabled.contains($0.id) }.count
    }
    private var stageLabel: String {
        let s = (companyStore.company.brief.stage ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return (s.isEmpty ? "Building" : s).lowercased()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header.viewHeadPadding()
            ScrollView {
                // Spacing comes from `CodepetTokens.Space`, not the web's `.envwrap`
                // numbers — one rhythm across every tab.
                VStack(alignment: .leading, spacing: 0) {
                    linkedProjectSection
                    sectionEyebrow(lang == .vi ? "Đề xuất cho dự án của bạn" : "Recommended for your project")
                    recommendationGrid
                    sectionEyebrow(lang == .vi ? "Xem tất cả" : "Browse all")
                    browseAll
                }
                .padding(.top, CodepetTokens.Space.headToBody).padding(.horizontal, 26).padding(.bottom, CodepetTokens.Space.pageBottom)
                .pageColumn()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        // The server owns connector state, so re-read it whenever this surface
        // appears — a consent completed in another window must not leave a stale
        // "Connect" button here.
        .task { await companyStore.refreshConnectorStatus() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(lang == .vi ? "Môi trường của bạn" : "Your Environment")
                .font(CodepetTheme.inter(28, weight: .semibold))
                .tracking(-0.5)
                .foregroundColor(CodepetTheme.primaryText)
            introParagraph
            Button { askCompanion(about: nil) } label: {
                HStack(spacing: 6) {
                    Image(systemName: "questionmark.bubble")
                        .font(.system(size: 11, weight: .medium))
                    Text(lang == .vi ? "Hỏi nên thiết lập gì" : "Ask what to set up")
                        .font(CodepetTheme.inter(12.5, weight: .semibold))
                }
                .foregroundColor(CodepetTheme.accentPurple)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .overlay(Capsule().stroke(CodepetTheme.hairline))
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .padding(.top, 8)
        }
    }

    /// Seed a real founder turn into the copilot, scoped to a category when the ask
    /// came from one. The Environment surface has no dock — `ShellLayout
    /// .showsCopilot(in: .environment)` is false — so this navigates to `.chat`
    /// rather than opening a panel in place. The question is sent as the founder's
    /// own message so the transcript reads honestly on a later scroll-back.
    private func askCompanion(about cat: ToolCategory?) {
        let seed: String
        if let cat {
            let verb = cat.enableVerb(lang).lowercased()
            seed = lang == .vi
                ? "Mình nên \(verb) \(cat.label(lang).lowercased()) nào cho công ty của mình?"
                : "Which \(cat.label(lang).lowercased()) should I \(verb) for my company?"
        } else {
            seed = lang == .vi
                ? "Mình nên thiết lập gì trong môi trường của mình?"
                : "What should I set up in my environment?"
        }
        companyStore.dockCollapsed = false
        companyStore.select(.chat)
        Task { await companyStore.sendChat(seed, language: lang, founderAsk: seed) }
    }

    /// web `.env-sech` — 10px, 1px tracking, uppercase, --t-4. Spacing is the shared
    /// section rhythm: a large gap above, a small one below, so the label reads as
    /// belonging to the group it introduces.
    private func sectionEyebrow(_ text: String) -> some View {
        Text(text.uppercased())
            .font(CodepetTheme.inter(10, weight: .regular))
            .tracking(1)
            .foregroundColor(CodepetTokens.faint)
            .padding(.top, CodepetTokens.Space.sectionAbove).padding(.horizontal, 2).padding(.bottom, CodepetTokens.Space.sectionBelow)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// What the companion makes of this page — one paragraph, in its voice.
    ///
    /// Four steps to get here, all founder calls: it began as an accent-tinted
    /// full-width strip below the "Ask what to set up" button (web `.env-byte`), moved up
    /// under the subtitle and lost its card, then ran on directly from the subtitle
    /// sentence (Aug 5). On Aug 6 the founder cut the subtitle — "Set up Codepet's
    /// toolkit … work for you" restated the tab it sits in — leaving the companion's
    /// read as the whole paragraph.
    ///
    /// No sprite. An inline `Text(Image("char-…"))` was tried and is a trap: inline
    /// sizing-to-the-line holds for SF Symbols, NOT for asset-catalog images, which
    /// render at intrinsic size — the companion filled the page (founder caught it,
    /// Aug 5). A leading `CharacterImage` sibling cannot work either, because a
    /// paragraph will not flow around a sibling view, and flowing is the point.
    ///
    /// The voice still reads without a marker: "here's the toolkit **I'd** set up"
    /// is plainly the companion talking, not the product describing itself.
    private var introParagraph: some View {
        companionText
            .font(CodepetTheme.inter(15))
            .foregroundColor(CodepetTheme.mutedText)
            .lineSpacing(15 * 0.42)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // "Linked project" — the repo the coding agent edits, linked via ProjectLinker
    // (shared with the chat card's `.noProject` offer). ProjectLink has no displayName;
    // derive one from the path the way Project.nameFromPath does elsewhere.
    private var linkedProjectSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text((lang == .vi ? "Dự án đã liên kết" : "Linked project").uppercased())
                .font(CodepetTheme.inter(11, weight: .semibold))
                .foregroundColor(CodepetTheme.mutedText)
            if let link = companyStore.activeProjectLink {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(Project.nameFromPath(link.path))
                            .font(CodepetTheme.inter(13, weight: .semibold))
                            .foregroundColor(CodepetTheme.primaryText)
                        Text(link.path)
                            .font(CodepetTheme.inter(11)).foregroundColor(CodepetTheme.mutedText)
                            .lineLimit(1).truncationMode(.middle)
                    }
                    Spacer()
                    Button(lang == .vi ? "Đổi" : "Change") {
                        ProjectLinker.pickAndLink(into: companyStore, language: lang)
                    }.buttonStyle(.plain).foregroundColor(CodepetTheme.accentPurple)
                }
            } else {
                Button {
                    ProjectLinker.pickAndLink(into: companyStore, language: lang)
                } label: {
                    Text(lang == .vi ? "Liên kết một dự án…" : "Link a project…")
                        .font(CodepetTheme.inter(12, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(Capsule().fill(CodepetTheme.accentPurple))
                }.buttonStyle(.plain)
            }
        }
        .padding(.bottom, 24)
    }

    /// The web bolds the stage inside the sentence (`.env-byte .txt b`).
    private var companionText: Text {
        // 15 to match `introParagraph`'s size — a 13.5 bold span inside a 15pt
        // paragraph reads as a rendering mistake rather than emphasis.
        let boldStage = Text(stageLabel)
            .font(CodepetTheme.inter(15, weight: .semibold))
            .foregroundColor(CodepetTheme.primaryText)
        if lang == .vi {
            let tail = needsYouCount > 0 ? " — bạn chỉ cần kết nối \(needsYouCount) tài khoản." : "."
            return Text("Dựa trên ") + boldStage
                 + Text(" của bạn, đây là bộ công cụ mình sẽ thiết lập\(tail)")
        }
        let plural = needsYouCount > 1 ? "s" : ""
        let tail = needsYouCount > 0
            ? " — you just need to connect \(needsYouCount) account\(plural)."
            : "."
        return Text("Based on your ") + boldStage
             + Text(", here's the toolkit I'd set up. I've turned on the skills and agents I can\(tail)")
    }

    // MARK: Recommended — web `.erec` grid of `.rcard`s

    private var recommendationGrid: some View {
        // web: repeat(auto-fill, minmax(300px, 1fr)) with a 14px gap
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 14)],
                  alignment: .leading, spacing: 14) {
            ForEach(recs) { item in recCard(item) }
        }
    }

    private func recCard(_ item: ToolItem) -> some View {
        let rc = item.category.tint
        let on = enabled.contains(item.id)
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {   // .rc-top
                Text(item.badge)
                    .font(CodepetTheme.inter(11, weight: .semibold))
                    .foregroundColor(rc)
                    .frame(width: 34, height: 34)
                    .background(RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(rc.opacity(0.16)))
                Text(item.category.label(lang).uppercased())
                    .font(CodepetTheme.inter(9))
                    .tracking(0.6)
                    .foregroundColor(rc)
            }
            .padding(.bottom, 11)

            Text(item.name)
                .font(CodepetTheme.inter(15, weight: .semibold))
                .foregroundColor(CodepetTheme.primaryText)
                .fixedSize(horizontal: false, vertical: true)
            Text(item.why ?? item.detail)
                .font(CodepetTheme.inter(12.5))
                .foregroundColor(CodepetTheme.bodyText)
                .lineSpacing(12.5 * 0.5)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 5)

            // .rc-act sits at the card's bottom (margin-top: auto)
            Spacer(minLength: 0)
            HStack(spacing: 10) {
                if on {
                    HStack(spacing: 7) {   // .rc-done
                        Text("✓")
                            .font(CodepetTheme.inter(10, weight: .bold))
                            .foregroundColor(.white)
                            .frame(width: 18, height: 18)
                            .background(Circle().fill(rc))
                        Text(item.category.onLabel(lang))
                            .font(CodepetTheme.inter(12.5, weight: .semibold))
                            .foregroundColor(CodepetTheme.bodyText)
                    }
                } else {
                    Button { Task { await companyStore.toggleTool(id: item.id) } } label: {
                        Text(item.category.enableVerb(lang))   // .rc-btn
                            .font(CodepetTheme.inter(12.5, weight: .semibold))
                            .foregroundColor(rc)
                            .padding(.horizontal, 16).padding(.vertical, 7)
                            .background(RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .fill(CodepetTheme.surface))
                            .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .stroke(rc.opacity(0.45), lineWidth: 1))
                    }.buttonStyle(.plain)
                    if item.category == .connectors {
                        Text((lang == .vi ? "cần bạn" : "needs you").uppercased())   // .rc-you
                            .font(CodepetTheme.inter(9.5, weight: .bold))
                            .tracking(0.3)
                            .foregroundColor(rc)
                    }
                }
            }
            .padding(.top, 15)
        }
        .padding(.horizontal, 17).padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        // web: fill = color-mix(rc 8%, surface), border = color-mix(rc 26%, transparent)
        .background(RoundedRectangle(cornerRadius: 15, style: .continuous)
            .fill(CodepetTheme.surface))
        .background(RoundedRectangle(cornerRadius: 15, style: .continuous)
            .fill(rc.opacity(0.08)))
        .overlay(RoundedRectangle(cornerRadius: 15, style: .continuous)
            .stroke(rc.opacity(0.26), lineWidth: 1))
    }

    // MARK: Browse all — web `.ebrowse` grid of `.ereg` groups

    private var browseAll: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 20)],
                  alignment: .leading, spacing: 20) {
            ForEach(ToolCategory.allCases) { cat in categorySection(cat) }
        }
    }

    private func categorySection(_ cat: ToolCategory) -> some View {
        let items = Toolkit.items(in: cat)
        let onCount = items.filter { enabled.contains($0.id) }.count
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {   // .ereg-h
                Text(cat.label(lang).uppercased())
                    .font(CodepetTheme.inter(10))
                    .tracking(1)
                    .foregroundColor(CodepetTheme.mutedText)
                Text("\(onCount)/\(items.count)")
                    .font(CodepetTheme.inter(11))
                    .foregroundColor(CodepetTokens.faint)
            }
            .padding(.horizontal, 4).padding(.bottom, 9)

            // ONE card per category; rows are separated by hairlines (`.erow + .erow`)
            VStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element.id) { i, item in
                    if i > 0 { Rectangle().fill(CodepetTokens.cardEdge).frame(height: 1) }
                    ToolRowView(item: item, isOn: enabled.contains(item.id))
                }
                Rectangle().fill(CodepetTokens.cardEdge).frame(height: 1)
                notSureRow(cat)
            }
            .cardChrome(radius: 14, dark: isDark)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The last row of every category card: the founder who doesn't know which of
    /// these thirteen items matters for *their* company taps here and gets the
    /// question asked for them, already scoped to this category.
    private func notSureRow(_ cat: ToolCategory) -> some View {
        Button { askCompanion(about: cat) } label: {
            HStack(spacing: 7) {
                Image(systemName: "questionmark.bubble")
                    .font(.system(size: 11, weight: .medium))
                Text(lang == .vi
                     ? "Chưa chắc nên \(cat.enableVerb(lang).lowercased()) gì?"
                     : "Not sure what to \(cat.enableVerb(lang).lowercased())?")
                    .font(CodepetTheme.inter(12.5))
                Spacer(minLength: 0)
            }
            .foregroundColor(CodepetTheme.mutedText)
            .padding(.horizontal, 14).padding(.vertical, 11)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// One toolkit row — web `.erow`: category-tinted 30pt badge, name (+ usage
/// receipt), and the enable/on button (`.eb`) pinned right.
struct ToolRowView: View {
    let item: ToolItem
    let isOn: Bool
    @EnvironmentObject var companyStore: CompanyStore
    @Environment(\.uiLanguage) private var lang
    @State private var hovered = false
    @State private var connecting = false

    /// The connector behind this row, when a real consent flow exists for it.
    ///
    /// `nil` for skills and agents — which are genuine local flips — and also for
    /// connectors whose OAuth is not built yet. Those keep the toggle they have
    /// today rather than being quietly disabled; see the note in the PR.
    private var provider: ConnectorProvider? {
        item.category == .connectors ? ConnectorProvider(rawValue: item.id) : nil
    }

    /// A real connector reports the server's view of whether a token exists. Only
    /// a local toggle may report the local flag.
    private var on: Bool {
        if let provider { return companyStore.connectedProviders.contains(provider.toolId) }
        return isOn
    }

    var body: some View {
        HStack(spacing: 13) {
            Text(item.badge)   // .eic
                .font(CodepetTheme.inter(10, weight: .semibold))
                .foregroundColor(item.category.tint)
                .frame(width: 30, height: 30)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(item.category.tint.opacity(0.14)))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(item.category.tint.opacity(0.3), lineWidth: 1))
            VStack(alignment: .leading, spacing: 2) {   // .en
                Text(item.name)
                    .font(CodepetTheme.inter(14, weight: .medium))
                    .foregroundColor(CodepetTheme.primaryText)
            }
            Spacer(minLength: 8)
            Button {
                if let provider {
                    // A real connector: consent, then reconcile from the server.
                    // Never flips a local flag on its own — the token has to exist.
                    connecting = true
                    Task {
                        await companyStore.connectProvider(provider)
                        connecting = false
                    }
                } else {
                    Task { await companyStore.toggleTool(id: item.id) }
                }
            } label: {
                if connecting {
                    ProgressView()
                        .controlSize(.small)
                        .padding(.horizontal, 15).padding(.vertical, 4)
                } else if on {
                    // web `.eb.on` — borderless, quiet: a filled tick + muted label
                    HStack(spacing: 6) {
                        Text("✓")
                            .font(CodepetTheme.inter(10, weight: .bold))
                            .foregroundColor(.white)
                            .frame(width: 18, height: 18)
                            .background(Circle().fill(CodepetTheme.accentPurple))
                        Text(item.category.onLabel(lang))
                            .font(CodepetTheme.inter(12))
                            .foregroundColor(CodepetTheme.mutedText)
                    }
                    .padding(6)
                } else {
                    Text(item.category.enableVerb(lang))
                        .font(CodepetTheme.inter(12, weight: .semibold))
                        .foregroundColor(CodepetTheme.accentPurple)
                        .padding(.horizontal, 15).padding(.vertical, 6)
                        .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(CodepetTheme.surface))
                        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(CodepetTokens.accentLine, lineWidth: 1))
                }
            }
            .buttonStyle(.plain)
            .fixedSize()
            .disabled(connecting)
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(hovered ? CodepetTokens.surface2 : Color.clear)   // .erow:hover
        .onHover { h in hovered = h }
    }
}

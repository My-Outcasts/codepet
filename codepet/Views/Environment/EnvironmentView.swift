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
                // web `.envwrap { padding: 18px 26px 48px }`
                VStack(alignment: .leading, spacing: 0) {
                    companionLine
                    linkedProjectSection
                    sectionEyebrow(lang == .vi ? "Đề xuất cho dự án của bạn" : "Recommended for your project")
                    recommendationGrid
                    sectionEyebrow(lang == .vi ? "Xem tất cả" : "Browse all")
                        .padding(.top, 36)   // web inline `marginTop: 36`
                    browseAll
                }
                .padding(.top, 18).padding(.horizontal, 26).padding(.bottom, 48)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(lang == .vi ? "Môi trường Claude Code của bạn" : "Your Claude Code environment")
                .font(CodepetTheme.inter(28, weight: .semibold))
                .tracking(-0.5)
                .foregroundColor(CodepetTheme.primaryText)
            Text(lang == .vi
                 ? "Thiết lập bộ công cụ của Codepet — kỹ năng, kết nối và trợ lý — để nó có thể làm nhiều việc hơn cho bạn."
                 : "Set up Codepet's toolkit — skills, connectors, and agents — so it can do more of the work for you.")
                .font(CodepetTheme.inter(15))
                .foregroundColor(CodepetTheme.mutedText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// web `.env-sech` — 10px, 1px tracking, uppercase, --t-4, 14px below.
    private func sectionEyebrow(_ text: String) -> some View {
        Text(text.uppercased())
            .font(CodepetTheme.inter(10, weight: .regular))
            .tracking(1)
            .foregroundColor(CodepetTokens.faint)
            .padding(.horizontal, 2).padding(.bottom, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// web `.env-byte` — accent-tinted strip, 14pt radius, 13.5px copy, 24px below.
    private var companionLine: some View {
        HStack(alignment: .top, spacing: 11) {
            CharacterImage(companyStore.company.companionId, size: 28)
            companionText
                .font(CodepetTheme.inter(13.5))
                .foregroundColor(CodepetTheme.bodyText)
                .lineSpacing(13.5 * 0.55)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(CodepetTheme.accentPurple.opacity(0.08)))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
            .stroke(CodepetTheme.accentPurple.opacity(0.20), lineWidth: 1))
        .padding(.top, 2).padding(.bottom, 24)
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
        let boldStage = Text(stageLabel)
            .font(CodepetTheme.inter(13.5, weight: .semibold))
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
            }
            .cardChrome(radius: 14, dark: isDark)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
            Button { Task { await companyStore.toggleTool(id: item.id) } } label: {
                if isOn {
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
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(hovered ? CodepetTokens.surface2 : Color.clear)   // .erow:hover
        .onHover { h in hovered = h }
    }
}

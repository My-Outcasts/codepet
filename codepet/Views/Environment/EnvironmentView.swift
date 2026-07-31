// codepet/Views/Environment/EnvironmentView.swift
import SwiftUI

/// The Environment = the company's toolkit. A recommendations strip (recommended-but-off
/// items) over category sections of skills/connectors/agents with per-item toggles.
struct EnvironmentView: View {
    @EnvironmentObject var companyStore: CompanyStore
    @EnvironmentObject var projectStore: ProjectStore
    @Environment(\.uiLanguage) private var lang

    private var enabled: Set<String> { companyStore.company.enabledTools }
    private var recs: [ToolItem] { Toolkit.recommended.filter { !enabled.contains($0.id) } }
    // Recommended-but-off connectors — the accounts still needing a founder to connect
    // them (same "needs you" tag basis the recommendation rows already show).
    private var needsYouCount: Int { recs.filter { $0.category == .connectors }.count }
    private var stageLabel: String {
        let s = (companyStore.company.brief.stage ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return (s.isEmpty ? "Building" : s).lowercased()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                companionLine
                linkedProject
                if !recs.isEmpty { recommendations }
                ForEach(ToolCategory.allCases) { cat in
                    categorySection(cat)
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(lang == .vi ? "Môi trường Claude Code của bạn" : "Your Claude Code environment")
                .font(CodepetTheme.title()).foregroundColor(CodepetTheme.primaryText)
            Text(lang == .vi
                 ? "Thiết lập bộ công cụ của Codepet — kỹ năng, kết nối và trợ lý — để nó có thể làm nhiều việc hơn cho bạn."
                 : "Set up Codepet's toolkit — skills, connectors, and agents — so it can do more of the work for you.")
                .font(CodepetTheme.subtitle()).foregroundColor(CodepetTheme.mutedText)
        }
    }

    // Companion "why this toolkit" line (web env-byte): explains the recommendation set
    // in the founder's own stage, and flags how many accounts still need connecting.
    private var companionLine: some View {
        HStack(alignment: .top, spacing: 10) {
            CharacterImage(companyStore.company.companionId, size: 28)
            Text(companionText)
                .font(.pixelSystem(size: 12))
                .foregroundColor(CodepetTheme.bodyText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(CodepetTheme.accentPurple.opacity(0.08)))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(CodepetTheme.accentPurple.opacity(0.25), lineWidth: 1))
    }

    private var companionText: String {
        if lang == .vi {
            let base = "Dựa trên giai đoạn \(stageLabel), đây là bộ công cụ mình sẽ thiết lập"
            return needsYouCount > 0
                ? base + " — bạn chỉ cần kết nối \(needsYouCount) tài khoản."
                : base + "."
        }
        let base = "Based on your \(stageLabel), here's the toolkit I'd set up"
        return needsYouCount > 0
            ? base + " — you just need to connect \(needsYouCount) account\(needsYouCount > 1 ? "s" : "")."
            : base + "."
    }

    private var recommendations: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(lang == .vi ? "Bộ công cụ đề xuất" : "Recommended toolkit")
                .font(.pixelSystem(size: 13, weight: .bold))
                .foregroundColor(CodepetTheme.primaryText)
            ForEach(recs) { item in
                CodepetCard {
                    HStack(spacing: 10) {
                        ToolBadge(item: item)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.name)
                                .font(.pixelSystem(size: 12, weight: .semibold))
                                .foregroundColor(CodepetTheme.primaryText)
                            if let why = item.why {
                                Text(why)
                                    .font(.pixelSystem(size: 11))
                                    .foregroundColor(CodepetTheme.mutedText)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        Spacer()
                        Button { Task { await companyStore.toggleTool(id: item.id) } } label: {
                            Text(item.category.enableVerb(lang))
                                .font(.pixelSystem(size: 10, weight: .semibold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 10).padding(.vertical, 4)
                                .background(Capsule().fill(item.category.tint))
                        }.buttonStyle(.plain)
                        if item.category == .connectors && !enabled.contains(item.id) {
                            Text(lang == .vi ? "cần bạn" : "needs you")
                                .font(.pixelSystem(size: 9, weight: .bold))
                                .foregroundColor(item.category.tint)
                                .textCase(.uppercase)
                        }
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    // MARK: - Linked project (coding agent, 2C-3)

    /// The coding agent's project surface: when a project is linked, a status row
    /// (path + git / CLAUDE.md badges + Change…); otherwise a link button plus
    /// one-tap chips for auto-detected roots. All linking goes through ProjectLinker
    /// so the CLAUDE.md-bootstrap consent is asked once, in one place.
    @ViewBuilder private var linkedProject: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(lang == .vi ? "DỰ ÁN ĐÃ LIÊN KẾT" : "LINKED PROJECT")
                .font(.pixelSystem(size: 11, weight: .bold))
                .foregroundColor(CodepetTheme.bodyText)
            if let link = companyStore.activeProjectLink {
                linkedRow(link)
            } else {
                unlinkedRow
            }
        }
    }

    private func linkedRow(_ link: ProjectLink) -> some View {
        CodepetCard {
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(Project.nameFromPath(link.path))
                        .font(.pixelSystem(size: 12, weight: .semibold))
                        .foregroundColor(CodepetTheme.primaryText)
                    Text(link.path)
                        .font(.pixelSystem(size: 10))
                        .foregroundColor(CodepetTheme.mutedText)
                        .lineLimit(1).truncationMode(.middle)
                    HStack(spacing: 6) {
                        badge(link.isGitRepo ? "⑂ git" : (lang == .vi ? "không phải git" : "no git"),
                              on: link.isGitRepo)
                        badge(link.hasClaudeMd ? "CLAUDE.md ✓" : "CLAUDE.md –", on: link.hasClaudeMd)
                    }
                }
                Spacer()
                Button {
                    _ = ProjectLinker.pickAndLink(into: companyStore, language: lang)
                } label: {
                    Text(lang == .vi ? "Đổi…" : "Change…")
                        .font(.pixelSystem(size: 10, weight: .semibold))
                        .foregroundColor(CodepetTheme.accentPurple)
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(Capsule().fill(CodepetTheme.accentPurple.opacity(0.14)))
                }.buttonStyle(.plain)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var unlinkedRow: some View {
        let suggestions = ProjectLinkSuggestions.suggest(
            from: projectStore.sortedProjects, excluding: companyStore.activeProjectLink?.path)
        return CodepetCard {
            VStack(alignment: .leading, spacing: 10) {
                Text(lang == .vi
                     ? "Liên kết một dự án và mình có thể sửa code thật trong đó — trên máy bạn, để bạn duyệt, trên gói Claude của bạn."
                     : "Link a project and I can make real code changes in it — on your machine, for your review, on your Claude subscription.")
                    .font(.pixelSystem(size: 11))
                    .foregroundColor(CodepetTheme.mutedText)
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    _ = ProjectLinker.pickAndLink(into: companyStore, language: lang)
                } label: {
                    Text(lang == .vi ? "Liên kết thư mục dự án" : "Link a project folder")
                        .font(.pixelSystem(size: 11, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(Capsule().fill(CodepetTheme.accentPurple))
                }.buttonStyle(.plain)
                if !suggestions.isEmpty {
                    Text(lang == .vi ? "Dự án gần đây" : "Recent projects")
                        .font(.pixelSystem(size: 10, weight: .bold))
                        .foregroundColor(CodepetTheme.mutedText)
                    FlowLayout(spacing: 6) {
                        ForEach(suggestions) { proj in
                            Button {
                                ProjectLinker.link(path: proj.id, into: companyStore, language: lang)
                            } label: {
                                Text(proj.displayName)
                                    .font(.pixelSystem(size: 10, weight: .semibold))
                                    .foregroundColor(CodepetTheme.accentPurple)
                                    .padding(.horizontal, 10).padding(.vertical, 4)
                                    .background(Capsule().fill(CodepetTheme.accentPurple.opacity(0.12)))
                                    .overlay(Capsule().stroke(CodepetTheme.accentPurple.opacity(0.4), lineWidth: 1))
                            }.buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func badge(_ text: String, on: Bool) -> some View {
        Text(text)
            .font(.pixelSystem(size: 9, weight: .bold))
            .foregroundColor(on ? CodepetTheme.accentTeal : CodepetTheme.mutedText)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(Capsule().fill((on ? CodepetTheme.accentTeal : CodepetTheme.mutedText).opacity(0.14)))
    }

    private func categorySection(_ cat: ToolCategory) -> some View {
        let items = Toolkit.items(in: cat)
        let onCount = items.filter { enabled.contains($0.id) }.count
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(cat.label(lang).uppercased())
                    .font(.pixelSystem(size: 11, weight: .bold))
                    .foregroundColor(CodepetTheme.bodyText)
                Spacer()
                Text("\(onCount)/\(items.count)")
                    .font(.pixelSystem(size: 11, weight: .medium))
                    .foregroundColor(CodepetTheme.mutedText)
            }
            ForEach(items) { item in
                ToolRowView(item: item, isOn: enabled.contains(item.id))
            }
        }
    }
}

/// The square category-tinted badge for a tool.
struct ToolBadge: View {
    let item: ToolItem
    var body: some View {
        Text(item.badge)
            .font(.pixelSystem(size: 11, weight: .bold))
            .foregroundColor(item.category.tint)
            .frame(width: 30, height: 30)
            .background(RoundedRectangle(cornerRadius: 8).fill(item.category.tint.opacity(0.14)))
    }
}

/// One toolkit row — badge + name + detail + an on/off toggle button.
struct ToolRowView: View {
    let item: ToolItem
    let isOn: Bool
    @EnvironmentObject var companyStore: CompanyStore
    @Environment(\.uiLanguage) private var lang

    var body: some View {
        CodepetCard {
            HStack(spacing: 10) {
                ToolBadge(item: item)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.name)
                        .font(.pixelSystem(size: 12, weight: .semibold))
                        .foregroundColor(CodepetTheme.primaryText)
                    Text(item.detail)
                        .font(.pixelSystem(size: 11))
                        .foregroundColor(CodepetTheme.mutedText)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Button { Task { await companyStore.toggleTool(id: item.id) } } label: {
                    Text(isOn ? item.category.onLabel(lang) : item.category.enableVerb(lang))
                        .font(.pixelSystem(size: 10, weight: .semibold))
                        .foregroundColor(isOn ? .white : item.category.tint)
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(Capsule().fill(isOn ? item.category.tint : item.category.tint.opacity(0.14)))
                }.buttonStyle(.plain)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

#if DEBUG
// Unlinked state (the common first-run). The linked row is verified live / in the
// composer + card previews — seeding a link here would write a real bookmark.
#Preview("Environment") {
    EnvironmentView()
        .environmentObject(CompanyStore())
        .environmentObject(ProjectStore())
        .frame(width: 560, height: 700)
}
#endif

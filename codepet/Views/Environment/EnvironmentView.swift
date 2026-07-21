// codepet/Views/Environment/EnvironmentView.swift
import SwiftUI

/// The Environment = the company's toolkit. A recommendations strip (recommended-but-off
/// items) over category sections of skills/connectors/agents with per-item toggles.
struct EnvironmentView: View {
    @EnvironmentObject var companyStore: CompanyStore
    @Environment(\.uiLanguage) private var lang

    private var enabled: Set<String> { companyStore.company.enabledTools }
    private var recs: [ToolItem] { Toolkit.recommended.filter { !enabled.contains($0.id) } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
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
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
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

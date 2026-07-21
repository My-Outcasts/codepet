// codepet/Views/Library/LibraryView.swift
import SwiftUI

/// The Library = delivered work. Lists company.library newest-first; each card opens
/// a markdown detail sheet. Empty → an honest empty state (nothing until 6B generates).
struct LibraryView: View {
    @EnvironmentObject var companyStore: CompanyStore
    @Environment(\.uiLanguage) private var lang
    @State private var selected: Deliverable?

    private var items: [Deliverable] {
        companyStore.company.library.sorted { ($0.createdAt ?? "") > ($1.createdAt ?? "") }
    }

    var body: some View {
        Group {
            if items.isEmpty {
                emptyState
            } else {
                ScrollView {
                    VStack(spacing: 10) {
                        ForEach(items) { d in
                            Button { selected = d } label: { DeliverableCardView(deliverable: d) }
                                .buttonStyle(.plain)
                        }
                    }
                    .padding(18)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sheet(item: $selected) { DeliverableDetailView(deliverable: $0) }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "tray")
                .font(.system(size: 30)).foregroundColor(CodepetTheme.mutedText)
            Text(lang == .vi ? "Sản phẩm sẽ xuất hiện ở đây" : "Delivered work will appear here")
                .font(.pixelSystem(size: 15, weight: .bold)).foregroundColor(CodepetTheme.primaryText)
            Text(lang == .vi ? "Khi Codepet tạo ra sản phẩm, chúng sẽ tập hợp ở đây."
                             : "Once Codepet produces work, it collects here.")
                .font(.pixelSystem(size: 12)).foregroundColor(CodepetTheme.mutedText)
                .multilineTextAlignment(.center)
        }
        .padding(24).frame(maxWidth: 360)
    }
}

/// One library row — kind icon + title + kind label.
struct DeliverableCardView: View {
    let deliverable: Deliverable
    @Environment(\.uiLanguage) private var lang
    var body: some View {
        CodepetCard {
            HStack(spacing: 10) {
                Image(systemName: deliverable.kind.icon)
                    .foregroundColor(CodepetTheme.accentPurple).frame(width: 22)
                VStack(alignment: .leading, spacing: 2) {
                    Text(deliverable.title)
                        .font(.pixelSystem(size: 13, weight: .semibold))
                        .foregroundColor(CodepetTheme.primaryText)
                    Text(deliverable.kind.label(lang))
                        .font(.pixelSystem(size: 10, weight: .medium))
                        .foregroundColor(CodepetTheme.mutedText)
                }
                Spacer()
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// Deliverable detail sheet — title + kind + the markdown body (scrolls).
struct DeliverableDetailView: View {
    let deliverable: Deliverable
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: deliverable.kind.icon).foregroundColor(CodepetTheme.accentPurple)
                Text(deliverable.title)
                    .font(.pixelSystem(size: 15, weight: .bold))
                    .foregroundColor(CodepetTheme.primaryText)
                Spacer()
                Button { dismiss() } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain).foregroundColor(CodepetTheme.mutedText)
            }
            .padding(16)
            Divider()
            ScrollView { MarkdownView(markdown: deliverable.body).padding(16) }
        }
        .frame(minWidth: 460, minHeight: 420)
        .background(CodepetTheme.pageBackground)
    }
}

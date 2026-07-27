// codepet/Views/Shell/AppRailView.swift
import SwiftUI

/// The left navigation rail — replaces the top bar's centred tab row. Six
/// destinations from `AppView.navTabs`, the active one tinted with the companion
/// accent, and the account menu pinned to the bottom.
struct AppRailView: View {
    let accent: Color

    @EnvironmentObject var companyStore: CompanyStore
    @Environment(\.uiLanguage) private var lang

    private static let width: CGFloat = 64

    var body: some View {
        VStack(spacing: 6) {
            Text("C").font(CodepetTheme.pixel(18)).foregroundColor(CodepetTheme.primaryText)
                .frame(height: 40)
            ForEach(AppView.navTabs) { item($0) }
            Spacer()
            AccountMenuView().padding(.bottom, 10)
        }
        .frame(width: Self.width)
        .padding(.top, 8)
        .background(CodepetTheme.surface)
        .overlay(alignment: .trailing) {
            Rectangle().fill(CodepetTheme.hairline).frame(width: 1)
        }
    }

    private func item(_ v: AppView) -> some View {
        let on = companyStore.view == v
        let count = badge(v)
        return Button {
            companyStore.selectedDeptKey = nil
            companyStore.select(v)
        } label: {
            Image(systemName: v.icon)
                .font(.system(size: 17, weight: .medium))
                .foregroundColor(on ? accent : CodepetTheme.mutedText)
                .frame(width: 40, height: 36)
                .background(RoundedRectangle(cornerRadius: 10).fill(on ? accent.opacity(0.14) : .clear))
                .overlay(alignment: .topTrailing) {
                    if count > 0 {
                        Text("\(count)")
                            .font(CodepetTheme.inter(9, weight: .semibold)).foregroundColor(.white)
                            .padding(.horizontal, 4).padding(.vertical, 1)
                            .background(Capsule().fill(CodepetTheme.accentGold))
                            .offset(x: 4, y: -2)
                    }
                }
        }
        .buttonStyle(.plain)
        .help(v.title(lang))
    }

    private func badge(_ v: AppView) -> Int {
        switch v {
        case .tasks:       return TopbarCounts.tasks(companyStore.company.tasks)
        case .library:     return TopbarCounts.library(companyStore.company.library)
        case .environment: return TopbarCounts.envPending(enabled: companyStore.company.enabledTools)
        default:           return 0
        }
    }
}

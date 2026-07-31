// codepet/Views/Shell/TopNavView.swift
import SwiftUI

/// The top navigation bar (web parity): account dropdown on the left, the five
/// destination tabs centered, wake pill + Upgrade on the right. Replaces the old
/// left rail and the old slim top bar.
struct TopNavView: View {
    let accent: Color

    @EnvironmentObject var companyStore: CompanyStore
    @Environment(\.uiLanguage) private var lang

    private var companionName: String { PetCharacter.all[companyStore.company.companionId]?.name ?? "Codepet" }

    var body: some View {
        HStack(spacing: 16) {
            Text("Codepet").font(CodepetTheme.pixel(18)).foregroundColor(CodepetTheme.primaryText)
            AccountMenuView()   // compact:false → avatar + name + chevron + dropdown (Settings/Billing/Support)
            Spacer(minLength: 12)
            HStack(spacing: 4) { ForEach(AppView.topTabs) { tab($0) } }
            Spacer(minLength: 12)
            wakePill
            upgradeButton
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(CodepetTheme.surface)
    }

    private func tab(_ v: AppView) -> some View {
        let on = companyStore.view == v
        let count = badge(v)
        return Button {
            companyStore.selectedDeptKey = nil
            companyStore.select(v)
        } label: {
            HStack(spacing: 5) {
                Text(v.navLabel(lang))
                    .font(CodepetTheme.inter(14, weight: on ? .semibold : .medium))
                    .foregroundColor(on ? accent : CodepetTheme.mutedText)
                if count > 0 {
                    Text("\(count)")
                        .font(CodepetTheme.inter(9, weight: .semibold)).foregroundColor(.white)
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(Capsule().fill(CodepetTheme.accentGold))
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            .overlay(alignment: .bottom) {
                Rectangle().fill(on ? accent : .clear).frame(height: 2).offset(y: 6)
            }
        }
        .buttonStyle(.plain)
    }

    private func badge(_ v: AppView) -> Int {
        switch v {
        case .tasks:       return TopbarCounts.tasks(companyStore.company.tasks)
        case .library:     return TopbarCounts.library(companyStore.company.library)
        case .environment: return TopbarCounts.envPending(enabled: companyStore.company.enabledTools)
        default:           return 0
        }
    }

    private var wakePill: some View {
        Button { companyStore.selectedDeptKey = nil; companyStore.select(.environment) } label: {
            HStack(spacing: 5) {
                Circle().fill(CodepetTheme.accentOrange).frame(width: 6, height: 6)
                Text("⚡ " + (lang == .vi ? "Đánh thức \(companionName)" : "Wake \(companionName) up"))
                    .font(CodepetTheme.inter(13.5, weight: .medium))
            }
            .foregroundColor(CodepetTheme.bodyText)
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(Capsule().fill(CodepetTheme.surface).overlay(Capsule().stroke(CodepetTheme.hairline)))
        }.buttonStyle(.plain)
    }

    private var upgradeButton: some View {
        Button { companyStore.selectedDeptKey = nil; companyStore.select(.billing) } label: {
            Text(lang == .vi ? "Nâng cấp" : "Upgrade")
                .font(CodepetTheme.inter(13.5, weight: .semibold)).foregroundColor(.white)
                .padding(.horizontal, 13).padding(.vertical, 7)
                .background(Capsule().fill(CodepetTheme.primaryText))
        }.buttonStyle(.plain)
    }
}

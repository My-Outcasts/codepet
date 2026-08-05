// codepet/Views/Shell/TopNavView.swift
import SwiftUI

/// The top navigation bar (web parity): account dropdown on the left, the five
/// destination tabs packed immediately after it, Upgrade pushed right.
/// Replaces the old left rail and the old slim top bar.
///
/// The tabs are deliberately NOT centred: the web packs them straight after the account
/// block (its "Overview" starts ~45px after the chevron), so a leading `Spacer` here left a
/// ~365pt gap that read as a different layout.
struct TopNavView: View {
    let accent: Color

    @EnvironmentObject var companyStore: CompanyStore
    @Environment(\.uiLanguage) private var lang

    var body: some View {
        HStack(spacing: 16) {
            Text("Codepet").font(CodepetTheme.pixel(18)).foregroundColor(CodepetTheme.primaryText)
            HStack(spacing: 4) { ForEach(AppView.topTabs) { tab($0) } }
            Spacer(minLength: 12)
            // The account control is the ONLY thing on the right (founder call, Aug 5).
            // It used to sit between the wordmark and the tabs — an identity control in
            // the middle of navigation — and the Upgrade pill sat out here. The pill is
            // gone: upgrading is an account-level act, so it lives in the account menu
            // and in the settings modal's Billing section, which is where the pill was
            // already pointing.
            AccountMenuView()
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
            // The label carried no fill, so the tab hit-tested on its glyphs alone —
            // the 10pt either side and 6pt above/below were dead on the app's most
            // used control. `hoverAffordance` supplies the interior and the pointer
            // response; the active underline still comes from the overlay above.
            .hoverAffordance(RoundedRectangle(cornerRadius: 7, style: .continuous), accent: accent)
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

}


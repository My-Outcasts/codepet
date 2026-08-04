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
            AccountMenuView()   // compact:false → avatar + name + chevron + dropdown (Settings, Appearance, Log out)
            HStack(spacing: 4) { ForEach(AppView.topTabs) { tab($0) } }
            Spacer(minLength: 12)
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

    private var upgradeButton: some View {
        // Opens the modal's Billing section over the current view — no longer a route,
        // so it doesn't have to clear `selectedDeptKey` or take the founder off Company.
        Button { companyStore.openSettings(.billing) } label: {
            UpgradePillLabel(title: lang == .vi ? "Nâng cấp" : "Upgrade")
        }.buttonStyle(.plain)
    }
}

/// The Upgrade CTA's visuals, split out from the button so the light/dark contrast
/// can be pixel-tested without standing up the whole nav bar (which needs Firebase).
///
/// This is an INVERTED "ink" pill: it fills with the primary TEXT color, so the pill
/// itself flips near-black (light) → near-cream (dark). A hardcoded white label
/// therefore vanished in dark mode. `onAccent` picks the ink from the fill's luminance
/// per drawing appearance — white-on-black in light, black-on-cream in dark.
struct UpgradePillLabel: View {
    let title: String

    var body: some View {
        Text(title)
            .font(CodepetTheme.inter(13.5, weight: .semibold))
            .foregroundColor(CodepetTheme.onAccent(CodepetTheme.primaryText))
            .padding(.horizontal, 13).padding(.vertical, 7)
            .background(Capsule().fill(CodepetTheme.primaryText))
    }
}

// codepet/Views/Settings/BillingPanel.swift
import SwiftUI

/// Plan and payment. Content lifted from the retired `BillingView` plan cards, re-cut
/// into the modal's row grammar.
///
/// There is deliberately no Upgrade action: `BillingView` never had one either — it drew
/// a static "Upgrade — coming soon" capsule, because there is no billing backend and no
/// upgrade destination in the app. Inventing a button here would be inventing a route,
/// so the same honest label ships instead. Wire it up when Stripe lands.
struct BillingPanel: View {
    @Environment(\.uiLanguage) private var lang

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            SettingsGroupLabel(lang == .vi ? "Gói" : "Plan")
            SettingsGroup {
                planRow(.trial, current: true)
                SettingsDivider()
                planRow(.pro, current: false)
            }
            Text(lang == .vi ? "Chưa có thanh toán trong ứng dụng — gói được quản lý bên ngoài."
                             : "There is no in-app checkout yet — plans are managed outside the app.")
                .font(CodepetTheme.inter(11))
                .foregroundColor(CodepetTheme.mutedText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// One plan as a settings row: name + the price/credits lines, with the trailing
    /// control saying either "you're on this" or "not yet buyable".
    @ViewBuilder private func planRow(_ plan: Plan, current: Bool) -> some View {
        SettingsRow(
            label: plan.title(lang),
            description: "\(plan.priceLine(lang)) · \(plan.creditsLine(lang))"
        ) {
            if current {
                Text(lang == .vi ? "Hiện tại" : "Current")
                    .font(CodepetTheme.inter(10, weight: .semibold))
                    .foregroundColor(CodepetTheme.accentPurple)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Capsule().fill(CodepetTheme.accentPurple.opacity(0.14)))
            } else {
                Text(lang == .vi ? "Nâng cấp — sắp có" : "Upgrade — coming soon")
                    .font(CodepetTheme.inter(11, weight: .semibold))
                    .foregroundColor(CodepetTheme.mutedText)
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(Capsule().stroke(CodepetTheme.hairline))
            }
        }
    }
}

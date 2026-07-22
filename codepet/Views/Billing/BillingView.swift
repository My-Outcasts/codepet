// codepet/Views/Billing/BillingView.swift
import SwiftUI

/// Billing & Usage (web BillingView.tsx), native-appropriate: a static usage/plan
/// display (no live metering / BYOK yet). The plan cards moved here from Settings.
struct BillingView: View {
    @Environment(\.uiLanguage) private var lang

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(lang == .vi ? "Thanh toán & sử dụng" : "Billing & Usage")
                    .font(CodepetTheme.title()).foregroundColor(CodepetTheme.primaryText)

                // Usage card (static — no live metering natively yet)
                CodepetCard(fill: CodepetTheme.surface) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(lang == .vi ? "Tín dụng tháng này" : "Credits this month")
                            .font(CodepetTheme.inter(12, weight: .semibold)).foregroundColor(CodepetTheme.mutedText)
                        Text("—")
                            .font(CodepetTheme.inter(30, weight: .bold)).foregroundColor(CodepetTheme.primaryText)
                        Text(lang == .vi ? "Làm mới hằng tháng" : "Renews monthly")
                            .font(CodepetTheme.inter(11)).foregroundColor(CodepetTheme.mutedText)
                    }
                }

                Text(lang == .vi ? "Gói" : "Plan")
                    .font(CodepetTheme.inter(13, weight: .semibold)).foregroundColor(CodepetTheme.mutedText)
                planCard(.trial, current: true)
                planCard(.pro, current: false)
            }
            .padding(20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func planCard(_ plan: Plan, current: Bool) -> some View {
        CodepetCard(fill: current ? CodepetTheme.accentPurple.opacity(0.08) : CodepetTheme.surface) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(plan.title(lang))
                            .font(CodepetTheme.inter(14, weight: .bold)).foregroundColor(CodepetTheme.primaryText)
                        if current {
                            Text(lang == .vi ? "Hiện tại" : "Current")
                                .font(CodepetTheme.inter(10, weight: .semibold)).foregroundColor(CodepetTheme.accentPurple)
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Capsule().fill(CodepetTheme.accentPurple.opacity(0.14)))
                        }
                    }
                    Text(plan.priceLine(lang))
                        .font(CodepetTheme.inter(12, weight: .semibold)).foregroundColor(CodepetTheme.bodyText)
                    Text(plan.creditsLine(lang))
                        .font(CodepetTheme.inter(11)).foregroundColor(CodepetTheme.mutedText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                if !current {
                    Text(lang == .vi ? "Nâng cấp — sắp có" : "Upgrade — coming soon")
                        .font(CodepetTheme.inter(11, weight: .semibold)).foregroundColor(CodepetTheme.mutedText)
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(Capsule().stroke(CodepetTheme.hairline))
                }
            }
        }
    }
}

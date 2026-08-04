// codepet/Views/Settings/UsagePanel.swift
import SwiftUI

/// What the account has spent today.
///
/// NO METER, on purpose. The spec asked for a ChatGPT-style progress bar, but nothing in
/// the app counts runs: the per-account cap is enforced server-side and only ever becomes
/// visible as a 429 (`ReflectionAPIClient` / `VirtualCompanyClient` decode `limit` and
/// `reset_at` from that error body, and neither is persisted). A bar needs a numerator,
/// and the only numerator available would be a number this view made up — which reads as
/// authoritative and is worse than an empty state. So this panel states the cap and the
/// reset rule, and shows `—` where the count belongs until a real counter exists.
struct UsagePanel: View {
    @Environment(\.uiLanguage) private var lang

    /// Display only, and NOT a measurement: this mirrors the server-side daily request
    /// cap. Keep it in sync with the functions-side limit by hand — if it drifts, the
    /// honest fix is to have the server report the cap, not to re-guess it here.
    private let dailyCap = 30

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            SettingsGroup {
                SettingsRow(
                    label: lang == .vi ? "Lượt hôm nay" : "Runs today",
                    description: lang == .vi
                        ? "Giới hạn áp dụng phía máy chủ; ứng dụng chưa đếm số lượt tại máy, nên chưa có thanh đo ở đây."
                        : "The limit is enforced on the server; the app doesn't count runs locally yet, so there's no meter here."
                ) {
                    // The denominator is the cap; the numerator is honestly unknown.
                    Text("— / \(dailyCap)")
                        .font(CodepetTheme.inter(13, weight: .medium))
                        .foregroundColor(CodepetTheme.mutedText)
                }
                SettingsDivider()
                SettingsRow(
                    label: lang == .vi ? "Tín dụng tháng này" : "Credits this month",
                    description: lang == .vi ? "Làm mới hằng tháng." : "Renews monthly."
                ) {
                    Text("—")
                        .font(CodepetTheme.inter(13, weight: .medium))
                        .foregroundColor(CodepetTheme.mutedText)
                }
            }
            Text(lang == .vi ? "Giới hạn đặt lại vào nửa đêm."
                             : "The limit resets at midnight.")
                .font(CodepetTheme.inter(11))
                .foregroundColor(CodepetTheme.mutedText)
        }
    }
}

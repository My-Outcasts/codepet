// codepet/Views/Settings/UsagePanel.swift
import SwiftUI

/// What the account has spent this month.
///
/// NO METER, on purpose. The spec asked for a ChatGPT-style progress bar, but nothing in
/// the app counts runs locally, and the account is priced in credits, not a per-day cap
/// (see `MockChat.swift`) — so a client-side cap number and a "resets at midnight" line
/// would both be inventions, not measurements. This panel says plainly that usage isn't
/// tracked on this device yet, and keeps the one row it can show honestly: the credits
/// balance, lifted from the retired `BillingView`.
struct UsagePanel: View {
    @Environment(\.uiLanguage) private var lang

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            SettingsGroup {
                SettingsRow(
                    label: lang == .vi ? "Tín dụng tháng này" : "Credits this month",
                    description: lang == .vi ? "Làm mới hằng tháng." : "Renews monthly."
                ) {
                    Text("—")
                        .font(CodepetTheme.inter(13, weight: .medium))
                        .foregroundColor(CodepetTheme.mutedText)
                }
            }
            Text(lang == .vi ? "Mức sử dụng chưa được theo dõi trên máy này."
                             : "Usage isn't tracked on this device yet.")
                .font(CodepetTheme.inter(11))
                .foregroundColor(CodepetTheme.mutedText)
        }
    }
}

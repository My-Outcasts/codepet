// codepet/Views/Settings/UsagePanel.swift
import SwiftUI

/// What the account has spent this month, and today's department meetings.
///
/// NO METER, on purpose. The spec asked for a ChatGPT-style progress bar, but nothing in
/// the app counts runs locally, and the account is priced in credits, not a per-day cap
/// (see `MockChat.swift`) — so a client-side cap number and a "resets at midnight" line
/// would both be inventions, not measurements. This panel says plainly that usage isn't
/// tracked on this device yet, and keeps the one row it can show honestly: the credits
/// balance, lifted from the retired `BillingView`.
///
/// The one thing this device DOES count is department meetings (CP-028): each room's estimated
/// cost left the chat and is added up per local day in `UsageLedger`. It is shown as an estimate
/// of plan usage, because on the founder's own Claude plan that is all it is.
struct UsagePanel: View {
    @Environment(\.uiLanguage) private var lang
    var ledger: UsageLedgering = CompanyStore.defaultUsageLedger

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
            SettingsGroup {
                SettingsRow(label: UsageCopy.todayLabel(lang), description: UsageCopy.todayDetail(lang)) {
                    Text(UsageCopy.todayValue(ledger.day(Date()), lang: lang))
                        .font(CodepetTheme.inter(13, weight: .medium))
                        .monospacedDigit()
                        .foregroundColor(CodepetTheme.primaryText)
                }
            }
            Text(lang == .vi ? "Chỉ tính các cuộc họp phòng ban trên máy này. Chat và công việc chưa được theo dõi."
                             : "Counts department meetings on this Mac only. Chat and tasks aren't tracked yet.")
                .font(CodepetTheme.inter(11))
                .foregroundColor(CodepetTheme.mutedText)
        }
    }
}

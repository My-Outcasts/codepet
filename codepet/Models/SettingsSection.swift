// codepet/Models/SettingsSection.swift
import Foundation

/// The account-level surfaces. Formerly the `.settings`, `.billing` and `.support`
/// `AppView` destinations; now sections of one centered modal.
///
/// Settings is an overlay, not a destination: `CompanyStore.settingsSection` is `nil`
/// when closed, so closing it returns the founder to the view they were already on —
/// there is no route to restore. The `String` raw values give chat cards a deep link.
enum SettingsSection: String, CaseIterable, Identifiable {
    case preferences, aiSettings, claudeCode, company, memory,
         notifications, billing, usage, support, advanced

    var id: String { rawValue }

    func title(_ lang: AppLanguage) -> String {
        switch self {
        case .preferences:   return lang == .vi ? "Tuỳ chọn" : "Preferences"
        case .aiSettings:    return lang == .vi ? "Cài đặt AI" : "AI Settings"
        case .claudeCode:    return "Claude Code"
        case .company:       return lang == .vi ? "Công ty" : "Company"
        case .memory:        return lang == .vi ? "Ghi nhớ" : "Memory"
        case .notifications: return lang == .vi ? "Thông báo" : "Notifications"
        case .billing:       return lang == .vi ? "Thanh toán" : "Billing"
        case .usage:         return lang == .vi ? "Mức dùng" : "Usage"
        case .support:       return lang == .vi ? "Hỗ trợ" : "Support"
        case .advanced:      return lang == .vi ? "Nâng cao" : "Advanced"
        }
    }

    /// The muted line under the panel title.
    func subtitle(_ lang: AppLanguage) -> String {
        switch self {
        case .preferences:
            return lang == .vi ? "Hồ sơ, giao diện và tuỳ chọn tài khoản."
                               : "Manage your profile, appearance, and account preferences."
        case .aiSettings:
            return lang == .vi ? "Cách đội của bạn nói chuyện với bạn."
                               : "How your team talks to you."
        // Says "your own plan", not "your API key" — the entire point of connecting here
        // is that Codepet spends the founder's Claude subscription and never holds a
        // credential of its own. A subtitle mentioning keys would describe the design we
        // rejected.
        case .claudeCode:
            return lang == .vi ? "Nối gói Claude của bạn, để Codepet chạy trên đó."
                               : "Connect your own Claude plan, and Codepet runs on it."
        case .company:
            return lang == .vi ? "Bạn đồng hành và hồ sơ công ty."
                               : "Your companion and your company brief."
        case .memory:
            return lang == .vi ? "Những gì đội của bạn ghi nhớ về công ty."
                               : "What your team remembers about your company."
        case .notifications:
            return lang == .vi ? "Chọn khi nào Codepet nhắc bạn."
                               : "Choose when Codepet interrupts you."
        // Both of these say only what their panel actually shows. `BillingPanel` has no
        // checkout — there is no billing backend to point one at — so it must not be
        // introduced as "your payment method"; and `UsagePanel` deliberately carries no
        // per-day framing, because the account is priced in credits, not a daily cap, and
        // nothing on this device counts runs. A subtitle promising either would reinstate,
        // one file over, exactly the claim the panel was written to avoid.
        case .billing:
            return lang == .vi ? "Gói của bạn. Chưa thanh toán được trong ứng dụng."
                               : "Your plan. There's no checkout in the app yet."
        case .usage:
            return lang == .vi ? "Tín dụng của bạn, và những gì máy này biết."
                               : "Your credits, and what this device can tell you."
        case .support:
            return lang == .vi ? "Nhận trợ giúp về Codepet." : "Get help with Codepet."
        case .advanced:
            return lang == .vi ? "Đăng xuất và thông tin phiên bản."
                               : "Sign out and app version."
        }
    }

    var icon: String {
        switch self {
        case .preferences:   return "slider.horizontal.3"
        case .aiSettings:    return "sparkles"
        case .claudeCode:    return "terminal"
        case .company:       return "building.2"
        case .memory:        return "brain"
        case .notifications: return "bell"
        case .billing:       return "creditcard"
        case .usage:         return "chart.bar"
        case .support:       return "questionmark.circle"
        case .advanced:      return "gearshape"
        }
    }
}

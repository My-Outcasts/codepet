// codepet/Models/SettingsSection.swift
import Foundation

/// The account-level surfaces. Formerly the `.settings`, `.billing` and `.support`
/// `AppView` destinations; now sections of one centered modal.
///
/// Settings is an overlay, not a destination: `CompanyStore.settingsSection` is `nil`
/// when closed, so closing it returns the founder to the view they were already on —
/// there is no route to restore. The `String` raw values give chat cards a deep link.
enum SettingsSection: String, CaseIterable, Identifiable {
    case preferences, aiSettings, company, memory,
         notifications, billing, usage, support, advanced

    var id: String { rawValue }

    func title(_ lang: AppLanguage) -> String {
        switch self {
        case .preferences:   return lang == .vi ? "Tuỳ chọn" : "Preferences"
        case .aiSettings:    return lang == .vi ? "Cài đặt AI" : "AI Settings"
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
        case .company:
            return lang == .vi ? "Bạn đồng hành và hồ sơ công ty."
                               : "Your companion and your company brief."
        case .memory:
            return lang == .vi ? "Những gì đội của bạn ghi nhớ về công ty."
                               : "What your team remembers about your company."
        case .notifications:
            return lang == .vi ? "Chọn khi nào Codepet nhắc bạn."
                               : "Choose when Codepet interrupts you."
        case .billing:
            return lang == .vi ? "Gói và phương thức thanh toán."
                               : "Your plan and payment method."
        case .usage:
            return lang == .vi ? "Mức dùng hôm nay." : "What you've used today."
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

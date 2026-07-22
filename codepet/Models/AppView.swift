import Foundation

/// The web app's top-level views (components/AppRoot.tsx), minus Giang's Build
/// Coach (summary/build/install). Drives the app shell's sidebar + content.
enum AppView: String, CaseIterable, Identifiable {
    case overview, company, roadmap, tasks, library, environment, settings, billing, support

    var id: String { rawValue }

    /// The 5 primary destinations shown as top-bar tabs (web Topbar). Settings /
    /// Billing / Support are reached via the account menu; Roadmap is folded into Overview.
    static let navTabs: [AppView] = [.overview, .company, .tasks, .library, .environment]

    func title(_ lang: AppLanguage) -> String {
        switch self {
        case .overview:    return lang == .vi ? "Tổng quan" : "Overview"
        case .company:     return lang == .vi ? "Công ty" : "Company"
        case .roadmap:     return lang == .vi ? "Lộ trình" : "Roadmap"
        case .tasks:       return lang == .vi ? "Nhiệm vụ" : "Tasks"
        case .library:     return lang == .vi ? "Thư viện" : "Library"
        case .environment: return lang == .vi ? "Môi trường" : "Environment"
        case .settings:    return lang == .vi ? "Cài đặt" : "Settings"
        case .billing:     return lang == .vi ? "Thanh toán" : "Billing & Usage"
        case .support:     return lang == .vi ? "Hỗ trợ" : "Support"
        }
    }

    /// SF Symbol shown in the sidebar.
    var icon: String {
        switch self {
        case .overview:    return "square.grid.2x2"
        case .company:     return "building.2"
        case .roadmap:     return "map"
        case .tasks:       return "checklist"
        case .library:     return "books.vertical"
        case .environment: return "wrench.and.screwdriver"
        case .settings:    return "gearshape"
        case .billing:     return "creditcard"
        case .support:     return "questionmark.circle"
        }
    }
}

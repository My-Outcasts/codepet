import Foundation

/// The web app's top-level views (components/AppRoot.tsx), minus Giang's Build
/// Coach (summary/build/install). Drives the app shell's sidebar + content.
enum AppView: String, CaseIterable, Identifiable {
    case overview, summary, team, company, roadmap, tasks, library, environment, settings, billing, support

    var id: String { rawValue }

    /// The primary destinations shown as top-bar tabs (web Topbar). Settings /
    /// Billing / Support are reached via the account menu; Roadmap is folded into Overview.
    /// `team` is the multi-agent demo (client-side simulated).
    static let navTabs: [AppView] = [.summary, .overview, .team, .company, .tasks, .library, .environment]

    func title(_ lang: AppLanguage) -> String {
        switch self {
        case .summary:     return lang == .vi ? "Tóm tắt" : "Summary"
        case .overview:    return lang == .vi ? "Tổng quan" : "Overview"
        case .team:        return lang == .vi ? "Đội ngũ" : "Team"
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

    /// Resolve a chat `nav` action's `destination` string to an `AppView` —
    /// mirrors the web's own destination→route map. `department` (a specific
    /// dept's detail view, not a top-level tab) resolves to `.company`; the
    /// caller (CompanyStore.activateNav) additionally sets `selectedDeptKey`
    /// from `target` so `.company` opens on that department, not the roster.
    /// Unknown destinations return nil so an unresolvable chip is a no-op.
    static func from(navDestination raw: String) -> AppView? {
        switch raw {
        case "roadmap":     return .overview
        case "tasks":       return .tasks
        case "library":     return .library
        case "company":     return .company
        case "environment": return .environment
        case "department":  return .company
        default:            return nil
        }
    }

    /// SF Symbol shown in the sidebar.
    var icon: String {
        switch self {
        case .summary:     return "sparkles"
        case .overview:    return "square.grid.2x2"
        case .team:        return "person.3"
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

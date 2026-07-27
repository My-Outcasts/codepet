import Foundation

/// The web app's top-level views (components/AppRoot.tsx), minus Giang's Build
/// Coach (summary/build/install). Drives the app shell's sidebar + content.
enum AppView: String, CaseIterable, Identifiable {
    case chat, summary, company, roadmap, secondBrain, tasks, library, environment, settings, billing, support

    var id: String { rawValue }

    /// The primary destinations shown as top-bar tabs (web Topbar). Settings /
    /// Billing / Support are reached via the account menu; chat is the full-width
    /// home (reached via the wordmark), not a tab.
    static let navTabs: [AppView] = [.summary, .roadmap, .secondBrain, .company, .tasks, .library, .environment]

    func title(_ lang: AppLanguage) -> String {
        switch self {
        case .chat:        return lang == .vi ? "Trò chuyện" : "Chat"
        case .summary:     return lang == .vi ? "Tóm tắt" : "Summary"
        case .company:     return lang == .vi ? "Công ty" : "Company"
        case .roadmap:     return lang == .vi ? "Lộ trình" : "Roadmap"
        case .secondBrain: return lang == .vi ? "Bộ não thứ hai" : "Second Brain"
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
        case "roadmap":     return .roadmap
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
        case .chat:        return "message"
        case .summary:     return "sparkles"
        case .company:     return "building.2"
        case .roadmap:     return "map"
        case .secondBrain: return "brain"
        case .tasks:       return "checklist"
        case .library:     return "books.vertical"
        case .environment: return "wrench.and.screwdriver"
        case .settings:    return "gearshape"
        case .billing:     return "creditcard"
        case .support:     return "questionmark.circle"
        }
    }
}

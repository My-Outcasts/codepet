import Foundation

/// The app's top-level destinations. Chat is the primary surface; Roadmap and
/// Second Brain are the two halves of the retired Overview page.
enum AppView: String, CaseIterable, Identifiable {
    case chat, roadmap, secondBrain, tasks, library, environment, company, settings, billing, support

    var id: String { rawValue }

    /// Destinations shown in the left rail, in order. `company` is reached from a
    /// Second Brain department row; settings / billing / support from the account menu.
    static let navTabs: [AppView] = [.chat, .roadmap, .secondBrain, .tasks, .library, .environment]

    func title(_ lang: AppLanguage) -> String {
        switch self {
        case .chat:        return lang == .vi ? "Trò chuyện" : "Chat"
        case .roadmap:     return lang == .vi ? "Lộ trình" : "Roadmap"
        case .secondBrain: return lang == .vi ? "Bộ não" : "Second Brain"
        case .tasks:       return lang == .vi ? "Nhiệm vụ" : "Tasks"
        case .library:     return lang == .vi ? "Thư viện" : "Library"
        case .environment: return lang == .vi ? "Môi trường" : "Environment"
        case .company:     return lang == .vi ? "Công ty" : "Company"
        case .settings:    return lang == .vi ? "Cài đặt" : "Settings"
        case .billing:     return lang == .vi ? "Thanh toán" : "Billing & Usage"
        case .support:     return lang == .vi ? "Hỗ trợ" : "Support"
        }
    }

    /// Resolve a chat `nav` action's `destination` string. `department` resolves to
    /// `.company`; the caller additionally sets `selectedDeptKey` from `target` so
    /// `.company` opens on that department. Unknown destinations return nil so an
    /// unresolvable chip is a no-op.
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

    /// SF Symbol shown in the rail.
    var icon: String {
        switch self {
        case .chat:        return "bubble.left"
        case .roadmap:     return "map"
        case .secondBrain: return "brain"
        case .tasks:       return "checklist"
        case .library:     return "books.vertical"
        case .environment: return "wrench.and.screwdriver"
        case .company:     return "building.2"
        case .settings:    return "gearshape"
        case .billing:     return "creditcard"
        case .support:     return "questionmark.circle"
        }
    }
}

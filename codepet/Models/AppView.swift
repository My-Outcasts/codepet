import Foundation

/// The web app's top-level views (components/AppRoot.tsx), minus Giang's Build
/// Coach (summary/build/install). Drives the app shell's sidebar + content.
enum AppView: String, CaseIterable, Identifiable {
    case overview, company, roadmap, tasks, library, environment, settings

    var id: String { rawValue }

    func title(_ lang: AppLanguage) -> String {
        switch self {
        case .overview:    return lang == .vi ? "Tổng quan" : "Overview"
        case .company:     return lang == .vi ? "Công ty" : "Company"
        case .roadmap:     return lang == .vi ? "Lộ trình" : "Roadmap"
        case .tasks:       return lang == .vi ? "Nhiệm vụ" : "Tasks"
        case .library:     return lang == .vi ? "Thư viện" : "Library"
        case .environment: return lang == .vi ? "Môi trường" : "Environment"
        case .settings:    return lang == .vi ? "Cài đặt" : "Settings"
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
        }
    }
}

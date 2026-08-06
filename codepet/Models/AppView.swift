import Foundation

/// The app's top-level destinations. Chat is the primary surface; Roadmap and
/// Second Brain are the two halves of the retired Overview page.
enum AppView: String, CaseIterable, Identifiable {
    case chat, roadmap, secondBrain, tasks, library, environment, company

    var id: String { rawValue }

    /// Destinations shown as top-nav tabs, in order (web parity). Chat is the docked
    /// copilot (no tab); Second Brain is a toggle on the Overview. Settings, Billing,
    /// Usage and Support are NOT destinations at all — they are sections of the centered
    /// settings modal (`SettingsSection`), opened as an overlay over whatever view the
    /// founder is already on.
    /// Overview is NOT here. It is the default destination, so a tab that is selected the moment
    /// the app opens spent a permanent slot restating where you already are. The wordmark carries
    /// it now — clicking Codepet goes home, the way a site's logo does (founder call, Aug 6) —
    /// which is also why `navLabel(.roadmap)` still says "Overview": the tooltip on that wordmark
    /// is the label's remaining reader.
    static let topTabs: [AppView] = [.company, .tasks, .library, .environment]

    /// Where the wordmark goes, and the destination the app opens on.
    static let home: AppView = .roadmap

    /// How the wordmark's shortcut is written in its tooltip chip. The binding itself lives in
    /// `TopNavView` — this stays a Foundation-only model, so the SwiftUI key types don't belong
    /// here.
    ///
    /// ⇧⌘H, not ⌘1: Safari's Home uses ⇧⌘H, and ⌘1-⌘7 are already bound in `CodePetApp`'s
    /// Navigation menu — to the OLD game layer's tabs (home/skills/sessions/…), which still
    /// register even though the company layer is the product. Reusing ⌘1 would have collided
    /// with a live binding.
    static let homeShortcutLabel = "⇧⌘H"

    /// Nav label — the Roadmap destination is titled "Overview" in the top nav (web parity).
    func navLabel(_ lang: AppLanguage) -> String {
        self == .roadmap ? (lang == .vi ? "Tổng quan" : "Overview") : title(lang)
    }

    func title(_ lang: AppLanguage) -> String {
        switch self {
        case .chat:        return lang == .vi ? "Trò chuyện" : "Chat"
        case .roadmap:     return lang == .vi ? "Lộ trình" : "Roadmap"
        case .secondBrain: return lang == .vi ? "Bộ não" : "Second Brain"
        case .tasks:       return lang == .vi ? "Nhiệm vụ" : "Tasks"
        case .library:     return lang == .vi ? "Thư viện" : "Library"
        case .environment: return lang == .vi ? "Môi trường" : "Environment"
        case .company:     return lang == .vi ? "Công ty" : "Company"
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

    /// SF Symbol shown for the destination (account menu, top nav).
    var icon: String {
        switch self {
        case .chat:        return "bubble.left"
        case .roadmap:     return "map"
        case .secondBrain: return "brain"
        case .tasks:       return "checklist"
        case .library:     return "books.vertical"
        case .environment: return "wrench.and.screwdriver"
        case .company:     return "building.2"
        }
    }
}

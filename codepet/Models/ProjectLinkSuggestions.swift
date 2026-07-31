import Foundation

/// Which auto-detected project roots to offer as one-tap "link this" chips in the
/// Environment link surface: `ProjectStore.sortedProjects` order (most-recent
/// first), minus the already-active link, capped. Pure.
enum ProjectLinkSuggestions {
    static func suggest(from detected: [Project], excluding activePath: String?, max: Int = 4) -> [Project] {
        Array(detected.filter { $0.id != activePath }.prefix(max))
    }
}

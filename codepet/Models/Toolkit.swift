// codepet/Models/Toolkit.swift
import SwiftUI

/// A toolkit category — skills / connectors / agents. Chrome (labels/verbs) is VI/EN;
/// item content (name/detail/why) is EN, ported from the web catalog.
enum ToolCategory: String, CaseIterable, Identifiable {
    case skills, connectors, agents
    var id: String { rawValue }

    func label(_ lang: AppLanguage) -> String {
        switch self {
        case .skills:     return lang == .vi ? "Kỹ năng" : "Skills"
        case .connectors: return lang == .vi ? "Kết nối" : "Connectors"
        case .agents:     return lang == .vi ? "Trợ lý" : "Agents"
        }
    }
    func enableVerb(_ lang: AppLanguage) -> String {
        switch self {
        case .skills:     return lang == .vi ? "Bật" : "Turn on"
        case .connectors: return lang == .vi ? "Kết nối" : "Connect"
        case .agents:     return lang == .vi ? "Bật" : "Enable"
        }
    }
    func onLabel(_ lang: AppLanguage) -> String {
        switch self {
        case .skills:     return lang == .vi ? "Đang bật" : "Active"
        case .connectors: return lang == .vi ? "Đã kết nối" : "Connected"
        case .agents:     return lang == .vi ? "Đã bật" : "Enabled"
        }
    }
    var tint: Color {
        switch self {
        case .skills:     return CodepetTheme.accentPurple
        case .connectors: return CodepetTheme.accentBlue
        case .agents:     return CodepetTheme.accentTeal
        }
    }
}

/// One toolkit item. `defaultOn` seeds the first-run enabled set; `recommended`/`why`
/// drive the recommendations strip.
struct ToolItem: Identifiable, Equatable {
    let id: String
    let name: String
    let badge: String
    let detail: String
    let category: ToolCategory
    let recommended: Bool
    let why: String?
    let defaultOn: Bool
}

/// The static toolkit catalog — the 13 web `ENV` items, companion-name-genericized.
enum Toolkit {
    static let catalog: [ToolItem] = [
        // skills
        ToolItem(id: "web-research", name: "Web research", badge: "Wr",
                 detail: "Searches the web and cites sources in drafts.",
                 category: .skills, recommended: false, why: nil, defaultOn: false),
        ToolItem(id: "prd-writer", name: "PRD writer", badge: "Pr",
                 detail: "Turn a rough idea into a structured product spec.",
                 category: .skills, recommended: true,
                 why: "Turn each feature into a clear spec before building it.", defaultOn: true),
        ToolItem(id: "code-review", name: "Code review", badge: "Cr",
                 detail: "Reviews diffs for bugs before anything ships.",
                 category: .skills, recommended: true,
                 why: "Catch bugs before they reach your testers.", defaultOn: false),
        ToolItem(id: "changelog", name: "Changelog", badge: "Ch",
                 detail: "Auto-drafts release notes from your commits.",
                 category: .skills, recommended: false, why: nil, defaultOn: false),
        // connectors
        ToolItem(id: "github", name: "GitHub", badge: "Gh",
                 detail: "Read repos, open PRs, track issues.",
                 category: .connectors, recommended: true,
                 why: "Reads your repo and opens PRs as it ships work.", defaultOn: true),
        ToolItem(id: "notion", name: "Notion", badge: "No",
                 detail: "Sync briefs, roadmaps, and docs.",
                 category: .connectors, recommended: true,
                 why: "Connect it so your companion can write there.", defaultOn: false),
        ToolItem(id: "figma", name: "Figma", badge: "Fi",
                 detail: "Pull designs and components into context.",
                 category: .connectors, recommended: false, why: nil, defaultOn: false),
        ToolItem(id: "slack", name: "Slack", badge: "Sl",
                 detail: "Post updates and gather feedback.",
                 category: .connectors, recommended: false, why: nil, defaultOn: false),
        ToolItem(id: "linear", name: "Linear", badge: "Li",
                 detail: "Create and update issues from your tasks.",
                 category: .connectors, recommended: false, why: nil, defaultOn: false),
        // agents
        ToolItem(id: "code-reviewer", name: "Code Reviewer", badge: "Cr",
                 detail: "A subagent that audits changes for correctness.",
                 category: .agents, recommended: false, why: nil, defaultOn: false),
        ToolItem(id: "explorer", name: "Explorer", badge: "Ex",
                 detail: "Searches the codebase to answer questions fast.",
                 category: .agents, recommended: false, why: nil, defaultOn: true),
        ToolItem(id: "test-writer", name: "Test Writer", badge: "Tw",
                 detail: "Generates tests for new code.",
                 category: .agents, recommended: true,
                 why: "Writes tests as each new feature ships.", defaultOn: false),
        ToolItem(id: "migrator", name: "Migrator", badge: "Mg",
                 detail: "Runs large, repetitive refactors safely.",
                 category: .agents, recommended: false, why: nil, defaultOn: false),
    ]

    static func items(in category: ToolCategory) -> [ToolItem] {
        catalog.filter { $0.category == category }
    }

    /// The skill ids the founder has turned on, for the chat request's
    /// `enabled_skills`. Sorted so the payload — and therefore the request the
    /// CF caches against — is stable for an unchanged toolkit; a `Set`'s order
    /// is not, and an order that churns per turn would look like a new prefix.
    ///
    /// Deliberately NOT filtered to "skills we've built": the CF is the
    /// authority on that (see `IMPLEMENTED_SKILLS`), so shipping a skill is a
    /// backend deploy, not a client release.
    /// The one skill id a view names directly — the `🌐` row in `plusMenu` flips it,
    /// and it is the REAL gate on web search: `companyChat.ts` adds `WEB_SEARCH_TOOL`
    /// only when this id arrives in `enabled_skills`. Named here so the string is not
    /// typed into a view, where a typo would silently toggle nothing.
    static let webResearchId = "web-research"

    static func enabledSkillIds(in enabled: Set<String>) -> [String] {
        items(in: .skills).map(\.id).filter(enabled.contains).sorted()
    }
    static var recommended: [ToolItem] { catalog.filter(\.recommended) }

    /// The skills this binary is compiled knowing about, used ONLY until the live
    /// manifest arrives: first paint, offline, or a failed fetch.
    ///
    /// A floor, not a copy to keep in sync. `IMPLEMENTED_SKILLS` in the CF stays the
    /// authority, so a skill shipped backend-only becomes built via the manifest
    /// without this list changing.
    static let bundledBuiltSkills: Set<String> = ["web-research", "prd-writer"]

    static var defaultEnabledIds: Set<String> { Set(catalog.filter(\.defaultOn).map(\.id)) }

    /// Resolve a chat `setup`/`env_setup` {category,name} pair to its catalog item —
    /// case-insensitive, category+name first, falling back to name alone (category
    /// strings on the wire aren't guaranteed to match `ToolCategory.rawValue` exactly).
    static func find(category: String, name: String) -> ToolItem? {
        let cat = category.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let nm = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !nm.isEmpty else { return nil }
        return catalog.first { $0.category.rawValue == cat && $0.name.lowercased() == nm }
            ?? catalog.first { $0.name.lowercased() == nm }
    }
}

extension ToolItem {

    /// Whether this item does anything at all today.
    ///
    /// Three categories, three honest authorities, one accessor — so no view and no
    /// payload has to know where the truth came from:
    ///
    ///  - **skills**: the CF owns it (`IMPLEMENTED_SKILLS`), delivered as `builtSkills`.
    ///    `parseEnabledSkills` drops any id it has not implemented, so a skill absent
    ///    from the manifest genuinely cannot affect a turn.
    ///  - **connectors**: `ConnectorProvider` IS the OAuth implementation, so the enum
    ///    having a case is the same fact as the consent flow existing. Adding
    ///    `case notion` builds that row and nothing else needs to change.
    ///  - **agents**: nothing can run one. This is the single line that changes when
    ///    subagents land — see the local Claude Code execution design.
    ///
    /// Takes the skill set rather than reading a singleton: hidden global state makes
    /// every gate untestable, and a new observable service type would trip landmine 3.
    func isBuilt(builtSkills: Set<String>) -> Bool {
        switch category {
        case .skills:     return builtSkills.contains(id)
        case .connectors: return ConnectorProvider(rawValue: id) != nil
        case .agents:     return false
        }
    }
}

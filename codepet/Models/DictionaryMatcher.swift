import Foundation

/// Matches dictionary terms to the user's projects by tech-stack tag overlap.
///
/// Mirrors `ReadingMatcher` (see ReadingMatcher.swift): it reuses
/// `ProjectSignals.inferTags(from:brief:)` to infer a project's stack, then
/// scores each term by how many of its `tags` overlap. This is *tag-level*
/// matching (project stack) — it does NOT scan the user's actual code for
/// literal term usage.
struct DictionaryMatcher {

    /// A term matched to a project, with its tag-overlap score.
    struct MatchedTerm: Identifiable {
        let term: DictionaryTerm
        let score: Int
        var id: String { term.id }
    }

    /// The terms relevant to a single project.
    struct ProjectTermGroup: Identifiable {
        let projectName: String
        let projectPath: String?
        let tags: Set<ProjectTag>     // the project's inferred stack (for pills)
        let terms: [MatchedTerm]
        var id: String { projectPath ?? "__universal__" }
    }

    /// Build the top panel (Surface B): the most-recent project's stack and the
    /// dictionary terms that belong to it, best matches first. Returns `nil`
    /// when there's no project or the project's stack yields no tags.
    static func match(projects: [String: Project], maxTerms: Int = 12) -> ProjectTermGroup? {
        guard let primary = projects.values.sorted(by: { $0.lastSeenAt > $1.lastSeenAt }).first
        else { return nil }

        let projectTags = ProjectSignals.inferTags(from: primary.id, brief: primary.brief)
        guard !projectTags.isEmpty else { return nil }

        let scored = DictionaryContent.terms.compactMap { term -> MatchedTerm? in
            guard !term.tags.isEmpty else { return nil }     // universal terms never match a stack
            let overlap = Set(term.tags).intersection(projectTags).count
            return overlap > 0 ? MatchedTerm(term: term, score: overlap) : nil
        }
        .sorted { $0.score > $1.score }

        guard !scored.isEmpty else { return nil }

        return ProjectTermGroup(
            projectName: primary.displayName,
            projectPath: primary.id,
            tags: projectTags,
            terms: Array(scored.prefix(maxTerms))
        )
    }

    /// Per-card lookup for the passive badge (Surface A). Given a term and the
    /// already-inferred tags + name of the primary project, returns the project
    /// name when the term belongs to that stack, else `nil`.
    ///
    /// Callers infer `projectTags` ONCE (in `DictionaryView`) and pass them in,
    /// so this stays cheap even when called for every visible card.
    static func projectUsing(
        _ term: DictionaryTerm,
        projectTags: Set<ProjectTag>,
        projectName: String
    ) -> String? {
        guard !term.tags.isEmpty, !projectTags.isEmpty else { return nil }
        return Set(term.tags).isDisjoint(with: projectTags) ? nil : projectName
    }
}

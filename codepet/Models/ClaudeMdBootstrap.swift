import Foundation

/// Composes a seed CLAUDE.md for a freshly-linked project that has none — the
/// coding agent's standing context, drawn from the founder's brief + decisions.
/// Pure and deterministic. The app writes this only with the founder's consent
/// and only when no CLAUDE.md already exists (never clobbers an existing one).
enum ClaudeMdBootstrap {
    static func compose(brief: CompanyBrief, decisions: [DecisionEntry]) -> String {
        let clip = { (s: String?) -> String? in
            let t = (s ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return t.isEmpty ? nil : t
        }
        let project = clip(brief.projectName) ?? "This project"
        var out = ["# \(project) — project context"]

        if let one = clip(brief.oneLiner) ?? clip(brief.summary) { out.append("\n\(one)") }

        var about: [String] = []
        if let f = clip(brief.founderName) {
            about.append("- Founder: \(f)" + (clip(brief.role).map { " (\($0))" } ?? ""))
        }
        if let s = clip(brief.stage) { about.append("- Stage: \(s)") }
        if let t = clip(brief.tech) { about.append("- Tech: \(t)") }
        if !about.isEmpty { out.append("\n## About\n" + about.joined(separator: "\n")) }

        let facts = decisions
            .map { ($0.topic.trimmingCharacters(in: .whitespacesAndNewlines),
                    $0.statement.trimmingCharacters(in: .whitespacesAndNewlines)) }
            .filter { !$0.0.isEmpty && !$0.1.isEmpty }
        if !facts.isEmpty {
            out.append("\n## Decisions\n" + facts.map { "- \($0.0): \($0.1)" }.joined(separator: "\n"))
        }

        out.append("\n<!-- Seeded by Codepet from your brief + decisions. Edit freely. -->")
        return out.joined(separator: "\n")
    }
}

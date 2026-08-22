// codepet/Models/ProjectIdentity.swift
import Foundation

/// The hints that let a folder linked on one machine be recognised as a project the
/// founder already has, rather than minted as a second one.
///
/// Both are hints and neither is an identity. `gitRemote` is strong enough to propose a
/// match; `folderName` is only ever shown to the founder so they can tell two candidates
/// apart. Nothing here is trusted enough to merge two projects without being asked.
struct ProjectHints: Codable, Hashable, Sendable {
    var gitRemote: String?
    var folderName: String?
}

/// A project's identity — minted once, opaque forever.
///
/// Deliberately carries nothing derived from the machine. An absolute path, or any hash
/// of one, would put the same repo under two different keys on two machines and silently
/// orphan every fact scoped to it. That was the first draft of the design and it was
/// wrong; see §4.1 and §4.3 of the spec.
enum ProjectIdentity {

    /// A fresh id. 32 lowercase hex characters — a UUID with its dashes removed, which is
    /// safe as a Firestore document ID (no `/`, no leading `.`, well under the length cap).
    static func mint() -> String {
        UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
    }

    /// A git remote reduced to the part that identifies the repository, so the same repo
    /// cloned over ssh on one machine and https on another compares equal.
    ///
    /// Drops the scheme, any `user@`, the `.git` suffix, a trailing slash, and case. What
    /// survives is `host/owner/name`. Returns nil for nil or blank — an absent hint must
    /// never match another absent hint.
    static func normalizeRemote(_ raw: String?) -> String? {
        var s = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return nil }

        // scp-style (`git@host:owner/name`) has no scheme and uses `:` as the separator.
        if let at = s.firstIndex(of: "@"), !s.contains("://") {
            s = String(s[s.index(after: at)...])
            if let colon = s.firstIndex(of: ":") {
                s.replaceSubrange(colon...colon, with: "/")
            }
        } else if let range = s.range(of: "://") {
            s = String(s[range.upperBound...])
            // A URL form can still carry credentials before the host.
            if let at = s.firstIndex(of: "@") { s = String(s[s.index(after: at)...]) }
        }

        while s.hasSuffix("/") { s.removeLast() }
        if s.hasSuffix(".git") { s.removeLast(4) }
        s = s.lowercased()
        return s.isEmpty ? nil : s
    }

    /// Package what is known about a folder. Blank strings become nil so an empty hint is
    /// never mistaken for a present one.
    static func hints(folderName: String?, gitRemote: String?) -> ProjectHints {
        let name = (folderName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return ProjectHints(gitRemote: normalizeRemote(gitRemote),
                            folderName: name.isEmpty ? nil : name)
    }
}

/// A project as the cloud holds it. The local path is deliberately absent — it lives in
/// `ProjectIdentityMap` because it describes one machine.
struct CloudProject: Codable, Hashable, Sendable {
    let id: String
    var hints: ProjectHints
    var displayName: String
}

/// What to do with a folder the founder just linked.
enum ProjectMatch: Equatable {
    /// This machine already knows the folder. Nothing to ask.
    case bound(String)
    /// A hint says this is an existing project. The founder confirms before anything binds.
    case propose(String, reason: String)
    /// No usable hint, or an ambiguous one. Mint a new id.
    case mint
}

extension ProjectIdentity {

    /// Resolve a linked folder to a project.
    ///
    /// Pure, so the interesting cases — no remote, wrong remote, two projects with the
    /// same remote — are all provable without a folder, a network, or a founder.
    ///
    /// A remote hit is `.propose`, never `.bound`. Adopting it silently would attach one
    /// repo's memory to another with nothing on screen, and a duplicate project is the
    /// cheaper mistake: it is visible, and it can be merged later. Wrongly merged memory
    /// is neither.
    ///
    /// `folderName` never decides anything. Two unrelated checkouts called `api` are
    /// ordinary, and a hint that common is not evidence — it exists only so the founder
    /// can tell two candidates apart when asked.
    static func match(localId: String?,
                      hints: ProjectHints,
                      against projects: [CloudProject]) -> ProjectMatch {
        if let bound = localId?.trimmingCharacters(in: .whitespacesAndNewlines), !bound.isEmpty {
            return .bound(bound)
        }
        guard let remote = hints.gitRemote else { return .mint }

        let hits = projects.filter { $0.hints.gitRemote == remote }
        // Exactly one, or nothing to say. Two projects claiming one remote is a state the
        // founder has to resolve, and picking either would be a coin toss with their memory.
        guard hits.count == 1, let hit = hits.first else { return .mint }

        return .propose(hit.id, reason: remote)
    }
}

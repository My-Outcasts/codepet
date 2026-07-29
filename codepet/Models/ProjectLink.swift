import Foundation

/// A project folder the founder deliberately linked for the coding agent. Pure
/// value type — the filesystem probe that builds it is `ProjectProbe`. Its
/// `slice` is the client-only `CompanyContext.project` view (never sent to the
/// cloud; see Part 1's client-only invariant).
struct ProjectLink: Equatable {
    let path: String
    let isGitRepo: Bool
    let hasClaudeMd: Bool

    /// The client-only context slice for this link. `recentChangeSummary` is nil
    /// until the runner (2B) can summarize local changes.
    var slice: CompanyContext.ProjectSlice {
        CompanyContext.ProjectSlice(
            path: path, isGitRepo: isGitRepo, hasClaudeMd: hasClaudeMd, recentChangeSummary: nil)
    }
}

/// Filesystem detection for a linked project. Deterministic given the directory's
/// contents (`.git` dir → git repo; `CLAUDE.md` file → has CLAUDE.md).
enum ProjectProbe {
    static func claudeMdURL(forProjectAt path: String) -> URL {
        URL(fileURLWithPath: path).appendingPathComponent("CLAUDE.md")
    }

    static func probe(path: String) -> ProjectLink {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        let gitPath = (path as NSString).appendingPathComponent(".git")
        let isGit = fm.fileExists(atPath: gitPath, isDirectory: &isDir) && isDir.boolValue
        let hasClaude = fm.fileExists(atPath: claudeMdURL(forProjectAt: path).path)
        return ProjectLink(path: path, isGitRepo: isGit, hasClaudeMd: hasClaude)
    }
}

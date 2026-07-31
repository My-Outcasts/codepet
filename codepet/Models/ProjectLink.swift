import Foundation

/// A project folder the founder deliberately linked for the coding agent. Pure
/// value type — the filesystem probe that builds it is `ProjectProbe`.
///
/// PORT NOTE (Task 3, feat/coding-agent-copilot): the source (`feat/chat-redesign`)
/// also exposes a `slice: CompanyContext.ProjectSlice` computed property — a view
/// onto the redesign's cloud-grounding "Capability Bus" (`CompanyContext`). That
/// type does not exist on `main` and is out of scope for this port (the plan's own
/// "Deferred" section excludes cloud `byte` auto-initiating `edit_code`, the only
/// consumer of this slice). `slice` is dropped here as dead code for this port;
/// nothing in the 15-task plan (docs/superpowers/plans/2026-07-31-coding-agent-in-copilot.md)
/// references it. Re-add it if/when `CompanyContext` is ported.
struct ProjectLink: Equatable {
    let path: String
    let isGitRepo: Bool
    let hasClaudeMd: Bool
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
        var claudeIsDir: ObjCBool = false
        let hasClaude = fm.fileExists(atPath: claudeMdURL(forProjectAt: path).path, isDirectory: &claudeIsDir)
            && !claudeIsDir.boolValue   // a real file, not a dir named CLAUDE.md
        return ProjectLink(path: path, isGitRepo: isGit, hasClaudeMd: hasClaude)
    }
}

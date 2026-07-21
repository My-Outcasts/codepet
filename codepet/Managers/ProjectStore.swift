import Foundation
import Combine
import os

/// Manages auto-detected projects. Infers project identity from `cwd` paths
/// by walking up to find a `.git` directory (or falling back to the cwd itself).
///
/// Persists project metadata (display name, brief) to UserDefaults so projects
/// and their briefs survive app restarts.
@MainActor
final class ProjectStore: ObservableObject {

    /// All known projects, keyed by normalized project root path.
    @Published private(set) var projects: [String: Project] = [:]

    /// The project the user is currently focused on in the Reflection tab
    /// (resolved from the selected session). Project Health observes this to
    /// highlight the same project as its active folder tab. Nil when the focus
    /// isn't a detected project (e.g. the welcome session).
    @Published var activeProjectPath: String? = nil

    /// Project paths in the exact order Reflection lists its groups — most recent
    /// activity first, and ONLY projects that actually have sessions. Project
    /// Health renders its folder tabs in this order so the two stay in lockstep
    /// (instead of diverging on lastSeenAt, which the hook pipeline updates
    /// differently). Empty until Reflection has been shown at least once.
    @Published var reflectionProjectOrder: [String] = []

    /// Set the Reflection-focused project. No-op if unchanged.
    func setActiveProject(_ path: String?) {
        let normalized = (path?.isEmpty == true) ? nil : path
        if activeProjectPath != normalized { activeProjectPath = normalized }
    }

    /// Publish Reflection's ordered project list (see `reflectionProjectOrder`).
    /// No-op if unchanged.
    func setReflectionProjectOrder(_ paths: [String]) {
        if reflectionProjectOrder != paths { reflectionProjectOrder = paths }
    }

    /// Cache: session-specific key → resolved project root path.
    /// Key is "cwd" for single-project workspaces, or "sessionId" for sessions
    /// whose cwd was disambiguated using file paths.
    /// Populated by `detectProject` so `resolvedProjectPath` is a simple lookup.
    private var cwdToRoot: [String: String] = [:]
    /// Per-session override when multiple projects share the same cwd.
    private var sessionToRoot: [String: String] = [:]

    /// Ordered list of projects sorted by most recently seen.
    var sortedProjects: [Project] {
        projects.values.sorted { $0.lastSeenAt > $1.lastSeenAt }
    }

    /// User-assigned overrides: sessionId → projectPath. Persisted to UserDefaults
    /// so manual reassignments survive app restarts.
    private var manualOverrides: [String: String] = [:]

    /// Project paths whose description the user typed/edited by hand. ONLY
    /// these are protected: the from-history synthesis may overwrite any other
    /// description (empty, per-session auto-fill, or a legacy auto value), but
    /// never one in this set. Positive tracking is deliberate — it correctly
    /// leaves machine-written descriptions (which carry no marker) replaceable.
    private var userEditedBriefs: Set<String> = []
    /// Project paths whose one-time from-history brief backfill has run, so it
    /// runs at most once per project.
    private var backfilledBriefs: Set<String> = []

    private let userDefaultsKey = "cp_detected_projects"
    private let overridesKey = "cp_session_project_overrides"
    private let userEditedBriefsKey = "cp_brief_user_edited"
    private let backfilledBriefsKey = "cp_brief_backfilled"
    private let logger = Logger(subsystem: "app.murror.codepet", category: "ProjectStore")

    // MARK: - Persistence

    func load() {
        if let data = UserDefaults.standard.data(forKey: userDefaultsKey),
           let decoded = try? JSONDecoder().decode([String: Project].self, from: data) {
            projects = decoded
            logger.info("Loaded \(decoded.count) persisted projects")
        } else {
            logger.info("No persisted projects found — starting fresh")
        }
        // Restore manual overrides
        if let overrides = UserDefaults.standard.dictionary(forKey: overridesKey) as? [String: String] {
            manualOverrides = overrides
            // Warm the sessionToRoot cache from persisted overrides
            for (sid, path) in overrides { sessionToRoot[sid] = path }
            logger.info("Loaded \(overrides.count) manual session overrides")
        }
        // Restore brief ownership / backfill markers
        if let edited = UserDefaults.standard.stringArray(forKey: userEditedBriefsKey) {
            userEditedBriefs = Set(edited)
        }
        if let done = UserDefaults.standard.stringArray(forKey: backfilledBriefsKey) {
            backfilledBriefs = Set(done)
        }
    }

    /// Wipe all detected projects, caches, and manual overrides. Called on
    /// account switch so a new user doesn't inherit the previous user's projects.
    func resetAll() {
        projects = [:]
        cwdToRoot = [:]
        sessionToRoot = [:]
        manualOverrides = [:]
        userEditedBriefs = []
        backfilledBriefs = []
        UserDefaults.standard.removeObject(forKey: userDefaultsKey)
        UserDefaults.standard.removeObject(forKey: overridesKey)
        UserDefaults.standard.removeObject(forKey: userEditedBriefsKey)
        UserDefaults.standard.removeObject(forKey: backfilledBriefsKey)
        logger.info("ProjectStore reset for account switch")
    }

    /// Re-hydrate in-memory state from the (account-swapped) UserDefaults keys.
    /// Clears first so a fresh account doesn't inherit the previous projects,
    /// then loads. Does NOT remove keys (unlike `resetAll`).
    func reload() {
        projects = [:]
        cwdToRoot = [:]
        sessionToRoot = [:]
        manualOverrides = [:]
        userEditedBriefs = []
        backfilledBriefs = []
        load()
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(projects) else { return }
        UserDefaults.standard.set(data, forKey: userDefaultsKey)
    }

    private func persistBriefMarkers() {
        UserDefaults.standard.set(Array(userEditedBriefs), forKey: userEditedBriefsKey)
        UserDefaults.standard.set(Array(backfilledBriefs), forKey: backfilledBriefsKey)
    }

    private func persistOverrides() {
        UserDefaults.standard.set(manualOverrides, forKey: overridesKey)
    }

    // MARK: - Project Detection

    /// Given a raw `cwd` path from a JSONL event, returns the normalized
    /// project root path. Creates a new Project entry if this is the first
    /// time we've seen this project.
    ///
    /// `filePaths` are optional tool-event paths (e.g. edited files) that help
    /// disambiguate when a workspace contains multiple git repos.
    ///
    /// Returns `nil` if `cwd` is empty or looks invalid (e.g. `/`).
    @discardableResult
    func detectProject(cwd: String, filePaths: [String] = [], sessionId: String? = nil) -> Project? {
        let trimmed = cwd.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != "/" else { return nil }

        let root = findProjectRoot(from: trimmed, filePaths: filePaths)
        cwdToRoot[trimmed] = root  // cache the resolution (last-writer-wins for same cwd)
        // Also store per-session mapping — critical when multiple sessions share
        // the same cwd but work in different child repos.
        if let sid = sessionId { sessionToRoot[sid] = root }

        if var existing = projects[root] {
            existing.lastSeenAt = Date()
            projects[root] = existing
            persist()
            return existing
        }

        let project = Project(
            id: root,
            displayName: Project.nameFromPath(root),
            brief: "",
            firstSeenAt: Date(),
            lastSeenAt: Date()
        )
        projects[root] = project

        // Auto-prune: if the resolved root is a child of a previously detected
        // "project" that was really a workspace folder, remove the stale parent
        // (only if the parent has no user-written brief).
        // e.g. root = ".../Test folder/yoga-site", stale = ".../Test folder"
        let staleParents = projects.keys.filter { key in
            guard key != root else { return false }
            let keySlash = key.hasSuffix("/") ? key : key + "/"
            return root.hasPrefix(keySlash) && (projects[key]?.brief.isEmpty ?? true)
        }
        for stale in staleParents {
            logger.info("Pruning stale parent project: \(stale) (replaced by \(root))")
            projects.removeValue(forKey: stale)
        }

        persist()
        logger.info("New project detected: \(project.displayName) at \(root)")
        return project
    }

    /// Look up a project by its root path without creating it.
    func project(for path: String?) -> Project? {
        guard let path = path else { return nil }
        return projects[path]
    }

    /// Resolve a session to the canonical project root path.
    /// Prefers per-session resolution (populated by `detectProject(sessionId:)`),
    /// then falls back to cwd-level cache, then heuristics.
    func resolvedProjectPath(for rawCwd: String?, sessionId: String? = nil) -> String? {
        // 0a. Manual override — user explicitly moved this session
        if let sid = sessionId, let manual = manualOverrides[sid] { return manual }
        // 0b. Per-session auto-detection cache
        if let sid = sessionId, let cached = sessionToRoot[sid] { return cached }

        guard let cwd = rawCwd, !cwd.isEmpty else { return nil }

        // 1. Check the resolution cache (populated by detectProject)
        if let cached = cwdToRoot[cwd] { return cached }

        // 2. Direct match — cwd IS a known project root
        if projects[cwd] != nil { return cwd }

        // 3. cwd is a child of a known project (e.g. "yoga-site/app" → "yoga-site")
        for knownRoot in projects.keys {
            let rootSlash = knownRoot.hasSuffix("/") ? knownRoot : knownRoot + "/"
            if cwd.hasPrefix(rootSlash) { return knownRoot }
        }

        // 4. No match — return as-is
        return cwd
    }

    /// Try to detect a project purely from file paths (no cwd).
    /// Used when a session has empty cwd but tool events have file paths.
    @discardableResult
    func detectProjectFromFilePaths(_ filePaths: [String], sessionId: String? = nil) -> Project? {
        guard !filePaths.isEmpty else { return nil }
        let fs = FileManager.default
        var rootVotes: [String: Int] = [:]
        for filePath in filePaths {
            var dir = URL(fileURLWithPath: filePath).deletingLastPathComponent()
            for _ in 0..<10 {
                if fs.fileExists(atPath: dir.appendingPathComponent(".git").path) {
                    rootVotes[dir.path, default: 0] += 1
                    break
                }
                let parent = dir.deletingLastPathComponent()
                if parent.path == dir.path { break }
                dir = parent
            }
        }
        guard let winner = rootVotes.max(by: { $0.value < $1.value }) else { return nil }
        let root = winner.key
        if let sid = sessionId { sessionToRoot[sid] = root }

        if var existing = projects[root] {
            existing.lastSeenAt = Date()
            projects[root] = existing
            persist()
            return existing
        }
        let project = Project(
            id: root,
            displayName: Project.nameFromPath(root),
            brief: "",
            firstSeenAt: Date(),
            lastSeenAt: Date()
        )
        projects[root] = project
        persist()
        logger.info("File-path detected project: \(project.displayName) at \(root)")
        return project
    }

    // MARK: - Manual Session Assignment

    /// Manually assign a session to a project. Persists across app restarts.
    func assignSession(_ sessionId: String, to projectPath: String) {
        manualOverrides[sessionId] = projectPath
        sessionToRoot[sessionId] = projectPath
        persistOverrides()
        // Trigger UI update by touching the projects dict
        objectWillChange.send()
        logger.info("Manually assigned session \(sessionId) → \(Project.nameFromPath(projectPath))")
    }

    /// Remove a manual override for a session (revert to auto-detection).
    func removeSessionOverride(_ sessionId: String) {
        manualOverrides.removeValue(forKey: sessionId)
        sessionToRoot.removeValue(forKey: sessionId)
        persistOverrides()
        objectWillChange.send()
    }

    // MARK: - Brief Management

    /// Update the brief for a project.
    func updateBrief(projectId: String, brief: String) {
        guard var project = projects[projectId] else { return }
        project.brief = brief
        projects[projectId] = project
        persist()
        logger.info("Updated brief for \(project.displayName)")
    }

    /// Get the brief for a project path, or empty string if unknown.
    func brief(for projectPath: String?) -> String {
        guard let path = projectPath else { return "" }
        return projects[path]?.brief ?? ""
    }

    /// Read the structured founder brief for a project path, if any.
    func companyBrief(for projectPath: String?) -> CompanyBrief? {
        guard let path = projectPath else { return nil }
        return projects[path]?.companyBrief
    }

    /// Set the structured founder brief. Recomposes the flat `brief` string and
    /// marks the project user-owned so from-history synthesis never overwrites it.
    func setCompanyBrief(projectId: String, brief: CompanyBrief) {
        guard var project = projects[projectId] else { return }
        project.companyBrief = brief
        if let composed = BriefContext.compose(brief) { project.brief = composed }
        projects[projectId] = project
        markBriefUserOwned(projectPath: projectId)   // persists markers
        persist()                                    // persists projects dict
        logger.info("Set founder brief for \(project.displayName)")
    }

    // MARK: - Brief ownership & backfill

    /// True only when the user has NOT hand-edited this project's description,
    /// so the from-history synthesis is free to (re)write it. Empty, per-session
    /// auto-filled, and legacy machine-written descriptions are all writable.
    func briefDescriptionIsSynthesisWritable(projectPath: String) -> Bool {
        !userEditedBriefs.contains(projectPath)
    }

    /// Mark a project's description as user-owned — the user typed it, so
    /// synthesis must never overwrite it again. Also marks backfill done.
    func markBriefUserOwned(projectPath: String) {
        userEditedBriefs.insert(projectPath)
        backfilledBriefs.insert(projectPath)
        persistBriefMarkers()
    }

    /// Whether the one-time from-history backfill has already run for a project.
    func briefBackfillDone(projectPath: String) -> Bool {
        backfilledBriefs.contains(projectPath)
    }

    /// Mark the one-time from-history backfill as complete for a project.
    func markBriefBackfilled(projectPath: String) {
        backfilledBriefs.insert(projectPath)
        persistBriefMarkers()
    }

    // MARK: - Stage & Attestations (Project Health)

    /// Set the lifecycle stage for a project. Passing `nil` reverts to
    /// engine-inferred stage.
    func setStage(projectId: String, stage: ProjectStage?) {
        guard var project = projects[projectId] else { return }
        project.stage = stage
        projects[projectId] = project
        persist()
        logger.info("Set stage \(stage?.rawValue ?? "auto") for \(project.displayName)")
    }

    /// Toggle a self-attested health rule for a project ("Mark done" / undo).
    func toggleAttestation(projectId: String, ruleId: String) {
        guard var project = projects[projectId] else { return }
        if project.attestations.contains(ruleId) {
            project.attestations.remove(ruleId)
        } else {
            project.attestations.insert(ruleId)
        }
        projects[projectId] = project
        persist()
    }

    // MARK: - Project Root Detection

    /// Resolves a `cwd` to a project root using strategies in order:
    ///
    /// 1. **Walk up** from `cwd` looking for `.git` — handles the common case
    ///    where Claude Code runs from within a repo.
    /// 2. **Scan one level down** — handles the Cursor/VS Code pattern where
    ///    the workspace root is a parent folder containing project repos
    ///    (e.g. `~/Downloads/Test folder/yoga-site/.git`).
    ///    When multiple repos exist, uses `filePaths` to vote for the most
    ///    referenced child.
    /// 3. **File-path resolution** — when cwd doesn't match any git root,
    ///    walk up from actual file paths (tool events) to find the real project.
    ///    Handles Cursor workspaces where cwd ≠ project (e.g. `~/Test folder`
    ///    cwd but editing `~/Desktop/sprout/index.html`).
    /// 4. **Match known projects** — if `cwd` is a parent of an already-known
    ///    project, return that project's root instead of creating a new one.
    /// 5. **Fallback** — use `cwd` as-is.
    private func findProjectRoot(from path: String, filePaths: [String] = []) -> String {
        let fs = FileManager.default

        // Strategy 1: Walk up looking for .git
        var current = URL(fileURLWithPath: path)
        for _ in 0..<10 {
            let gitDir = current.appendingPathComponent(".git")
            if fs.fileExists(atPath: gitDir.path) {
                return current.path
            }
            let parent = current.deletingLastPathComponent()
            if parent.path == current.path { break }
            current = parent
        }

        // Strategy 2: Scan one level down for .git subdirectories
        let cwdURL = URL(fileURLWithPath: path)
        if let children = try? fs.contentsOfDirectory(
            at: cwdURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) {
            let gitChildren = children.filter { child in
                var isDir: ObjCBool = false
                let gitPath = child.appendingPathComponent(".git").path
                return fs.fileExists(atPath: gitPath, isDirectory: &isDir)
            }
            // If exactly one child repo found, use it as the project root.
            if gitChildren.count == 1 {
                return gitChildren[0].path
            }
            // If multiple child repos, use filePaths to vote for the best match.
            // Each file path that starts with a child's path is a vote for that child.
            if gitChildren.count > 1 && !filePaths.isEmpty {
                let cwdPrefix = path.hasSuffix("/") ? path : path + "/"
                var votes: [String: Int] = [:]
                for child in gitChildren {
                    let childPrefix = child.path.hasSuffix("/") ? child.path : child.path + "/"
                    let count = filePaths.filter { $0.hasPrefix(childPrefix) || $0.hasPrefix(cwdPrefix + child.lastPathComponent + "/") }.count
                    if count > 0 { votes[child.path] = count }
                }
                // Pick the child with the most file-path votes
                if let winner = votes.max(by: { $0.value < $1.value }) {
                    logger.info("Multi-repo workspace: \(votes.count) candidates, winner=\(winner.key) (\(winner.value) votes)")
                    return winner.key
                }
            }
        }

        // Strategy 3: Resolve from file paths — handles the Cursor pattern where
        // the workspace cwd (e.g. ~/Downloads/Test folder) differs from the actual
        // project being edited (e.g. ~/Desktop/sprout). Walk up from file path
        // directories to find a .git root.
        if !filePaths.isEmpty {
            var rootVotes: [String: Int] = [:]
            for filePath in filePaths {
                var dir = URL(fileURLWithPath: filePath).deletingLastPathComponent()
                for _ in 0..<10 {
                    let gitDir = dir.appendingPathComponent(".git")
                    if fs.fileExists(atPath: gitDir.path) {
                        rootVotes[dir.path, default: 0] += 1
                        break
                    }
                    let parent = dir.deletingLastPathComponent()
                    if parent.path == dir.path { break }
                    dir = parent
                }
            }
            // Pick the git root referenced by the most file paths
            if let winner = rootVotes.max(by: { $0.value < $1.value }) {
                logger.info("File-path derived project: \(winner.key) (\(winner.value) votes from \(filePaths.count) paths)")
                return winner.key
            }
        }

        // Strategy 4: Check if cwd is a parent of any already-known project.
        // e.g. cwd = "~/Test folder", known project = "~/Test folder/yoga-site"
        let cwdWithSlash = path.hasSuffix("/") ? path : path + "/"
        let matchingProjects = projects.keys.filter { $0.hasPrefix(cwdWithSlash) }
        if matchingProjects.count == 1 {
            return matchingProjects[0]
        }

        // Strategy 5: Fallback — use cwd as-is
        return path
    }
}

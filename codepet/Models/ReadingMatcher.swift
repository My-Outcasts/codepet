import Foundation

// MARK: - Project Signal Inference

/// Infers `ProjectTag`s from a project's file-system path by looking at known
/// file extensions, config files, and directory names in the project root.
///
/// This runs purely on the path string — no file-system I/O — so it's safe
/// to call from the main thread.
enum ProjectSignals {

    /// Mapping: file/directory pattern → inferred tags.
    /// Patterns are checked against the last path component OR well-known
    /// nested paths (e.g. ".github/workflows").
    private static let rules: [(pattern: String, tags: [ProjectTag])] = [
        // Swift / Apple
        (".xcodeproj",               [.swiftUI, .mobile]),
        (".xcworkspace",             [.swiftUI, .mobile]),
        ("Package.swift",            [.swiftUI]),
        ("GoogleService-Info.plist", [.firebase]),
        ("firebase.json",           [.firebase]),
        (".firebaserc",             [.firebase]),

        // Web frontend
        ("package.json",            [.nodeBackend]),   // refined below by deps
        ("next.config",             [.react]),
        ("nuxt.config",             [.vue]),
        ("angular.json",            [.angular]),
        ("vite.config",             [.react]),         // most Vite users are React
        ("tsconfig.json",           [.react]),         // loose signal, overridden by framework

        // Python
        ("requirements.txt",        [.python]),
        ("pyproject.toml",          [.python]),
        ("setup.py",                [.python]),
        ("Pipfile",                 [.python]),

        // Go
        ("go.mod",                  [.goLang]),

        // Rust
        ("Cargo.toml",             [.rust]),

        // Infra
        ("Dockerfile",             [.docker]),
        ("docker-compose",         [.docker]),
        (".github/workflows",      [.ci]),
        (".gitlab-ci.yml",         [.ci]),
        ("Jenkinsfile",            [.ci]),

        // Database
        ("prisma",                 [.database]),
        (".sql",                   [.database]),
        ("knexfile",               [.database]),
        ("sequelize",              [.database]),

        // API
        ("openapi",                [.api]),
        ("swagger",                [.api]),
        ("schema.graphql",         [.api]),

        // Testing
        ("XCTest",                 [.testing]),
        ("jest.config",            [.testing]),
        ("pytest",                 [.testing]),
        (".test.",                 [.testing]),
        (".spec.",                 [.testing]),
    ]

    /// Infer tags from a project root path.
    /// The path string is searched for known markers — this does NOT read the
    /// file system, so it works in sandboxed environments.
    static func inferTags(from projectPath: String) -> Set<ProjectTag> {
        var tags = Set<ProjectTag>()
        let lowered = projectPath.lowercased()

        for rule in rules {
            if lowered.contains(rule.pattern.lowercased()) {
                tags.formUnion(rule.tags)
            }
        }

        return tags
    }

    /// Infer tags from a project path + its brief text.
    /// The brief often contains keywords like "SwiftUI", "React", "Firebase"
    /// that give strong signals about the tech stack.
    static func inferTags(from projectPath: String, brief: String) -> Set<ProjectTag> {
        var tags = inferTags(from: projectPath)

        let briefLower = brief.lowercased()
        let briefRules: [(keyword: String, tags: [ProjectTag])] = [
            ("swiftui",      [.swiftUI]),
            ("uikit",        [.uiKit]),
            ("react",        [.react]),
            ("vue",          [.vue]),
            ("angular",      [.angular]),
            ("python",       [.python]),
            ("django",       [.python, .api]),
            ("flask",        [.python, .api]),
            ("fastapi",      [.python, .api]),
            ("node",         [.nodeBackend]),
            ("express",      [.nodeBackend, .api]),
            ("firebase",     [.firebase]),
            ("firestore",    [.firebase, .database]),
            ("docker",       [.docker]),
            ("kubernetes",   [.docker]),
            ("ci/cd",        [.ci]),
            ("github actions", [.ci]),
            ("postgres",     [.database]),
            ("mongodb",      [.database]),
            ("core data",    [.database, .swiftUI]),
            ("graphql",      [.api]),
            ("rest api",     [.api]),
            ("core ml",      [.swiftUI, .mobile]),
            ("ios",          [.mobile, .swiftUI]),
            ("android",      [.mobile]),
            ("macos",        [.swiftUI]),
            ("golang",       [.goLang]),
            ("rust",         [.rust]),
        ]

        for rule in briefRules {
            if briefLower.contains(rule.keyword) {
                tags.formUnion(rule.tags)
            }
        }

        return tags
    }

    /// Infer what a project is ABOUT (its domain) from its path + brief. This
    /// is independent of the tech stack, so two SwiftUI apps (e.g. a budget
    /// tracker vs a yoga app) infer different domains and get different books.
    static func inferDomains(from projectPath: String, brief: String) -> Set<ProjectDomain> {
        let haystack = (projectPath + " " + brief).lowercased()
        var domains = Set<ProjectDomain>()

        let rules: [(keyword: String, domain: ProjectDomain)] = [
            // Finance
            ("money", .finance), ("budget", .finance), ("expense", .finance), ("finance", .finance),
            ("bank", .finance), ("invoice", .finance), ("payment", .finance), ("wallet", .finance),
            ("crypto", .finance), ("trading", .finance), ("accounting", .finance), ("spending", .finance),
            // Health
            ("health", .health), ("fitness", .health), ("workout", .health), ("yoga", .health),
            ("wellness", .health), ("habit", .health), ("meditat", .health), ("diet", .health),
            ("gym", .health), ("nutrition", .health), ("mindful", .health),
            // E-commerce
            ("shop", .ecommerce), ("cart", .ecommerce), ("checkout", .ecommerce),
            ("ecommerce", .ecommerce), ("e-commerce", .ecommerce), ("commerce", .ecommerce), ("retail", .ecommerce),
            // Productivity
            ("todo", .productivity), ("to-do", .productivity), ("planner", .productivity),
            ("calendar", .productivity), ("journal", .productivity), ("productiv", .productivity),
            // Games
            ("game", .games), ("arcade", .games), ("puzzle", .games),
            // Social
            ("social", .social), ("chat", .social), ("messag", .social), ("community", .social),
            // Education
            ("course", .education), ("quiz", .education), ("lesson", .education),
            ("student", .education), ("tutor", .education), ("flashcard", .education),
            // Content
            ("blog", .content), ("cms", .content), ("portfolio", .content),
        ]

        for r in rules where haystack.contains(r.keyword) {
            domains.insert(r.domain)
        }

        return domains
    }
}

// MARK: - Reading Matcher

/// Matches readings from the expanded pool to user projects.
///
/// Algorithm:
/// 1. Filter pool by the active pet's domain
/// 2. For each project, score each reading by tag overlap
/// 3. Pick top N per project (default 2-3)
/// 4. If no projects exist, fall back to the pet's first 2 entries (universal picks)
struct ReadingMatcher {

    /// A reading matched to a specific project.
    struct MatchedReading: Identifiable {
        let item: TipReadingItem
        let projectName: String?      // nil = universal / no-project fallback
        let projectPath: String?      // nil = universal
        let score: Int                // tag overlap count

        var id: String {
            "\(projectPath ?? "__universal__")_\(item.title(.en))"
        }
    }

    /// A group of readings matched to a project.
    struct ProjectReadingGroup: Identifiable {
        let projectName: String
        let projectPath: String?      // nil = universal fallback
        let readings: [MatchedReading]
        var id: String { projectPath ?? "__universal__" }
    }

    /// Match readings for the active pet against the user's projects.
    ///
    /// - Parameters:
    ///   - petId: The active pet character ID (e.g. "crash", "nova")
    ///   - projects: All known projects from ProjectStore
    ///   - maxPerProject: Maximum readings to show per project (default 3)
    /// - Returns: Reading groups sorted by project recency, or a single
    ///   universal group if no projects exist.
    static func match(
        petId: String,
        projects: [String: Project],
        maxPerProject: Int = 3
    ) -> [ProjectReadingGroup] {
        let pool = TipsContent.tipReadingPool[petId] ?? []
        guard !pool.isEmpty else { return [] }

        // No projects → fall back to first 2 readings (the "universal" picks)
        let sortedProjects = projects.values.sorted { $0.lastSeenAt > $1.lastSeenAt }
        if sortedProjects.isEmpty {
            let fallback = Array(pool.prefix(2)).map { item in
                MatchedReading(item: item, projectName: nil, projectPath: nil, score: 0)
            }
            return [ProjectReadingGroup(
                projectName: "General",
                projectPath: nil,
                readings: fallback
            )]
        }

        var groups: [ProjectReadingGroup] = []

        for project in sortedProjects {
            let projectTags = ProjectSignals.inferTags(from: project.id, brief: project.brief)
            let projectDomains = ProjectSignals.inferDomains(from: project.id, brief: project.brief)

            // Score each reading by tech overlap PLUS domain overlap, with
            // domain weighted higher (×2) so same-tech projects surface
            // different top picks based on what they're actually about. Each
            // project scores the FULL pool independently (no cross-project
            // dedup), so a strong book can recommend on several projects.
            var scored: [(item: TipReadingItem, score: Int)] = pool.map { item in
                let techOverlap = Set(item.tags).intersection(projectTags).count
                let domainOverlap = Set(item.domains).intersection(projectDomains).count
                return (item, techOverlap + 2 * domainOverlap)
            }

            // Sort by score descending, take top N. Only keep books that
            // genuinely match THIS project's detected tech (score > 0) — no
            // generic filler. Projects with no real match get no group, and the
            // UI shows a "not enough info yet" message instead.
            scored.sort { $0.score > $1.score }
            let picks = Array(scored.prefix(maxPerProject).filter { $0.score > 0 })

            let techMatched = picks.map { pair in
                MatchedReading(
                    item: pair.item,
                    projectName: project.displayName,
                    projectPath: project.id,
                    score: pair.score
                )
            }

            // Business / marketing readings, matched by the project's lifecycle
            // stage rather than its tech stack — so an idea-stage project (which
            // may have no detected tech at all) still gets validation/positioning
            // books, and a growth-stage project gets retention/marketing ones.
            let stage = ProjectHealthEngine.inferStage(for: project, tags: projectTags)
            let businessMatched = TipsContent.businessReadingPool
                .filter { $0.stages.isEmpty || $0.stages.contains(stage) }
                .prefix(maxBusinessPerProject)
                .map { item in
                    MatchedReading(
                        item: item,
                        projectName: project.displayName,
                        projectPath: project.id,
                        score: 0
                    )
                }

            // Tech picks lead (most specific to what they're building now), then
            // the stage-relevant business books. Skip the project entirely only
            // if neither axis matched.
            let combined = techMatched + businessMatched
            guard !combined.isEmpty else { continue }

            groups.append(ProjectReadingGroup(
                projectName: project.displayName,
                projectPath: project.id,
                readings: combined
            ))
        }

        return groups
    }

    /// Max business/marketing readings blended into each project group, so the
    /// stage-relevant books don't crowd out the pet's tech picks.
    private static let maxBusinessPerProject = 2
}

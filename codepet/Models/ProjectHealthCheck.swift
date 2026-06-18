import Foundation

// MARK: - Project Health Check System

/// Where a project sits in its lifecycle. Health checks are gated by stage so a
/// day-two builder isn't told they're missing a pricing page — that surfaces as
/// "coming up later" until the project reaches the relevant stage.
///
/// `nil` on `Project.stage` means "let the engine infer it" (see
/// `ProjectHealthEngine.inferStage`). The user can override via the folder header.
enum ProjectStage: String, Codable, CaseIterable, Identifiable {
    case idea       // exploring the problem, validating, no/little code
    case building   // actively writing the product
    case launch     // shipping to real users — monetization & marketing matter
    case growth     // live with users — retention, revenue, scaling

    var id: String { rawValue }

    /// Monotonic order used to compare a rule's `relevantFrom` against the
    /// project's current stage.
    var order: Int {
        switch self {
        case .idea:     return 0
        case .building: return 1
        case .launch:   return 2
        case .growth:   return 3
        }
    }

    var label: L10n {
        switch self {
        case .idea:     return L10n(vi: "Ý tưởng", en: "Idea")
        case .building: return L10n(vi: "Đang xây", en: "Building")
        case .launch:   return L10n(vi: "Ra mắt", en: "Launch")
        case .growth:   return L10n(vi: "Tăng trưởng", en: "Growth")
        }
    }
}

/// A dimension of project health. Engineering is what Codepet shipped first;
/// Business and Growth extend health into "will this make money."
enum HealthPillar: String, CaseIterable {
    case engineering
    case business
    case marketing
    case growth

    /// Display order in the folder body.
    var order: Int {
        switch self {
        case .engineering: return 0
        case .business:    return 1
        case .marketing:   return 2
        case .growth:      return 3
        }
    }

    var label: L10n {
        switch self {
        case .engineering: return L10n(vi: "Kỹ thuật", en: "Engineering")
        case .business:    return L10n(vi: "Kinh doanh", en: "Business")
        case .marketing:   return L10n(vi: "Tiếp thị", en: "Marketing")
        case .growth:      return L10n(vi: "Tăng trưởng", en: "Growth")
        }
    }
}

/// How a rule decides whether it passes.
enum HealthEvaluation {
    /// Detected from the project path / brief (and, where present, files).
    /// Can also be satisfied by user attestation.
    case auto
    /// No detectable trace — only the user confirming it ("Mark done") passes.
    case selfAttested
}

/// The resolved status of a rule for a specific project.
enum HealthState {
    case passed          // auto-detected
    case attested        // user manually confirmed
    case missing         // relevant now, but not satisfied
    case notYetRelevant  // gated behind a later stage
}

/// A single health check rule that can be evaluated against a project.
struct ProjectHealthRule {
    let id: String
    let title: L10n
    let description: L10n              // shown when the check passes
    let missingDescription: L10n       // shown when the check fails — actionable advice
    /// Which dimension this rule belongs to.
    let pillar: HealthPillar
    /// Earliest stage at which this check becomes relevant. Below this, the rule
    /// surfaces under "coming up later" rather than as a gap.
    let relevantFrom: ProjectStage
    /// How the rule is satisfied (auto-detect vs. user attestation).
    let evaluation: HealthEvaluation
    /// Which tags this rule applies to. Empty = universal (applies to all projects).
    let appliesTo: [ProjectTag]
    /// Patterns to look for in the project path or brief. If ANY match, the check passes.
    let detectPatterns: [String]
    /// Brief keywords that also indicate the check passes.
    let detectBriefKeywords: [String]
    /// Optional reading URL for "Learn more" link on missing items.
    let learnMoreURL: String?

    /// Defaults keep the existing engineering rules unchanged: they're all
    /// `.engineering`, auto-detected, and relevant once you're `.building`.
    init(
        id: String,
        title: L10n,
        description: L10n,
        missingDescription: L10n,
        pillar: HealthPillar = .engineering,
        relevantFrom: ProjectStage = .building,
        evaluation: HealthEvaluation = .auto,
        appliesTo: [ProjectTag],
        detectPatterns: [String],
        detectBriefKeywords: [String],
        learnMoreURL: String?
    ) {
        self.id = id
        self.title = title
        self.description = description
        self.missingDescription = missingDescription
        self.pillar = pillar
        self.relevantFrom = relevantFrom
        self.evaluation = evaluation
        self.appliesTo = appliesTo
        self.detectPatterns = detectPatterns
        self.detectBriefKeywords = detectBriefKeywords
        self.learnMoreURL = learnMoreURL
    }
}

/// Result of evaluating a health rule against a specific project.
struct ProjectHealthResult: Identifiable {
    let rule: ProjectHealthRule
    let state: HealthState
    var id: String { rule.id }

    /// A rule "counts" as healthy when auto-detected or user-confirmed.
    /// Kept as a computed Bool so existing call sites (`!result.passed`,
    /// `report.passedCount`) keep working unchanged.
    var passed: Bool { state == .passed || state == .attested }
}

/// All health results for one project.
struct ProjectHealthReport: Identifiable {
    let projectName: String
    let projectPath: String
    let stage: ProjectStage
    let inferredTags: Set<ProjectTag>
    /// Checks relevant at the project's current stage (passed / attested / missing).
    let results: [ProjectHealthResult]
    /// Checks gated behind a later stage (state == .notYetRelevant).
    let upcoming: [ProjectHealthResult]

    var id: String { projectPath }
    var passedCount: Int { results.filter(\.passed).count }
    var totalCount: Int { results.count }
    var hasMissingItems: Bool { passedCount < totalCount }

    /// Relevant-now results for a single pillar, missing-first.
    func results(for pillar: HealthPillar) -> [ProjectHealthResult] {
        results.filter { $0.rule.pillar == pillar }
    }
}

// MARK: - Health Check Engine

enum ProjectHealthEngine {

    // ─── Rule Definitions ────────────────────────────────────────────

    static let allRules: [ProjectHealthRule] = [

        // ── Universal (all projects) ─────────────────────────────────
        ProjectHealthRule(
            id: "brief_written",
            title: L10n(vi: "Mô tả dự án", en: "Project brief written"),
            description: L10n(vi: "Giúp pet hiểu dự án của bạn", en: "Helps the pet understand your project"),
            missingDescription: L10n(
                vi: "Viết mô tả ngắn cho dự án — pet sẽ đưa ra lời khuyên phù hợp hơn",
                en: "Write a short project description — the pet will give more relevant advice"
            ),
            relevantFrom: .idea,
            appliesTo: [],  // universal
            detectPatterns: [],
            detectBriefKeywords: [],  // checked specially — non-empty brief = pass
            learnMoreURL: nil
        ),

        // ── Swift / Apple ────────────────────────────────────────────
        ProjectHealthRule(
            id: "xctest",
            title: L10n(vi: "Unit test", en: "Unit tests"),
            description: L10n(vi: "Thư mục test đã tìm thấy", en: "Test directory found"),
            missingDescription: L10n(
                vi: "Chưa thấy test — thêm XCTest để bảo vệ code khi refactor",
                en: "No tests found — add XCTest to protect code during refactoring"
            ),
            appliesTo: [.swiftUI, .uiKit],
            detectPatterns: ["Tests", "tests", "XCTest", "xctest"],
            detectBriefKeywords: ["xctest", "unit test", "testing"],
            learnMoreURL: nil
        ),
        ProjectHealthRule(
            id: "swift_ci",
            title: L10n(vi: "CI/CD cho Swift", en: "CI/CD for Swift"),
            description: L10n(vi: "Pipeline tự động đã cấu hình", en: "Automated pipeline configured"),
            missingDescription: L10n(
                vi: "Chưa có CI/CD — Xcode Cloud giúp deploy TestFlight tự động",
                en: "No CI/CD detected — Xcode Cloud automates TestFlight builds"
            ),
            appliesTo: [.swiftUI, .uiKit],
            detectPatterns: [".github/workflows", "xcode-cloud", "fastlane", "Fastfile", ".gitlab-ci"],
            detectBriefKeywords: ["ci/cd", "xcode cloud", "fastlane", "github actions"],
            learnMoreURL: "https://developer.apple.com/xcode-cloud/"
        ),
        ProjectHealthRule(
            id: "accessibility",
            title: L10n(vi: "Accessibility", en: "Accessibility"),
            description: L10n(vi: "Đã cân nhắc hỗ trợ VoiceOver", en: "VoiceOver support considered"),
            missingDescription: L10n(
                vi: "Thêm accessibilityLabel cho các view SwiftUI quan trọng",
                en: "Add accessibilityLabel to key SwiftUI views"
            ),
            appliesTo: [.swiftUI, .uiKit, .mobile],
            detectPatterns: ["accessibilityLabel", "accessibility", "a11y"],
            detectBriefKeywords: ["accessibility", "voiceover", "a11y"],
            learnMoreURL: "https://developer.apple.com/design/human-interface-guidelines/accessibility"
        ),
        ProjectHealthRule(
            id: "firebase_rules",
            title: L10n(vi: "Firebase Security Rules", en: "Firebase Security Rules"),
            description: L10n(vi: "Đã cấu hình quy tắc bảo mật", en: "Security rules configured"),
            missingDescription: L10n(
                vi: "Kiểm tra security rules — mặc định Firestore cho phép tất cả",
                en: "Review security rules — Firestore defaults allow everything"
            ),
            appliesTo: [.firebase],
            detectPatterns: ["firestore.rules", "firebase.json", "security-rules"],
            detectBriefKeywords: ["security rules", "firestore rules"],
            learnMoreURL: "https://firebase.google.com/docs/firestore/security/get-started"
        ),

        // ── Web Frontend ─────────────────────────────────────────────
        ProjectHealthRule(
            id: "frontend_tests",
            title: L10n(vi: "Test frontend", en: "Frontend tests"),
            description: L10n(vi: "Framework test đã cấu hình", en: "Test framework configured"),
            missingDescription: L10n(
                vi: "Thêm Jest hoặc Vitest để test component",
                en: "Add Jest or Vitest for component testing"
            ),
            appliesTo: [.react, .vue, .angular],
            detectPatterns: ["jest.config", "vitest.config", ".test.", ".spec.", "testing-library"],
            detectBriefKeywords: ["jest", "vitest", "testing-library", "cypress"],
            learnMoreURL: "https://testing-library.com/docs/guiding-principles"
        ),
        ProjectHealthRule(
            id: "linting",
            title: L10n(vi: "Linter / Formatter", en: "Linter / Formatter"),
            description: L10n(vi: "ESLint hoặc Prettier đã cấu hình", en: "ESLint or Prettier configured"),
            missingDescription: L10n(
                vi: "Thêm ESLint + Prettier để giữ code nhất quán",
                en: "Add ESLint + Prettier for consistent code style"
            ),
            appliesTo: [.react, .vue, .angular, .nodeBackend],
            detectPatterns: [".eslintrc", "eslint.config", ".prettierrc", "prettier.config", "biome.json"],
            detectBriefKeywords: ["eslint", "prettier", "biome", "linting"],
            learnMoreURL: nil
        ),
        ProjectHealthRule(
            id: "typescript",
            title: L10n(vi: "TypeScript", en: "TypeScript"),
            description: L10n(vi: "Type safety đã bật", en: "Type safety enabled"),
            missingDescription: L10n(
                vi: "Cân nhắc dùng TypeScript — bắt lỗi sớm hơn, IDE hỗ trợ tốt hơn",
                en: "Consider TypeScript — catch bugs earlier, better IDE support"
            ),
            appliesTo: [.react, .vue, .nodeBackend],
            detectPatterns: ["tsconfig.json", ".ts", ".tsx"],
            detectBriefKeywords: ["typescript"],
            learnMoreURL: nil
        ),

        // ── Backend ──────────────────────────────────────────────────
        ProjectHealthRule(
            id: "api_docs",
            title: L10n(vi: "Tài liệu API", en: "API documentation"),
            description: L10n(vi: "OpenAPI hoặc GraphQL schema có sẵn", en: "OpenAPI or GraphQL schema found"),
            missingDescription: L10n(
                vi: "Thêm OpenAPI spec hoặc GraphQL schema cho tài liệu API",
                en: "Add OpenAPI spec or GraphQL schema for API documentation"
            ),
            appliesTo: [.api, .nodeBackend, .goLang, .python],
            detectPatterns: ["openapi", "swagger", "schema.graphql", "api-docs"],
            detectBriefKeywords: ["openapi", "swagger", "graphql schema", "api doc"],
            learnMoreURL: "https://swagger.io/specification/"
        ),
        ProjectHealthRule(
            id: "backend_tests",
            title: L10n(vi: "Test backend", en: "Backend tests"),
            description: L10n(vi: "Framework test đã cấu hình", en: "Test framework configured"),
            missingDescription: L10n(
                vi: "Thêm test cho API endpoint — tránh regression khi refactor",
                en: "Add API endpoint tests — prevent regressions during refactoring"
            ),
            appliesTo: [.nodeBackend, .goLang, .python],
            detectPatterns: ["jest.config", "pytest", "go test", "_test.go", ".test.", ".spec.", "mocha"],
            detectBriefKeywords: ["jest", "pytest", "mocha", "test"],
            learnMoreURL: nil
        ),

        // ── Infrastructure ───────────────────────────────────────────
        ProjectHealthRule(
            id: "docker",
            title: L10n(vi: "Container hóa", en: "Containerization"),
            description: L10n(vi: "Dockerfile đã tìm thấy", en: "Dockerfile found"),
            missingDescription: L10n(
                vi: "Thêm Dockerfile để đóng gói và deploy nhất quán",
                en: "Add a Dockerfile for consistent packaging and deployment"
            ),
            appliesTo: [.nodeBackend, .goLang, .python],
            detectPatterns: ["Dockerfile", "docker-compose", "docker"],
            detectBriefKeywords: ["docker", "container"],
            learnMoreURL: "https://docs.docker.com/get-started/"
        ),
        ProjectHealthRule(
            id: "ci_pipeline",
            title: L10n(vi: "CI/CD pipeline", en: "CI/CD pipeline"),
            description: L10n(vi: "Pipeline tự động đã cấu hình", en: "Automated pipeline configured"),
            missingDescription: L10n(
                vi: "Thêm GitHub Actions hoặc GitLab CI để tự động test và deploy",
                en: "Add GitHub Actions or GitLab CI for automated test and deploy"
            ),
            appliesTo: [.nodeBackend, .goLang, .python, .react, .vue, .angular],
            detectPatterns: [".github/workflows", ".gitlab-ci", "Jenkinsfile", "circleci"],
            detectBriefKeywords: ["ci/cd", "github actions", "gitlab ci", "jenkins"],
            learnMoreURL: "https://docs.github.com/en/actions/learn-github-actions"
        ),
        ProjectHealthRule(
            id: "env_management",
            title: L10n(vi: "Quản lý biến môi trường", en: "Environment management"),
            description: L10n(vi: ".env.example hoặc config pattern có sẵn", en: ".env.example or config pattern found"),
            missingDescription: L10n(
                vi: "Thêm .env.example để đồng đội biết cần config gì",
                en: "Add .env.example so teammates know what config is needed"
            ),
            appliesTo: [.nodeBackend, .react, .vue, .python],
            detectPatterns: [".env.example", ".env.sample", "config.yaml", "config.toml"],
            detectBriefKeywords: [".env", "environment variable", "config"],
            learnMoreURL: nil
        ),

        // ── Database ─────────────────────────────────────────────────
        ProjectHealthRule(
            id: "db_migrations",
            title: L10n(vi: "Database migration", en: "Database migrations"),
            description: L10n(vi: "Migration framework đã cấu hình", en: "Migration framework configured"),
            missingDescription: L10n(
                vi: "Dùng migration để quản lý schema thay đổi — tránh sửa DB trực tiếp",
                en: "Use migrations to manage schema changes — avoid manual DB edits"
            ),
            appliesTo: [.database],
            detectPatterns: ["migrations", "prisma", "knex", "sequelize", "alembic", "flyway"],
            detectBriefKeywords: ["migration", "prisma", "knex", "alembic"],
            learnMoreURL: nil
        ),

        // ── Business ─────────────────────────────────────────────────
        // These leave little/no filesystem trace, so most are self-attested:
        // the pet asks, the user confirms. A few (monetization) also auto-detect
        // from brief keywords. Universal (appliesTo: []) — every project that
        // wants to make money needs them, regardless of stack.
        ProjectHealthRule(
            id: "biz_problem_validated",
            title: L10n(vi: "Đã kiểm chứng vấn đề", en: "Problem validated"),
            description: L10n(vi: "Đã nói chuyện với người dùng tiềm năng", en: "Talked to potential users"),
            missingDescription: L10n(
                vi: "Nói chuyện với 5+ người dùng tiềm năng trước khi xây nhiều — xác nhận vấn đề có thật",
                en: "Talk to 5+ potential users before building more — confirm the problem is real"
            ),
            pillar: .business,
            relevantFrom: .idea,
            evaluation: .selfAttested,
            appliesTo: [],
            detectPatterns: [],
            detectBriefKeywords: [],
            learnMoreURL: "http://momtestbook.com/"
        ),
        ProjectHealthRule(
            id: "biz_target_user",
            title: L10n(vi: "Đã xác định người dùng mục tiêu", en: "Target user defined"),
            description: L10n(vi: "Biết rõ sản phẩm dành cho ai", en: "You know who this is for"),
            missingDescription: L10n(
                vi: "Viết rõ ai là người dùng mục tiêu — càng cụ thể, marketing càng dễ",
                en: "Write down exactly who your target user is — the narrower, the easier to market"
            ),
            pillar: .business,
            relevantFrom: .idea,
            evaluation: .selfAttested,
            appliesTo: [],
            detectPatterns: [],
            detectBriefKeywords: [],
            learnMoreURL: nil
        ),
        ProjectHealthRule(
            id: "biz_value_prop",
            title: L10n(vi: "Tuyên bố giá trị một câu", en: "One-sentence value prop"),
            description: L10n(vi: "Giải thích được giá trị trong một câu", en: "You can state the value in one sentence"),
            missingDescription: L10n(
                vi: "Tóm tắt sản phẩm trong một câu: dành cho ai, giải quyết gì, khác biệt thế nào",
                en: "Sum up the product in one sentence: for whom, what it solves, why it's different"
            ),
            pillar: .business,
            relevantFrom: .building,
            evaluation: .selfAttested,
            appliesTo: [],
            detectPatterns: [],
            detectBriefKeywords: [],
            learnMoreURL: "https://www.obviouslyawesome.com/"
        ),
        ProjectHealthRule(
            id: "biz_pricing_model",
            title: L10n(vi: "Mô hình giá", en: "Pricing model decided"),
            description: L10n(vi: "Đã chọn cách kiếm tiền", en: "You've chosen how it makes money"),
            missingDescription: L10n(
                vi: "Quyết định mô hình giá: miễn phí, freemium, thuê bao, hay trả một lần",
                en: "Decide your pricing model: free, freemium, subscription, or one-time"
            ),
            pillar: .business,
            relevantFrom: .building,
            evaluation: .selfAttested,
            appliesTo: [],
            detectPatterns: [],
            detectBriefKeywords: [],
            learnMoreURL: nil
        ),
        ProjectHealthRule(
            id: "biz_monetization_wired",
            title: L10n(vi: "Đã tích hợp thanh toán", en: "Monetization wired"),
            description: L10n(vi: "Cổng thanh toán đã được tích hợp", en: "A payment path is integrated"),
            missingDescription: L10n(
                vi: "Tích hợp thanh toán (StoreKit, RevenueCat, Stripe…) để bắt đầu thu tiền",
                en: "Wire up payments (StoreKit, RevenueCat, Stripe…) so you can actually collect revenue"
            ),
            pillar: .business,
            relevantFrom: .launch,
            evaluation: .auto,
            appliesTo: [],
            detectPatterns: ["storekit", "revenuecat", "stripe", "paddle", "lemonsqueezy", "in-app purchase"],
            detectBriefKeywords: ["stripe", "revenuecat", "storekit", "in-app purchase", "iap", "subscription", "paddle", "lemonsqueezy"],
            learnMoreURL: nil
        ),
        ProjectHealthRule(
            id: "biz_legal",
            title: L10n(vi: "Chính sách & điều khoản", en: "Privacy policy & terms"),
            description: L10n(vi: "Đã có chính sách bảo mật và điều khoản", en: "Privacy policy and terms in place"),
            missingDescription: L10n(
                vi: "App Store và cổng thanh toán đều yêu cầu chính sách bảo mật + điều khoản",
                en: "Both the App Store and payment processors require a privacy policy + terms"
            ),
            pillar: .business,
            relevantFrom: .launch,
            evaluation: .auto,
            appliesTo: [],
            detectPatterns: ["privacy", "terms", "privacy-policy", "tos"],
            detectBriefKeywords: ["privacy policy", "terms of service", "terms"],
            learnMoreURL: nil
        ),
        ProjectHealthRule(
            id: "biz_revenue_tracked",
            title: L10n(vi: "Theo dõi doanh thu", en: "Revenue tracked"),
            description: L10n(vi: "Đang theo dõi doanh thu / MRR", en: "You track revenue / MRR"),
            missingDescription: L10n(
                vi: "Theo dõi doanh thu và MRR — bạn không thể cải thiện thứ mình không đo",
                en: "Track revenue and MRR — you can't improve what you don't measure"
            ),
            pillar: .business,
            relevantFrom: .growth,
            evaluation: .selfAttested,
            appliesTo: [],
            detectPatterns: [],
            detectBriefKeywords: [],
            learnMoreURL: nil
        ),

        // ── Growth / Marketing ───────────────────────────────────────
        ProjectHealthRule(
            id: "growth_landing_page",
            title: L10n(vi: "Landing page / waitlist", en: "Landing page / waitlist"),
            description: L10n(vi: "Đã có trang giới thiệu hoặc thu email", en: "A landing page or email capture exists"),
            missingDescription: L10n(
                vi: "Dựng landing page với thu email — bắt đầu gom người quan tâm từ sớm",
                en: "Stand up a landing page with email capture — start collecting interest early"
            ),
            pillar: .growth,
            relevantFrom: .idea,
            evaluation: .auto,
            appliesTo: [],
            detectPatterns: ["landing", "waitlist", "mailchimp", "convertkit", "resend"],
            detectBriefKeywords: ["landing page", "waitlist", "mailchimp", "convertkit", "email capture"],
            learnMoreURL: nil
        ),
        ProjectHealthRule(
            id: "growth_analytics",
            title: L10n(vi: "Đã cài analytics", en: "Analytics installed"),
            description: L10n(vi: "Đang đo hành vi người dùng", en: "You measure user behavior"),
            missingDescription: L10n(
                vi: "Cài analytics (PostHog, Mixpanel, Plausible…) — biết người dùng thực sự làm gì",
                en: "Install analytics (PostHog, Mixpanel, Plausible…) — learn what users actually do"
            ),
            pillar: .growth,
            relevantFrom: .building,
            evaluation: .auto,
            appliesTo: [],
            detectPatterns: ["posthog", "mixpanel", "plausible", "analytics", "amplitude", "google-analytics", "gtag"],
            detectBriefKeywords: ["posthog", "mixpanel", "plausible", "analytics", "amplitude"],
            learnMoreURL: nil
        ),
        ProjectHealthRule(
            id: "growth_audience_channel",
            title: L10n(vi: "Kênh tiếp cận khán giả", en: "Audience channel chosen"),
            description: L10n(vi: "Đang xây khán giả ở một kênh", en: "You're building an audience somewhere"),
            missingDescription: L10n(
                vi: "Chọn một kênh (X, LinkedIn, TikTok, cộng đồng…) và build-in-public từ sớm",
                en: "Pick one channel (X, LinkedIn, TikTok, a community…) and build in public early"
            ),
            pillar: .growth,
            relevantFrom: .building,
            evaluation: .selfAttested,
            appliesTo: [],
            detectPatterns: [],
            detectBriefKeywords: [],
            learnMoreURL: nil
        ),
        ProjectHealthRule(
            id: "growth_seo_basics",
            title: L10n(vi: "SEO cơ bản", en: "SEO basics"),
            description: L10n(vi: "Sitemap / robots / thẻ OG đã có", en: "Sitemap / robots / OG tags present"),
            missingDescription: L10n(
                vi: "Thêm sitemap.xml, robots.txt và thẻ Open Graph để được tìm thấy và chia sẻ đẹp",
                en: "Add sitemap.xml, robots.txt and Open Graph tags so you're findable and share nicely"
            ),
            pillar: .growth,
            relevantFrom: .launch,
            evaluation: .auto,
            appliesTo: [.react, .vue, .angular, .nodeBackend, .python],
            detectPatterns: ["sitemap", "robots.txt", "og:", "opengraph", "open-graph"],
            detectBriefKeywords: ["seo", "sitemap", "open graph", "meta tags"],
            learnMoreURL: nil
        ),
        ProjectHealthRule(
            id: "growth_launch_channels",
            title: L10n(vi: "Kế hoạch kênh ra mắt", en: "Launch channels planned"),
            description: L10n(vi: "Đã chọn nơi ra mắt", en: "You've picked where to launch"),
            missingDescription: L10n(
                vi: "Lên kế hoạch ra mắt: Product Hunt, Hacker News, subreddit, cộng đồng liên quan",
                en: "Plan your launch: Product Hunt, Hacker News, relevant subreddits and communities"
            ),
            pillar: .growth,
            relevantFrom: .launch,
            evaluation: .selfAttested,
            appliesTo: [],
            detectPatterns: [],
            detectBriefKeywords: [],
            learnMoreURL: nil
        ),
        ProjectHealthRule(
            id: "growth_retention_loop",
            title: L10n(vi: "Vòng lặp giữ chân / lan truyền", en: "Retention / sharing loop"),
            description: L10n(vi: "Có cơ chế kéo người dùng quay lại", en: "Something brings users back"),
            missingDescription: L10n(
                vi: "Xây một vòng lặp giữ chân: email vòng đời, thông báo, hoặc cơ chế chia sẻ/giới thiệu",
                en: "Build a retention loop: lifecycle email, notifications, or a sharing/referral mechanic"
            ),
            pillar: .growth,
            relevantFrom: .growth,
            evaluation: .selfAttested,
            appliesTo: [],
            detectPatterns: [],
            detectBriefKeywords: [],
            learnMoreURL: nil
        ),

        // ── Marketing ────────────────────────────────────────────────
        // How the product is positioned and promoted: name, message, content,
        // proof, and launch assets. Distinct from Growth (analytics, retention,
        // channels). Mostly self-attested — these leave no detectable trace.
        ProjectHealthRule(
            id: "mkt_name_tagline",
            title: L10n(vi: "Tên & tagline", en: "Name & tagline"),
            description: L10n(vi: "Đã có tên và một câu mô tả ngắn", en: "You have a name and a one-line hook"),
            missingDescription: L10n(
                vi: "Đặt tên sản phẩm và viết một câu hook: bạn giúp ai làm được gì",
                en: "Name the product and write a one-line hook: who you help and what they get"
            ),
            pillar: .marketing,
            relevantFrom: .idea,
            evaluation: .selfAttested,
            appliesTo: [],
            detectPatterns: [],
            detectBriefKeywords: [],
            learnMoreURL: nil
        ),
        ProjectHealthRule(
            id: "mkt_brand_basics",
            title: L10n(vi: "Nhận diện cơ bản", en: "Brand basics"),
            description: L10n(vi: "Tên, logo, và phong cách nhất quán", en: "Consistent name, logo, and look"),
            missingDescription: L10n(
                vi: "Thống nhất tên, logo và màu sắc trên trang web và các bài đăng",
                en: "Make your name, logo, and colors consistent across your site and posts"
            ),
            pillar: .marketing,
            relevantFrom: .building,
            evaluation: .selfAttested,
            appliesTo: [],
            detectPatterns: [],
            detectBriefKeywords: [],
            learnMoreURL: nil
        ),
        ProjectHealthRule(
            id: "mkt_launch_assets",
            title: L10n(vi: "Tài sản ra mắt", en: "Launch assets ready"),
            description: L10n(vi: "Video demo, ảnh chụp, và nội dung ra mắt", en: "Demo video, screenshots, and launch copy"),
            missingDescription: L10n(
                vi: "Chuẩn bị video demo, ảnh chụp màn hình và nội dung cho ngày ra mắt",
                en: "Prepare a demo video, screenshots, and copy for launch day"
            ),
            pillar: .marketing,
            relevantFrom: .launch,
            evaluation: .selfAttested,
            appliesTo: [],
            detectPatterns: [],
            detectBriefKeywords: [],
            learnMoreURL: nil
        ),
        ProjectHealthRule(
            id: "mkt_content",
            title: L10n(vi: "Tiếp thị nội dung", en: "Content marketing"),
            description: L10n(vi: "Đang đăng nội dung thu hút khán giả", en: "You publish content that attracts your audience"),
            missingDescription: L10n(
                vi: "Đăng nội dung (bài viết, video ngắn) thu hút đúng người một cách tự nhiên",
                en: "Publish content (posts, short videos) that pulls in the right people organically"
            ),
            pillar: .marketing,
            relevantFrom: .launch,
            evaluation: .selfAttested,
            appliesTo: [],
            detectPatterns: [],
            detectBriefKeywords: [],
            learnMoreURL: nil
        ),
        ProjectHealthRule(
            id: "mkt_social_proof",
            title: L10n(vi: "Bằng chứng xã hội", en: "Social proof"),
            description: L10n(vi: "Có lời chứng thực / đánh giá từ người dùng", en: "You have testimonials or reviews"),
            missingDescription: L10n(
                vi: "Thu thập lời chứng thực, đánh giá hoặc trích dẫn từ người dùng để tạo niềm tin",
                en: "Collect testimonials, reviews, or user quotes to build trust"
            ),
            pillar: .marketing,
            relevantFrom: .growth,
            evaluation: .selfAttested,
            appliesTo: [],
            detectPatterns: [],
            detectBriefKeywords: [],
            learnMoreURL: nil
        ),
    ]

    // ─── Stage Inference ─────────────────────────────────────────────

    /// Resolve a project's stage: an explicit user choice wins; otherwise infer
    /// from signals in the path + brief.
    static func inferStage(for project: Project, tags: Set<ProjectTag>) -> ProjectStage {
        if let explicit = project.stage { return explicit }

        let haystack = (project.id + " " + project.brief).lowercased()

        // Monetization or live-launch signals → at least Launch.
        let launchSignals = [
            "stripe", "revenuecat", "storekit", "paddle", "lemonsqueezy", "in-app purchase",
            "analytics", "posthog", "mixpanel", "plausible", "sitemap",
            "launched", "app store", "testflight", "production",
        ]
        if launchSignals.contains(where: { haystack.contains($0) }) { return .launch }

        // Any detected tech stack or a written brief → actively Building.
        if !tags.isEmpty || !project.brief.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return .building
        }

        return .idea
    }

    // ─── Evaluation ──────────────────────────────────────────────────

    /// Evaluate all applicable health rules for a project.
    ///
    /// `scan` is an optional file-scan result (`ProjectScanner`). When provided,
    /// auto-detect rules also match their patterns/keywords against the project's
    /// actual file contents — so a payment SDK or analytics dependency is found
    /// even when the user never mentioned it in the brief. When `nil`, detection
    /// falls back to path + brief only (no file I/O).
    static func evaluate(project: Project, scan: ProjectScanResult? = nil) -> ProjectHealthReport {
        let tags = ProjectSignals.inferTags(from: project.id, brief: project.brief)
        let stage = inferStage(for: project, tags: tags)

        // Filter rules to those that apply to this project's tags
        let applicable = allRules.filter { rule in
            if rule.appliesTo.isEmpty { return true }  // universal
            return !Set(rule.appliesTo).intersection(tags).isEmpty
        }

        var relevant: [ProjectHealthResult] = []
        var upcoming: [ProjectHealthResult] = []

        for rule in applicable {
            if rule.relevantFrom.order > stage.order {
                upcoming.append(ProjectHealthResult(rule: rule, state: .notYetRelevant))
            } else {
                let state = evaluateState(rule, project: project, scan: scan)
                relevant.append(ProjectHealthResult(rule: rule, state: state))
            }
        }

        // Relevant: missing first, then by pillar order (engineering→business→growth).
        let sortedRelevant = relevant.sorted { a, b in
            if a.passed != b.passed { return !a.passed && b.passed }
            return a.rule.pillar.order < b.rule.pillar.order
        }

        // Upcoming: by stage, then pillar — reads as a forward-looking roadmap.
        let sortedUpcoming = upcoming.sorted { a, b in
            if a.rule.relevantFrom.order != b.rule.relevantFrom.order {
                return a.rule.relevantFrom.order < b.rule.relevantFrom.order
            }
            return a.rule.pillar.order < b.rule.pillar.order
        }

        return ProjectHealthReport(
            projectName: project.displayName,
            projectPath: project.id,
            stage: stage,
            inferredTags: tags,
            results: sortedRelevant,
            upcoming: sortedUpcoming
        )
    }

    /// Evaluate all projects and return reports sorted by most recent.
    static func evaluateAll(projects: [String: Project]) -> [ProjectHealthReport] {
        let sorted = projects.values.sorted { $0.lastSeenAt > $1.lastSeenAt }
        return sorted.map { evaluate(project: $0) }
    }

    private static func evaluateState(_ rule: ProjectHealthRule, project: Project, scan: ProjectScanResult?) -> HealthState {
        // User confirmation always satisfies a rule, regardless of detection.
        if project.attestations.contains(rule.id) { return .attested }

        // Self-attested rules have no detectable trace — only attestation passes.
        if rule.evaluation == .selfAttested { return .missing }

        // Special case: brief_written checks if the brief is non-empty
        if rule.id == "brief_written" {
            let nonEmpty = !project.brief.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            return nonEmpty ? .passed : .missing
        }

        let pathLower = project.id.lowercased()
        let briefLower = project.brief.lowercased()
        let fileHaystack = scan?.haystack  // already lowercased

        // Patterns/keywords match against the path, the brief, AND (when scanned)
        // the project's file contents. Scan matches only ever flip missing→passed.
        for pattern in rule.detectPatterns {
            let p = pattern.lowercased()
            if pathLower.contains(p) || (fileHaystack?.contains(p) ?? false) { return .passed }
        }
        for keyword in rule.detectBriefKeywords {
            let k = keyword.lowercased()
            if briefLower.contains(k) || (fileHaystack?.contains(k) ?? false) { return .passed }
        }

        return .missing
    }
}

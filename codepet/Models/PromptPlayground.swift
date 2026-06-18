import SwiftUI

// MARK: - Prompt Playground Models

/// A scenario the user must solve by writing a prompt
struct PlaygroundScenario: Identifiable, Equatable {
    let id: String
    let title: String
    let difficulty: PlaygroundDifficulty
    let context: String           // What the user is trying to build
    let mission: String           // Specific task description
    let targetAudience: String    // Who the prompt is for (Claude, Cursor, etc.)
    let hints: [String]           // Progressive hints
    let exampleOutput: String     // What a good prompt might produce
    let requiredElements: [PromptElement]  // What the prompt must contain
    let bonusElements: [PromptElement]     // Extra credit
    let xpReward: Int
    let teacher: String           // Character ID
    let skillId: String           // Related skill

    static func == (lhs: PlaygroundScenario, rhs: PlaygroundScenario) -> Bool {
        lhs.id == rhs.id
    }
}

enum PlaygroundDifficulty: String {
    case beginner = "Beginner"
    case intermediate = "Intermediate"
    case advanced = "Advanced"
    case expert = "Expert"

    var color: Color {
        switch self {
        case .beginner: return Color(hex: "#6BCB77")
        case .intermediate: return Color(hex: "#D4960A")
        case .advanced: return Color(hex: "#7B8CE0")
        case .expert: return Color(hex: "#E04040")
        }
    }

    var xpMultiplier: Double {
        switch self {
        case .beginner: return 1.0
        case .intermediate: return 1.5
        case .advanced: return 2.0
        case .expert: return 3.0
        }
    }
}

/// An element the analyzer looks for in the user's prompt
struct PromptElement: Identifiable, Equatable {
    let id: String
    let name: String
    let description: String
    let icon: String
    let patterns: [String]     // Regex/keyword patterns to detect
    let weight: Double         // How important (0-1)

    static func == (lhs: PromptElement, rhs: PromptElement) -> Bool {
        lhs.id == rhs.id
    }
}

/// Result of analyzing a prompt
struct PromptAnalysis {
    let scores: [String: Double]       // elementId -> score (0-1)
    let overallScore: Int              // 0-100
    let feedback: [PromptFeedback]     // Specific feedback items
    let grade: PromptGrade
    let strengths: [String]
    let improvements: [String]
}

struct PromptFeedback: Identifiable {
    let id = UUID()
    let element: String
    let passed: Bool
    let message: String
}

enum PromptGrade: String {
    case s = "S"
    case a = "A"
    case b = "B"
    case c = "C"
    case d = "D"
    case f = "F"

    var color: Color {
        switch self {
        case .s: return Color(hex: "#D4960A")
        case .a: return Color(hex: "#6BCB77")
        case .b: return Color(hex: "#7B8CE0")
        case .c: return Color(hex: "#D89840")
        case .d: return Color(hex: "#E06050")
        case .f: return Color(hex: "#E04040")
        }
    }

    var label: String {
        switch self {
        case .s: return "Master Crafter"
        case .a: return "Skilled Builder"
        case .b: return "Getting There"
        case .c: return "Room to Grow"
        case .d: return "Keep Practicing"
        case .f: return "Try Again"
        }
    }
}

// MARK: - Prompt Analyzer

struct PromptAnalyzer {

    /// Analyze a user's prompt against a scenario's required/bonus elements
    static func analyze(prompt: String, scenario: PlaygroundScenario) -> PromptAnalysis {
        let text = prompt.lowercased()
        let wordCount = prompt.split(separator: " ").count
        var scores: [String: Double] = [:]
        var feedback: [PromptFeedback] = []
        var strengths: [String] = []
        var improvements: [String] = []

        // Check required elements
        for element in scenario.requiredElements {
            let score = scoreElement(text: text, wordCount: wordCount, element: element)
            scores[element.id] = score

            if score >= 0.6 {
                feedback.append(PromptFeedback(element: element.name, passed: true, message: "Good \(element.name.lowercased())!"))
                strengths.append(element.name)
            } else {
                feedback.append(PromptFeedback(element: element.name, passed: false, message: element.description))
                improvements.append("Add more \(element.name.lowercased())")
            }
        }

        // Check bonus elements
        for element in scenario.bonusElements {
            let score = scoreElement(text: text, wordCount: wordCount, element: element)
            scores[element.id] = score
            if score >= 0.6 {
                strengths.append("\(element.name) (bonus!)")
            }
        }

        // Structural analysis
        let structureScore = analyzeStructure(text: text, wordCount: wordCount)
        scores["structure"] = structureScore

        // Calculate overall
        let allElements = scenario.requiredElements + scenario.bonusElements
        let totalWeight = allElements.reduce(0.0) { $0 + $1.weight } + 0.15 // +0.15 for structure
        let weightedSum = allElements.reduce(0.0) { total, el in
            total + (scores[el.id] ?? 0) * el.weight
        } + structureScore * 0.15

        let overall = Int(min(100, (weightedSum / max(0.01, totalWeight)) * 100))

        let grade: PromptGrade
        switch overall {
        case 90...100: grade = .s
        case 80..<90: grade = .a
        case 70..<80: grade = .b
        case 55..<70: grade = .c
        case 40..<55: grade = .d
        default: grade = .f
        }

        return PromptAnalysis(
            scores: scores,
            overallScore: overall,
            feedback: feedback,
            grade: grade,
            strengths: strengths,
            improvements: improvements
        )
    }

    // MARK: - Element Scoring

    private static func scoreElement(text: String, wordCount: Int, element: PromptElement) -> Double {
        var score = 0.0
        var matchCount = 0

        for pattern in element.patterns {
            if let regex = try? NSRegularExpression(pattern: pattern.lowercased(), options: []) {
                let range = NSRange(text.startIndex..., in: text)
                let matches = regex.numberOfMatches(in: text, range: range)
                if matches > 0 { matchCount += 1 }
            } else {
                // Fallback to simple contains
                if text.contains(pattern.lowercased()) { matchCount += 1 }
            }
        }

        if !element.patterns.isEmpty {
            score = Double(matchCount) / Double(element.patterns.count)
        }

        // Bonus for detail (more words around the element)
        if matchCount > 0 && wordCount > 20 {
            score = min(1.0, score + 0.15)
        }

        return score
    }

    // MARK: - Structure Analysis

    private static func analyzeStructure(text: String, wordCount: Int) -> Double {
        var score = 0.0

        // Length check (at least 30 words for a decent prompt)
        if wordCount >= 15 { score += 0.15 }
        if wordCount >= 30 { score += 0.15 }
        if wordCount >= 50 { score += 0.1 }

        // Has line breaks (structured)
        if text.contains("\n") { score += 0.15 }

        // Has bullet points or numbered lists
        let listPatterns = ["- ", "• ", "* ", "1.", "2.", "3."]
        if listPatterns.contains(where: { text.contains($0) }) { score += 0.15 }

        // Has sections/headers (caps or colons)
        if text.contains(":") { score += 0.1 }

        // Has specificity markers
        let specifics = ["should", "must", "don't", "avoid", "include", "make sure", "use", "create"]
        let specificCount = specifics.filter { text.contains($0) }.count
        score += min(0.2, Double(specificCount) * 0.05)

        return min(1.0, score)
    }
}

// MARK: - Scenario Library

struct PlaygroundLibrary {
    static let scenarios: [PlaygroundScenario] = [
        // BEGINNER
        PlaygroundScenario(
            id: "pg-landing-page",
            title: "Build a Landing Page",
            difficulty: .beginner,
            context: "You're a solo founder building a SaaS product. You need a landing page.",
            mission: "Write a prompt that tells an AI to build you a complete landing page. Be specific about what you want.",
            targetAudience: "Claude or Bolt",
            hints: [
                "What does your product do?",
                "What sections should the page have?",
                "What style/colors do you want?"
            ],
            exampleOutput: "A responsive landing page with hero, features, pricing, and CTA sections",
            requiredElements: [
                PromptElement(id: "what", name: "Clear Task", description: "Tell the AI what to build", icon: "target",
                              patterns: ["build", "create", "make", "design", "landing page", "website"], weight: 0.3),
                PromptElement(id: "sections", name: "Page Sections", description: "Specify which sections you need", icon: "rectangle.3.group",
                              patterns: ["hero", "header", "features", "pricing", "footer", "cta", "testimonial", "section", "navbar"], weight: 0.3),
                PromptElement(id: "style", name: "Visual Style", description: "Describe the look and feel", icon: "paintbrush",
                              patterns: ["color", "style", "modern", "clean", "minimal", "dark", "light", "font", "design", "theme"], weight: 0.2),
            ],
            bonusElements: [
                PromptElement(id: "tech", name: "Tech Stack", description: "Specify what tech to use", icon: "wrench",
                              patterns: ["react", "next", "html", "tailwind", "css", "swift", "vue", "typescript"], weight: 0.1),
                PromptElement(id: "responsive", name: "Responsive", description: "Mention mobile/responsive design", icon: "iphone",
                              patterns: ["responsive", "mobile", "tablet", "breakpoint", "screen size"], weight: 0.1),
            ],
            xpReward: 50,
            teacher: "nova",
            skillId: "prompt-clarity"
        ),

        PlaygroundScenario(
            id: "pg-debug-error",
            title: "Debug a Crash",
            difficulty: .beginner,
            context: "Your app crashes on launch with an error. You need AI to help debug.",
            mission: "Write a prompt that gives AI everything it needs to diagnose the crash. Paste a fake error and ask for help.",
            targetAudience: "Claude or Cursor",
            hints: [
                "What error message do you see?",
                "What were you doing when it crashed?",
                "What have you already tried?"
            ],
            exampleOutput: "A clear diagnosis of the crash cause with step-by-step fix",
            requiredElements: [
                PromptElement(id: "error", name: "Error Message", description: "Include the actual error", icon: "exclamationmark.triangle",
                              patterns: ["error", "crash", "exception", "failed", "undefined", "nil", "null", "bug", "stack trace"], weight: 0.3),
                PromptElement(id: "context", name: "Context", description: "Explain what you were doing", icon: "doc.text",
                              patterns: ["when i", "after", "trying to", "working on", "running", "building", "happens when"], weight: 0.3),
                PromptElement(id: "ask", name: "Clear Ask", description: "Ask a specific question", icon: "questionmark.circle",
                              patterns: ["why", "how to fix", "what causes", "help me", "can you", "debug", "solve", "diagnose"], weight: 0.2),
            ],
            bonusElements: [
                PromptElement(id: "tried", name: "What You Tried", description: "Mention what you already attempted", icon: "arrow.counterclockwise",
                              patterns: ["tried", "attempted", "already", "didn't work", "still"], weight: 0.1),
                PromptElement(id: "code", name: "Code Snippet", description: "Include relevant code", icon: "chevron.left.forwardslash.chevron.right",
                              patterns: ["function", "class", "const ", "let ", "var ", "def ", "import", "```"], weight: 0.1),
            ],
            xpReward: 50,
            teacher: "crash",
            skillId: "error-reading"
        ),

        // INTERMEDIATE
        PlaygroundScenario(
            id: "pg-api-design",
            title: "Design a REST API",
            difficulty: .intermediate,
            context: "You're building a task management app and need AI to design the backend API.",
            mission: "Write a prompt that gets AI to design a complete REST API with endpoints, data models, and auth. Be as specific as possible.",
            targetAudience: "Claude",
            hints: [
                "What resources does your API manage?",
                "What operations (CRUD) do you need?",
                "How should authentication work?"
            ],
            exampleOutput: "Complete API spec with endpoints, request/response schemas, and auth flow",
            requiredElements: [
                PromptElement(id: "resources", name: "Resources", description: "Define what data your API manages", icon: "cylinder",
                              patterns: ["task", "user", "project", "endpoint", "resource", "model", "entity", "data"], weight: 0.25),
                PromptElement(id: "operations", name: "Operations", description: "Specify CRUD operations needed", icon: "arrow.triangle.2.circlepath",
                              patterns: ["create", "read", "update", "delete", "get", "post", "put", "patch", "list", "CRUD"], weight: 0.25),
                PromptElement(id: "auth", name: "Authentication", description: "Describe auth requirements", icon: "lock.shield",
                              patterns: ["auth", "login", "token", "jwt", "session", "permission", "role", "password", "signup"], weight: 0.2),
                PromptElement(id: "constraints", name: "Constraints", description: "Add rules or limitations", icon: "exclamationmark.shield",
                              patterns: ["don't", "avoid", "must", "should", "limit", "require", "validate", "only", "never"], weight: 0.15),
            ],
            bonusElements: [
                PromptElement(id: "errors", name: "Error Handling", description: "Mention error responses", icon: "xmark.octagon",
                              patterns: ["error", "status code", "404", "401", "500", "validation", "handle"], weight: 0.1),
                PromptElement(id: "examples", name: "Examples", description: "Include example requests/responses", icon: "text.quote",
                              patterns: ["example", "for instance", "like this", "such as", "e.g.", "sample"], weight: 0.05),
            ],
            xpReward: 80,
            teacher: "sage",
            skillId: "context-setting"
        ),

        // ADVANCED
        PlaygroundScenario(
            id: "pg-refactor",
            title: "Refactor Legacy Code",
            difficulty: .advanced,
            context: "You inherited a messy 500-line function. You need AI to help refactor it without breaking anything.",
            mission: "Write a prompt that guides AI through a safe refactor. Think about what context AI needs and what constraints to set.",
            targetAudience: "Cursor or Claude",
            hints: [
                "What does the function currently do?",
                "What patterns should the refactored code follow?",
                "What must NOT change (API contracts, behavior)?"
            ],
            exampleOutput: "Refactored code split into smaller functions with preserved behavior and tests",
            requiredElements: [
                PromptElement(id: "current", name: "Current State", description: "Describe what the code does now", icon: "doc.text.magnifyingglass",
                              patterns: ["currently", "right now", "existing", "legacy", "this function", "this code", "it does"], weight: 0.2),
                PromptElement(id: "goal", name: "Refactor Goal", description: "Say what the refactored code should look like", icon: "arrow.triangle.branch",
                              patterns: ["refactor", "split", "extract", "clean", "separate", "modular", "smaller", "readable"], weight: 0.25),
                PromptElement(id: "preserve", name: "Preserve Behavior", description: "Specify what must not break", icon: "shield.checkered",
                              patterns: ["don't break", "preserve", "keep", "same behavior", "backward", "compatible", "must still", "api"], weight: 0.25),
                PromptElement(id: "patterns", name: "Code Patterns", description: "Specify patterns to follow", icon: "square.grid.3x3",
                              patterns: ["pattern", "convention", "naming", "single responsibility", "dry", "solid", "clean code", "style"], weight: 0.15),
            ],
            bonusElements: [
                PromptElement(id: "tests", name: "Testing", description: "Mention tests", icon: "checkmark.seal",
                              patterns: ["test", "spec", "assert", "verify", "coverage", "unit test"], weight: 0.1),
                PromptElement(id: "steps", name: "Step-by-Step", description: "Ask for incremental approach", icon: "list.number",
                              patterns: ["step by step", "first", "then", "incrementally", "one at a time", "phase"], weight: 0.05),
            ],
            xpReward: 120,
            teacher: "sage",
            skillId: "scope-mgmt"
        ),

        // EXPERT
        PlaygroundScenario(
            id: "pg-architecture",
            title: "Architect a Full App",
            difficulty: .expert,
            context: "You're starting a new SaaS product from scratch. You need AI to help plan the entire architecture.",
            mission: "Write a mega-prompt that gives AI enough context to design a complete app architecture. This is the hardest challenge — think about everything.",
            targetAudience: "Claude",
            hints: [
                "What problem does the app solve?",
                "Who are the users?",
                "What's the tech stack, infrastructure, and deployment?",
                "What are the key features and data flows?"
            ],
            exampleOutput: "Complete architecture document with tech stack, data models, API design, deployment, and feature roadmap",
            requiredElements: [
                PromptElement(id: "problem", name: "Problem Statement", description: "Define what problem you're solving", icon: "lightbulb",
                              patterns: ["problem", "solve", "need", "pain point", "users want", "goal", "purpose", "mission"], weight: 0.15),
                PromptElement(id: "users", name: "Target Users", description: "Describe who uses this", icon: "person.2",
                              patterns: ["user", "customer", "audience", "persona", "who", "developer", "team", "people"], weight: 0.15),
                PromptElement(id: "stack", name: "Tech Stack", description: "Specify technologies", icon: "cpu",
                              patterns: ["react", "node", "python", "swift", "database", "postgres", "mongo", "redis", "aws", "tech stack", "framework"], weight: 0.15),
                PromptElement(id: "features", name: "Core Features", description: "List key features", icon: "star",
                              patterns: ["feature", "login", "dashboard", "notification", "search", "upload", "payment", "profile", "settings"], weight: 0.2),
                PromptElement(id: "data", name: "Data Model", description: "Describe data relationships", icon: "cylinder.split.1x2",
                              patterns: ["model", "schema", "table", "relation", "field", "entity", "database", "store", "data"], weight: 0.15),
                PromptElement(id: "scale", name: "Scale & Deploy", description: "Mention deployment and scaling", icon: "cloud",
                              patterns: ["deploy", "scale", "cloud", "docker", "ci/cd", "hosting", "production", "server", "infrastructure"], weight: 0.1),
            ],
            bonusElements: [
                PromptElement(id: "security", name: "Security", description: "Address security concerns", icon: "lock.shield",
                              patterns: ["security", "encrypt", "auth", "permission", "rate limit", "injection", "xss", "csrf"], weight: 0.05),
                PromptElement(id: "roadmap", name: "Roadmap", description: "Include phased approach", icon: "map",
                              patterns: ["phase", "mvp", "v1", "roadmap", "milestone", "sprint", "iteration", "priority"], weight: 0.05),
            ],
            xpReward: 200,
            teacher: "glitch",
            skillId: "architecture"
        ),
    ]

    static func forSkill(_ skillId: String) -> [PlaygroundScenario] {
        scenarios.filter { $0.skillId == skillId }
    }

    static func forDifficulty(_ difficulty: PlaygroundDifficulty) -> [PlaygroundScenario] {
        scenarios.filter { $0.difficulty == difficulty }
    }
}

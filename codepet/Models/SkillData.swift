import SwiftUI

struct SkillTier: Identifiable {
    let id: Int
    let name: String
    let kingdom: String
    let kingdomColor: Color
    let color: Color
    var skills: [Skill]
}

enum SkillNodeType: String {
    case lesson     // Regular lesson — 📖
    case challenge  // Mid-tier challenge — ⚡
    case boss       // Final boss of a kingdom — 💀
}

struct Skill: Identifiable, Equatable {
    let id: String
    let name: String
    let icon: String
    let desc: String
    var level: Int = 0
    let maxLevel: Int = 5
    var nodeType: SkillNodeType = .lesson
}

// MARK: - Challenge Models

struct ChallengeBadge: Equatable {
    let icon: String
    let name: String
}

struct ChallengeCheckpoint: Identifiable, Equatable {
    let id: String
    let label: String
    let keywords: [String]  // words to look for in submission
}

struct PromptBlock: Equatable {
    let emoji: String
    let title: String
    let hint: String
    let example: String
}

struct SampleAnswer: Equatable {
    let topic: String
    let text: String
}

struct ChallengeTool: Identifiable, Equatable {
    let id: String
    let name: String
    let icon: String
    let desc: String
    let color: Color
    let recommended: Bool
    let url: String?

    static let all: [ChallengeTool] = [
        ChallengeTool(id: "claude", name: "Claude", icon: "C", desc: "AI thinker — best for reasoning, planning, and debugging", color: Color(hex: "#D97706"), recommended: true, url: "https://claude.ai"),
        ChallengeTool(id: "cursor", name: "Cursor", icon: "⌨", desc: "AI code editor — best for editing existing projects", color: Color(hex: "#3B82F6"), recommended: false, url: "https://cursor.sh"),
        ChallengeTool(id: "vscode", name: "VS Code + Copilot", icon: "◇", desc: "Classic editor with AI autocomplete", color: Color(hex: "#007ACC"), recommended: false, url: nil),
        ChallengeTool(id: "bolt", name: "Bolt", icon: "⚡", desc: "AI builder — best for full apps from scratch", color: Color(hex: "#8B5CF6"), recommended: false, url: "https://bolt.new"),
        ChallengeTool(id: "v0", name: "v0", icon: "▲", desc: "AI UI generator — best for components and pages", color: Color(hex: "#000000"), recommended: false, url: "https://v0.dev"),
        ChallengeTool(id: "replit", name: "Replit", icon: "R", desc: "Browser IDE with AI — best for quick prototypes", color: Color(hex: "#F26207"), recommended: false, url: "https://replit.com"),
        ChallengeTool(id: "other", name: "Other Tool", icon: "•", desc: "Any AI coding tool you prefer", color: Color(hex: "#888888"), recommended: false, url: nil),
    ]
}

struct Challenge: Identifiable, Equatable {
    let id: String
    let skillName: String
    let teacher: String
    let xpReward: Int
    let badge: ChallengeBadge
    let brief: String
    let scenario: String
    let guidelines: [String]
    let checkpoints: [ChallengeCheckpoint]
    let promptBlocks: [PromptBlock]
    let sampleAnswer: SampleAnswer?
    let passFeedback: String
    let retryHints: [String: String]  // checkpoint id -> hint

    static func == (lhs: Challenge, rhs: Challenge) -> Bool {
        lhs.id == rhs.id
    }
}

struct DailyChallenge: Identifiable {
    let id: String
    let title: String
    let description: String
    let xpReward: Int
}

// MARK: - Character Outfits / Evolution

struct CharOutfit {
    let tier: Int
    let name: String
    let badge: String
}

let characterOutfits: [Int: CharOutfit] = [
    1: CharOutfit(tier: 1, name: "Starter", badge: "🥚"),
    2: CharOutfit(tier: 2, name: "Apprentice", badge: "🌱"),
    3: CharOutfit(tier: 3, name: "Adept", badge: "⚡"),
    4: CharOutfit(tier: 4, name: "Master", badge: "🔥"),
]

// MARK: - Static Data

struct GameData {
    static let skillTiers: [SkillTier] = [
        SkillTier(
            id: 1,
            name: "Foundations",
            kingdom: "The Molten Forge",
            kingdomColor: Color(hex: "#FF8040"),
            color: Color(hex: "#6BCB77"),
            skills: [
                Skill(id: "prompt-clarity", name: "Prompt Clarity", icon: "✏️", desc: "Learn how to tell AI exactly what you want.", nodeType: .lesson),
                Skill(id: "error-reading", name: "Error Reading", icon: "🔍", desc: "Understand what error messages are really telling you.", nodeType: .lesson),
                Skill(id: "tool-basics", name: "Tool Basics", icon: "🛠️", desc: "Know which AI tool to use for what.", nodeType: .challenge),
                Skill(id: "code-judgment", name: "Code Judgment", icon: "⚖️", desc: "Learn when to trust AI's code and when to say 'try again'.", nodeType: .boss),
            ]
        ),
        SkillTier(
            id: 2,
            name: "Context & Structure",
            kingdom: "The Frozen Spire",
            kingdomColor: Color(hex: "#88D0F0"),
            color: Color(hex: "#D89840"),
            skills: [
                Skill(id: "context-setting", name: "Context Setting", icon: "🎯", desc: "Tell AI about your project before asking it to code.", nodeType: .lesson),
                Skill(id: "rules-files", name: "AI Rules Files", icon: "📏", desc: "Create a file that tells AI your rules automatically.", nodeType: .lesson),
                Skill(id: "documentation", name: "Documentation", icon: "📄", desc: "Write docs that help both you and AI.", nodeType: .challenge),
                Skill(id: "file-structure", name: "Project Structure", icon: "📁", desc: "Organize files so AI can find the right ones.", nodeType: .boss),
            ]
        ),
        SkillTier(
            id: 3,
            name: "Advanced",
            kingdom: "The Eternal Garden",
            kingdomColor: Color(hex: "#F0A8D0"),
            color: Color(hex: "#7B8CE0"),
            skills: [
                Skill(id: "tool-switching", name: "Tool Switching", icon: "🔄", desc: "Know when to switch AI tools.", nodeType: .lesson),
                Skill(id: "scope-mgmt", name: "Scope Mgmt", icon: "📦", desc: "Break big ideas into small pieces AI can build.", nodeType: .challenge),
                Skill(id: "design-system", name: "Design System", icon: "🎨", desc: "Keep your app looking consistent.", nodeType: .lesson),
                Skill(id: "iteration", name: "Prompt Iteration", icon: "🔁", desc: "Refine prompts step by step.", nodeType: .boss),
            ]
        ),
        SkillTier(
            id: 4,
            name: "Expert",
            kingdom: "The Mystic Grove",
            kingdomColor: Color(hex: "#90D870"),
            color: Color(hex: "#C07AB8"),
            skills: [
                Skill(id: "personas", name: "User Personas", icon: "🧩", desc: "Define who you're building for.", nodeType: .lesson),
                Skill(id: "context-windows", name: "Context Windows", icon: "🧠", desc: "Understand AI's memory limits.", nodeType: .challenge),
                Skill(id: "architecture", name: "AI Architecture", icon: "🏗️", desc: "Design projects AI can help maintain.", nodeType: .lesson),
                Skill(id: "second-brain", name: "Second Brain", icon: "💡", desc: "Build a personal knowledge system.", nodeType: .boss),
            ]
        ),
    ]

    // MARK: - Full Challenge Data (6-stage flow)

    static let challenges: [Challenge] = [
        // ═══ TIER 1 ═══
        Challenge(
            id: "prompt-clarity-challenge",
            skillName: "Prompt Clarity",
            teacher: "nova",
            xpReward: 150,
            badge: ChallengeBadge(icon: "✏️", name: "Prompt Apprentice"),
            brief: "Write a clear, structured prompt for a real feature. Show that you can communicate your vision to AI.",
            scenario: "You need to ask AI to build a user profile page. Write a prompt that includes Context, Task, and Constraints.",
            guidelines: ["Include what tech stack to use", "Specify which components to create", "Add at least 2 constraints (things to avoid or include)"],
            checkpoints: [
                ChallengeCheckpoint(id: "context", label: "Includes project context", keywords: ["project", "app", "building", "stack", "react", "swift", "web"]),
                ChallengeCheckpoint(id: "task", label: "Clear task description", keywords: ["build", "create", "make", "implement", "add", "profile", "page"]),
                ChallengeCheckpoint(id: "constraints", label: "Has specific constraints", keywords: ["don't", "avoid", "must", "should", "constraint", "require", "no"]),
                ChallengeCheckpoint(id: "structure", label: "Well-structured format", keywords: ["context", "task", "constraint", "requirement", "spec", ":"]),
            ],
            promptBlocks: [
                PromptBlock(emoji: "🎯", title: "Set the Context", hint: "Tell AI what you're building and what stack you use.", example: "e.g. 'I'm building a SwiftUI macOS app for...'"),
                PromptBlock(emoji: "📝", title: "Describe the Task", hint: "Be specific about what you want built.", example: "e.g. 'Create a profile page with avatar, name, and stats'"),
                PromptBlock(emoji: "🚫", title: "Add Constraints", hint: "Tell AI what to include AND what to avoid.", example: "e.g. 'Use only system fonts. No third-party libraries.'"),
            ],
            sampleAnswer: SampleAnswer(
                topic: "Todo App",
                text: "CONTEXT:\nI'm building a React todo app with TypeScript and Tailwind.\n\nTASK:\nCreate a TodoItem component that shows the task text, due date, and a completion checkbox.\n\nCONSTRAINTS:\n- Use only Tailwind classes, no custom CSS\n- Include hover and focus states for accessibility\n- Must work on mobile (responsive)\n- Don't use any external UI library"
            ),
            passFeedback: "Great job! Your prompt was clear and well-structured. An AI would have no trouble building exactly what you described.",
            retryHints: [
                "context": "Add more about your project - what are you building? What tech stack?",
                "task": "Be more specific about what you want built. What components? What features?",
                "constraints": "Add clear constraints - what should AI include? What should it avoid?",
                "structure": "Try organizing with labels like CONTEXT:, TASK:, CONSTRAINTS:",
            ]
        ),

        Challenge(
            id: "error-reading-challenge",
            skillName: "Error Reading",
            teacher: "crash",
            xpReward: 150,
            badge: ChallengeBadge(icon: "🔍", name: "Bug Detective"),
            brief: "Diagnose an error message and explain the fix clearly.",
            scenario: "You see: TypeError: Cannot read properties of undefined (reading 'map') at UserList.jsx:12. What's happening and how do you fix it?",
            guidelines: ["Identify the error type", "Explain what's undefined", "Suggest a fix with code"],
            checkpoints: [
                ChallengeCheckpoint(id: "identify", label: "Identifies the error type", keywords: ["typeerror", "type error", "undefined", "null", "cannot read"]),
                ChallengeCheckpoint(id: "explain", label: "Explains root cause", keywords: ["undefined", "not defined", "null", "empty", "missing", "data", "array"]),
                ChallengeCheckpoint(id: "fix", label: "Suggests a concrete fix", keywords: ["optional", "check", "if", "guard", "?.", "??", "||", "default", "fallback"]),
            ],
            promptBlocks: [
                PromptBlock(emoji: "🔍", title: "Read the Error", hint: "Break down what each part of the error tells you.", example: "TypeError means you're calling a method on the wrong type"),
                PromptBlock(emoji: "🎯", title: "Find the Cause", hint: "Why is the value undefined? What should it be?", example: "The data hasn't loaded yet, so the array is undefined"),
                PromptBlock(emoji: "🛠️", title: "Write the Fix", hint: "Show a code fix that handles the edge case.", example: "Add optional chaining: data?.map(...) or a loading guard"),
            ],
            sampleAnswer: SampleAnswer(
                topic: "Different Error (ReferenceError)",
                text: "WHAT I SEE:\nReferenceError: items is not defined at Cart.jsx:8\n\nROOT CAUSE:\nThe variable 'items' was used before being declared. Likely a typo or the import is missing.\n\nFIX:\n1. Check if 'items' should be 'cartItems' (from props or state)\n2. Add: const items = props.cartItems || []\n3. This gives a fallback empty array if undefined"
            ),
            passFeedback: "Excellent diagnosis! You identified the error, explained the cause, and provided a practical fix.",
            retryHints: [
                "identify": "Start by naming the error type - it's a TypeError. What does that mean?",
                "explain": "Think about WHY .map() fails. What data type is being accessed?",
                "fix": "Show a code snippet that prevents this crash. Optional chaining? Default value?",
            ]
        ),

        Challenge(
            id: "tool-basics-challenge",
            skillName: "Tool Basics",
            teacher: "sage",
            xpReward: 150,
            badge: ChallengeBadge(icon: "🛠️", name: "Tool Scout"),
            brief: "Match tasks to the right AI tool for maximum efficiency.",
            scenario: "You have 5 tasks for your project. Choose which AI tool (Chat AI, Code AI, or Builder AI) to use for each.",
            guidelines: ["Pick the best tool for planning", "Pick the best tool for multi-file edits", "Explain why for each choice"],
            checkpoints: [
                ChallengeCheckpoint(id: "match", label: "Matches tasks to tools", keywords: ["chatgpt", "claude", "cursor", "copilot", "chat", "code", "builder", "v0"]),
                ChallengeCheckpoint(id: "reasoning", label: "Explains reasoning", keywords: ["because", "since", "better", "best", "good for", "suited", "works for"]),
                ChallengeCheckpoint(id: "planning", label: "Identifies planning tool", keywords: ["plan", "brainstorm", "design", "architect", "outline", "chat"]),
            ],
            promptBlocks: [
                PromptBlock(emoji: "📋", title: "List the Tasks", hint: "Write out 5 tasks you'd need for your project.", example: "Planning architecture, writing components, debugging, etc."),
                PromptBlock(emoji: "🔧", title: "Match Each Tool", hint: "Assign Chat AI, Code AI, or Builder AI to each task.", example: "Architecture planning -> Chat AI (Claude/ChatGPT)"),
                PromptBlock(emoji: "💡", title: "Explain Why", hint: "For each match, explain why that tool is best.", example: "Chat AI is best for planning because it handles long context"),
            ],
            sampleAnswer: nil,
            passFeedback: "You clearly understand which tools work best for different tasks. This will save you so much time!",
            retryHints: [
                "match": "Make sure to name specific tools (ChatGPT, Claude, Cursor, Copilot, v0, etc.)",
                "reasoning": "Explain WHY each tool fits - what makes it better than alternatives?",
                "planning": "Which tool is best for initial planning and brainstorming?",
            ]
        ),

        Challenge(
            id: "code-judgment-challenge",
            skillName: "Code Judgment",
            teacher: "glitch",
            xpReward: 150,
            badge: ChallengeBadge(icon: "⚖️", name: "Code Judge"),
            brief: "Review AI-generated code and spot what's missing or wrong.",
            scenario: "AI generated a function to fetch user data. Review it for bugs, missing error handling, and edge cases.",
            guidelines: ["Check for null/undefined handling", "Look for missing error handling", "Verify edge cases are covered"],
            checkpoints: [
                ChallengeCheckpoint(id: "bugs", label: "Identifies potential bugs", keywords: ["bug", "issue", "problem", "error", "wrong", "missing", "forgot", "null"]),
                ChallengeCheckpoint(id: "errorhandling", label: "Checks error handling", keywords: ["try", "catch", "error", "fail", "exception", "handle", "throw"]),
                ChallengeCheckpoint(id: "edge", label: "Considers edge cases", keywords: ["edge", "empty", "null", "undefined", "zero", "negative", "large", "timeout", "slow"]),
            ],
            promptBlocks: [
                PromptBlock(emoji: "🐛", title: "Find the Bugs", hint: "Look for obvious issues in the code.", example: "Missing null checks, wrong variable names, logic errors"),
                PromptBlock(emoji: "🛡️", title: "Check Error Handling", hint: "Is there try/catch? What if the API fails?", example: "No error handling for network timeout"),
                PromptBlock(emoji: "🧪", title: "Test Edge Cases", hint: "What happens with weird inputs?", example: "What if the user ID is null? Or the response is empty?"),
            ],
            sampleAnswer: nil,
            passFeedback: "Strong code review! You caught the important issues that could cause real problems in production.",
            retryHints: [
                "bugs": "Look more carefully - are there any null/undefined values that could cause crashes?",
                "errorhandling": "What happens if the network call fails? Is there a try/catch?",
                "edge": "Think about unusual inputs - empty arrays, null values, timeouts",
            ]
        ),

        // ═══ TIER 2 ═══
        Challenge(
            id: "context-setting-challenge",
            skillName: "Context Setting",
            teacher: "luna",
            xpReward: 30,
            badge: ChallengeBadge(icon: "🎯", name: "Context Crafter"),
            brief: "Write a full context block that gives AI everything it needs to help you.",
            scenario: "Start a new AI session for your project. Write a context block that covers Project, Stack, Current State, and Ask.",
            guidelines: ["Include your project description", "List your full tech stack", "Describe what's already built", "State your next task clearly"],
            checkpoints: [
                ChallengeCheckpoint(id: "project", label: "Describes the project", keywords: ["project", "app", "building", "creating", "making", "developing"]),
                ChallengeCheckpoint(id: "stack", label: "Lists tech stack", keywords: ["react", "swift", "python", "node", "typescript", "tailwind", "firebase", "next", "vue"]),
                ChallengeCheckpoint(id: "state", label: "Current state described", keywords: ["currently", "already", "built", "done", "existing", "so far", "have"]),
                ChallengeCheckpoint(id: "ask", label: "Clear next task", keywords: ["next", "need", "want", "help", "build", "add", "create", "implement"]),
            ],
            promptBlocks: [
                PromptBlock(emoji: "🏠", title: "Project Overview", hint: "What are you building and why?", example: "e.g. 'A gamified learning app for coding skills'"),
                PromptBlock(emoji: "⚙️", title: "Tech Stack", hint: "List every technology you're using.", example: "SwiftUI, Firebase, Combine, macOS 13+"),
                PromptBlock(emoji: "📍", title: "Current State", hint: "What's already built? What works?", example: "Home tab and Skills tab are done. Sessions needs work."),
                PromptBlock(emoji: "🎯", title: "Your Ask", hint: "What specific thing do you need help with?", example: "Add a multi-step challenge flow to the Sessions tab"),
            ],
            sampleAnswer: SampleAnswer(
                topic: "Weather App",
                text: "PROJECT:\nA weather dashboard app that shows forecasts for saved locations.\n\nSTACK:\nReact 18, TypeScript, Tailwind CSS, OpenWeatherMap API\n\nCURRENT STATE:\nI have the location search and current weather display working. The 5-day forecast component exists but shows dummy data.\n\nASK:\nConnect the 5-day forecast component to the real API. It should show daily high/low temps and weather icons."
            ),
            passFeedback: "Perfect context block! An AI would understand your project immediately and give targeted help.",
            retryHints: [
                "project": "Start by describing what your project IS. What does it do?",
                "stack": "List specific technologies - React? Swift? What database?",
                "state": "Mention what you've already built. Where are you in the project?",
                "ask": "End with a clear, specific request. What do you need help with RIGHT NOW?",
            ]
        ),

        Challenge(
            id: "rules-files-challenge",
            skillName: "AI Rules Files",
            teacher: "sage",
            xpReward: 30,
            badge: ChallengeBadge(icon: "📏", name: "Rule Maker"),
            brief: "Create a rules file that keeps AI consistent across sessions.",
            scenario: "Write a .cursorrules file that covers your project's style, patterns, and constraints.",
            guidelines: ["Add naming conventions", "Add file structure rules", "Add at least 2 'never do this' rules"],
            checkpoints: [
                ChallengeCheckpoint(id: "naming", label: "Has naming conventions", keywords: ["name", "naming", "camelcase", "snake_case", "pascal", "convention", "prefix"]),
                ChallengeCheckpoint(id: "structure", label: "Defines file structure", keywords: ["file", "folder", "directory", "structure", "organize", "path", "component"]),
                ChallengeCheckpoint(id: "donts", label: "Has 'never do' rules", keywords: ["never", "don't", "avoid", "no ", "not ", "forbidden", "prohibited"]),
                ChallengeCheckpoint(id: "patterns", label: "Describes code patterns", keywords: ["pattern", "style", "convention", "always", "prefer", "use", "standard"]),
            ],
            promptBlocks: [
                PromptBlock(emoji: "📝", title: "Naming Rules", hint: "How should files, variables, and components be named?", example: "Components: PascalCase. Files: kebab-case. Constants: SCREAMING_SNAKE."),
                PromptBlock(emoji: "📁", title: "Structure Rules", hint: "How should files be organized?", example: "Group by feature, not by type. Each feature has its own folder."),
                PromptBlock(emoji: "🚫", title: "Never Do Rules", hint: "What should AI NEVER do in your codebase?", example: "Never use !important. Never nest more than 3 levels deep."),
            ],
            sampleAnswer: nil,
            passFeedback: "Solid rules file! This will keep AI output consistent across all your sessions.",
            retryHints: [
                "naming": "Add specific naming rules - PascalCase for components? camelCase for variables?",
                "structure": "Describe your file/folder structure. Where do components go? Services?",
                "donts": "Add at least 2 'never do this' rules to prevent common AI mistakes",
                "patterns": "What coding patterns should AI follow? Error handling style? State management?",
            ]
        ),

        Challenge(
            id: "documentation-challenge",
            skillName: "Documentation",
            teacher: "luna",
            xpReward: 30,
            badge: ChallengeBadge(icon: "📄", name: "Doc Writer"),
            brief: "Write an AI-friendly README that helps both humans and AI.",
            scenario: "Write a README.md that helps both humans and AI understand your project.",
            guidelines: ["Include project description and stack", "Document file structure", "List key patterns and conventions"],
            checkpoints: [
                ChallengeCheckpoint(id: "desc", label: "Has project description", keywords: ["project", "about", "overview", "description", "what", "purpose"]),
                ChallengeCheckpoint(id: "stack", label: "Lists tech stack", keywords: ["stack", "built with", "technologies", "using", "framework"]),
                ChallengeCheckpoint(id: "structure", label: "Documents file structure", keywords: ["file", "folder", "structure", "directory", "src", "component"]),
                ChallengeCheckpoint(id: "patterns", label: "Lists patterns/conventions", keywords: ["pattern", "convention", "style", "rule", "approach", "how to"]),
            ],
            promptBlocks: [
                PromptBlock(emoji: "📖", title: "Project Overview", hint: "What does your project do? Who is it for?", example: "# MyApp\nA gamified coding skills tracker for people learning to build with AI agents."),
                PromptBlock(emoji: "🗂️", title: "File Structure", hint: "Show your folder tree.", example: "src/\n  components/\n  models/\n  views/"),
                PromptBlock(emoji: "📐", title: "Patterns", hint: "How does your code work?", example: "State management: @EnvironmentObject pattern"),
            ],
            sampleAnswer: nil,
            passFeedback: "This README would help any AI instantly understand your project. Great documentation!",
            retryHints: [
                "desc": "Add a clear project description at the top. What does it do?",
                "stack": "List all technologies used - frameworks, languages, libraries",
                "structure": "Show or describe your file/folder structure",
                "patterns": "List the key coding patterns and conventions used in the project",
            ]
        ),

        Challenge(
            id: "file-structure-challenge",
            skillName: "Project Structure",
            teacher: "sage",
            xpReward: 30,
            badge: ChallengeBadge(icon: "📁", name: "Architect"),
            brief: "Reorganize a messy project into a clean feature-based structure.",
            scenario: "A project has 20 files in flat folders. Reorganize them into a feature-based structure.",
            guidelines: ["Group related files by feature", "Create shared/ for reusable code", "Use consistent naming"],
            checkpoints: [
                ChallengeCheckpoint(id: "features", label: "Groups by feature", keywords: ["feature", "group", "folder", "organize", "auth", "home", "profile", "settings"]),
                ChallengeCheckpoint(id: "shared", label: "Has shared/common folder", keywords: ["shared", "common", "reusable", "utils", "helpers", "components"]),
                ChallengeCheckpoint(id: "naming", label: "Consistent naming", keywords: ["name", "naming", "consistent", "convention", "pattern"]),
            ],
            promptBlocks: [
                PromptBlock(emoji: "📦", title: "Group by Feature", hint: "Put related files together.", example: "auth/ -> LoginView, SignupView, AuthService"),
                PromptBlock(emoji: "🔗", title: "Create Shared", hint: "Reusable code goes in a shared folder.", example: "shared/ -> Button, Card, ApiClient, theme"),
                PromptBlock(emoji: "📝", title: "Naming Convention", hint: "Use consistent names across all features.", example: "Each feature: View, ViewModel, Service, Model"),
            ],
            sampleAnswer: nil,
            passFeedback: "Clean structure! AI tools will navigate this project much more efficiently.",
            retryHints: [
                "features": "Organize files into feature folders - auth/, home/, profile/, etc.",
                "shared": "Create a shared/ or common/ folder for reusable code",
                "naming": "Use a consistent naming pattern across all your feature folders",
            ]
        ),

        // ═══ TIER 3 ═══
        Challenge(
            id: "tool-switching-challenge",
            skillName: "Tool Switching",
            teacher: "glitch",
            xpReward: 35,
            badge: ChallengeBadge(icon: "🔄", name: "Tool Master"),
            brief: "Plan a multi-tool workflow for building a feature end-to-end.",
            scenario: "You're building a dashboard feature. Plan which tools to use for each phase: planning, coding, UI, and testing.",
            guidelines: ["Choose tools for each phase", "Explain handoff between tools", "Optimize for speed"],
            checkpoints: [
                ChallengeCheckpoint(id: "phases", label: "Covers multiple phases", keywords: ["plan", "code", "test", "design", "ui", "deploy", "phase", "step"]),
                ChallengeCheckpoint(id: "tools", label: "Assigns specific tools", keywords: ["cursor", "claude", "chatgpt", "copilot", "v0", "figma"]),
                ChallengeCheckpoint(id: "handoff", label: "Describes handoffs", keywords: ["then", "next", "after", "switch", "move to", "handoff", "hand off", "pass"]),
            ],
            promptBlocks: [
                PromptBlock(emoji: "📋", title: "Define Phases", hint: "Break your feature into phases.", example: "1. Plan 2. Code backend 3. Build UI 4. Test"),
                PromptBlock(emoji: "🔧", title: "Assign Tools", hint: "Pick the best tool for each phase.", example: "Planning: Claude. Coding: Cursor. UI: v0."),
                PromptBlock(emoji: "🔄", title: "Plan Handoffs", hint: "How do you move context between tools?", example: "Copy Claude's plan into Cursor's system prompt"),
            ],
            sampleAnswer: nil,
            passFeedback: "Efficient workflow! You'll save hours by using the right tool for each phase.",
            retryHints: [
                "phases": "Break your work into clear phases - planning, coding, design, testing",
                "tools": "Name specific tools for each phase",
                "handoff": "Explain how you transfer context from one tool to the next",
            ]
        ),

        Challenge(
            id: "scope-mgmt-challenge",
            skillName: "Scope Mgmt",
            teacher: "crash",
            xpReward: 35,
            badge: ChallengeBadge(icon: "📦", name: "Scope Slicer"),
            brief: "Break a big idea into AI-buildable chunks.",
            scenario: "Your idea: 'Build a social recipe sharing app.' Break it into 5 AI-buildable tasks, ordered by priority.",
            guidelines: ["Each task should be completable in one AI session", "Order by dependency", "Include acceptance criteria"],
            checkpoints: [
                ChallengeCheckpoint(id: "tasks", label: "Has 5+ clear tasks", keywords: ["1", "2", "3", "4", "5", "task", "step", "build", "create", "add"]),
                ChallengeCheckpoint(id: "sized", label: "Tasks are right-sized", keywords: ["component", "page", "feature", "api", "function", "form"]),
                ChallengeCheckpoint(id: "ordered", label: "Ordered by priority/dependency", keywords: ["first", "then", "after", "before", "depends", "need", "order", "priority"]),
            ],
            promptBlocks: [
                PromptBlock(emoji: "✂️", title: "Slice the Idea", hint: "Break the big idea into 5 small pieces.", example: "1. Recipe data model 2. Recipe list UI 3. Add recipe form..."),
                PromptBlock(emoji: "📏", title: "Right-size Each", hint: "Each task = one AI session (~1 hour).", example: "A single component or API endpoint per task"),
                PromptBlock(emoji: "📊", title: "Order by Priority", hint: "What needs to be built first?", example: "Data model first, then list view, then create form"),
            ],
            sampleAnswer: nil,
            passFeedback: "Great breakdown! Each task is perfectly sized for an AI coding session.",
            retryHints: [
                "tasks": "Make sure you have at least 5 distinct, specific tasks",
                "sized": "Each task should be doable in one AI session - not too big, not too small",
                "ordered": "Put them in order - what must be built before other things can work?",
            ]
        ),

        Challenge(
            id: "design-system-challenge",
            skillName: "Design System",
            teacher: "luna",
            xpReward: 35,
            badge: ChallengeBadge(icon: "🎨", name: "Design Lead"),
            brief: "Define a mini design system for visual consistency.",
            scenario: "Create a design system prompt that ensures AI-generated UI stays consistent across your app.",
            guidelines: ["Define color palette", "Define component patterns", "Define spacing and typography rules"],
            checkpoints: [
                ChallengeCheckpoint(id: "colors", label: "Defines color palette", keywords: ["color", "palette", "primary", "secondary", "accent", "hex", "#", "background"]),
                ChallengeCheckpoint(id: "components", label: "Lists component patterns", keywords: ["button", "card", "input", "component", "pattern", "style"]),
                ChallengeCheckpoint(id: "spacing", label: "Has spacing/typography", keywords: ["spacing", "padding", "margin", "font", "text", "size", "weight", "typography"]),
            ],
            promptBlocks: [
                PromptBlock(emoji: "🎨", title: "Color Palette", hint: "Define your colors.", example: "Primary: #6BCB77, Secondary: #2D2B26, Accent: #D89840"),
                PromptBlock(emoji: "🧩", title: "Components", hint: "How should buttons, cards, inputs look?", example: "Buttons: rounded-12, bold text, primary bg"),
                PromptBlock(emoji: "📐", title: "Spacing & Type", hint: "Define your spacing scale and fonts.", example: "Base: 8px grid. Body: 14px. Headers: 20px bold."),
            ],
            sampleAnswer: nil,
            passFeedback: "This design system will keep your app looking polished and professional!",
            retryHints: [
                "colors": "Add specific colors - hex codes, named roles (primary, secondary, etc.)",
                "components": "Describe how common components should look (buttons, cards, inputs)",
                "spacing": "Add spacing units and font sizes to ensure consistency",
            ]
        ),

        Challenge(
            id: "iteration-challenge",
            skillName: "Prompt Iteration",
            teacher: "nova",
            xpReward: 35,
            badge: ChallengeBadge(icon: "🔁", name: "Prompt Refiner"),
            brief: "Iterate on a prompt 3 times to improve AI output.",
            scenario: "Start with a basic prompt, then refine it 3 times, each time adding more specificity based on what the AI got wrong.",
            guidelines: ["Write your initial prompt", "Identify what's missing in the output", "Refine with more constraints each round"],
            checkpoints: [
                ChallengeCheckpoint(id: "v1", label: "Shows initial prompt", keywords: ["first", "initial", "v1", "version 1", "start", "original", "prompt"]),
                ChallengeCheckpoint(id: "feedback", label: "Identifies issues", keywords: ["wrong", "missing", "issue", "problem", "didn't", "wasn't", "need", "add"]),
                ChallengeCheckpoint(id: "v3", label: "Shows improved version", keywords: ["refined", "improved", "v2", "v3", "version", "updated", "better", "added"]),
            ],
            promptBlocks: [
                PromptBlock(emoji: "1️⃣", title: "Version 1", hint: "Write your first attempt.", example: "Build me a login page"),
                PromptBlock(emoji: "🔍", title: "What Went Wrong", hint: "What did AI miss or get wrong?", example: "No error states, wrong colors, missing loading state"),
                PromptBlock(emoji: "3️⃣", title: "Version 3", hint: "Show your refined prompt.", example: "Build a login page with: [all the details AI missed]"),
            ],
            sampleAnswer: nil,
            passFeedback: "This is exactly how pros iterate! Each version gets meaningfully better.",
            retryHints: [
                "v1": "Show your first attempt at the prompt - even if it's simple",
                "feedback": "What went wrong with the first version? What did you learn?",
                "v3": "Show how you improved the prompt in later versions",
            ]
        ),

        // ═══ TIER 4 ═══
        Challenge(
            id: "personas-challenge",
            skillName: "User Personas",
            teacher: "luna",
            xpReward: 40,
            badge: ChallengeBadge(icon: "🧩", name: "User Advocate"),
            brief: "Create user personas that shape how you build.",
            scenario: "Define 3 user personas for your app and write prompts that incorporate their needs.",
            guidelines: ["Create distinct personas with goals", "Write a prompt tailored to each persona", "Show how personas change your approach"],
            checkpoints: [
                ChallengeCheckpoint(id: "personas", label: "Has 3+ personas", keywords: ["persona", "user", "beginner", "expert", "casual", "power", "name", "age"]),
                ChallengeCheckpoint(id: "goals", label: "Each has goals/needs", keywords: ["goal", "need", "want", "pain", "frustrat", "problem", "motivation"]),
                ChallengeCheckpoint(id: "prompts", label: "Tailored prompts per persona", keywords: ["prompt", "for", "this user", "they", "their", "persona"]),
            ],
            promptBlocks: [
                PromptBlock(emoji: "👤", title: "Define Personas", hint: "Create 3 distinct users.", example: "Sarah (15, beginner), Mike (25, intermediate), Lin (40, non-tech)"),
                PromptBlock(emoji: "🎯", title: "Goals & Needs", hint: "What does each persona want?", example: "Sarah: easy onboarding. Mike: power features. Lin: simplicity."),
                PromptBlock(emoji: "📝", title: "Tailored Prompts", hint: "Write a prompt considering each persona.", example: "For Sarah: 'Make the onboarding 3 steps max, with big buttons'"),
            ],
            sampleAnswer: nil,
            passFeedback: "These personas will help you build features that actually serve real users!",
            retryHints: [
                "personas": "Create at least 3 distinct personas with names and backgrounds",
                "goals": "Give each persona specific goals, needs, and pain points",
                "prompts": "Show how you'd write different prompts for different personas",
            ]
        ),

        Challenge(
            id: "context-windows-challenge",
            skillName: "Context Windows",
            teacher: "sage",
            xpReward: 40,
            badge: ChallengeBadge(icon: "🧠", name: "Memory Manager"),
            brief: "Optimize a conversation for AI memory limits.",
            scenario: "You're 20 messages deep and AI is losing context. Restructure your conversation to stay within limits.",
            guidelines: ["Summarize key context", "Remove irrelevant history", "Front-load the most important info"],
            checkpoints: [
                ChallengeCheckpoint(id: "summary", label: "Summarizes context", keywords: ["summary", "summarize", "key points", "important", "essential", "relevant"]),
                ChallengeCheckpoint(id: "trim", label: "Removes irrelevant parts", keywords: ["remove", "trim", "cut", "irrelevant", "unnecessary", "old", "delete"]),
                ChallengeCheckpoint(id: "structure", label: "Front-loads important info", keywords: ["first", "top", "start", "front", "beginning", "most important", "priority"]),
            ],
            promptBlocks: [
                PromptBlock(emoji: "📋", title: "Summarize", hint: "Condense key decisions and context.", example: "Summary: We decided on React + Tailwind, auth is done, working on dashboard"),
                PromptBlock(emoji: "✂️", title: "Trim", hint: "What can be removed?", example: "Remove old debugging conversations, outdated approaches"),
                PromptBlock(emoji: "⬆️", title: "Prioritize", hint: "Put most important context first.", example: "Current state and immediate task at the very top"),
            ],
            sampleAnswer: nil,
            passFeedback: "You understand context management! This skill prevents AI from losing its way in long sessions.",
            retryHints: [
                "summary": "Show how you'd summarize a long conversation into key points",
                "trim": "What parts of old conversations can safely be removed?",
                "structure": "Explain why important info should go at the start of your prompt",
            ]
        ),

        Challenge(
            id: "architecture-challenge",
            skillName: "AI Architecture",
            teacher: "sage",
            xpReward: 40,
            badge: ChallengeBadge(icon: "🏗️", name: "Systems Thinker"),
            brief: "Design a project structure AI can effectively maintain.",
            scenario: "Design the architecture for a medium-sized app so that AI tools can effectively help you build and maintain it.",
            guidelines: ["Define clear module boundaries", "Document interfaces between modules", "Create a maintenance guide"],
            checkpoints: [
                ChallengeCheckpoint(id: "modules", label: "Has clear modules", keywords: ["module", "layer", "component", "service", "model", "view", "controller"]),
                ChallengeCheckpoint(id: "interfaces", label: "Defines interfaces", keywords: ["interface", "api", "contract", "protocol", "boundary", "between"]),
                ChallengeCheckpoint(id: "maintenance", label: "Includes maintenance guide", keywords: ["maintain", "update", "change", "add", "extend", "scale", "guide"]),
            ],
            promptBlocks: [
                PromptBlock(emoji: "🏗️", title: "Modules", hint: "What are the main building blocks?", example: "Auth module, Data module, UI module, API module"),
                PromptBlock(emoji: "🔌", title: "Interfaces", hint: "How do modules talk to each other?", example: "Auth exposes: login(), logout(), currentUser"),
                PromptBlock(emoji: "📖", title: "Maintenance", hint: "How do you add features or fix bugs?", example: "To add a feature: 1. Create model 2. Add service 3. Build view"),
            ],
            sampleAnswer: nil,
            passFeedback: "This architecture makes your project AI-friendly and maintainable. Excellent design!",
            retryHints: [
                "modules": "Break your app into clear, independent modules",
                "interfaces": "Define how each module communicates with others",
                "maintenance": "Add a guide for how to add new features or fix bugs",
            ]
        ),

        Challenge(
            id: "second-brain-challenge",
            skillName: "Second Brain",
            teacher: "glitch",
            xpReward: 40,
            badge: ChallengeBadge(icon: "💡", name: "Knowledge Keeper"),
            brief: "Build a personal knowledge system for your AI learnings.",
            scenario: "Set up a system to capture, organize, and retrieve what you learn from AI interactions.",
            guidelines: ["Design a capture workflow", "Create categories and tags", "Set up retrieval prompts"],
            checkpoints: [
                ChallengeCheckpoint(id: "capture", label: "Has capture workflow", keywords: ["capture", "save", "note", "record", "log", "collect", "store"]),
                ChallengeCheckpoint(id: "organize", label: "Has organization system", keywords: ["organize", "category", "tag", "folder", "label", "group", "sort"]),
                ChallengeCheckpoint(id: "retrieve", label: "Has retrieval method", keywords: ["retrieve", "find", "search", "look up", "recall", "reference", "use"]),
            ],
            promptBlocks: [
                PromptBlock(emoji: "📥", title: "Capture", hint: "How do you save what you learn?", example: "After each AI session, note the key technique in a markdown file"),
                PromptBlock(emoji: "🏷️", title: "Organize", hint: "How do you categorize knowledge?", example: "Tags: #prompting, #debugging, #architecture, #patterns"),
                PromptBlock(emoji: "🔍", title: "Retrieve", hint: "How do you find what you need later?", example: "Search by tag, or ask AI 'what pattern did I use for auth?'"),
            ],
            sampleAnswer: nil,
            passFeedback: "Your second brain will compound your knowledge over time. This is how experts level up!",
            retryHints: [
                "capture": "Describe a specific workflow for saving what you learn from AI",
                "organize": "Create a system of categories or tags for your knowledge",
                "retrieve": "How would you find a specific piece of knowledge when you need it?",
            ]
        ),
    ]

    static let dailyChallenges: [DailyChallenge] = [
        DailyChallenge(id: "dc1", title: "Constraint Master", description: "Write a prompt that includes at least 3 specific constraints", xpReward: 50),
        DailyChallenge(id: "dc2", title: "Bug Spotter", description: "Find and explain 1 bug in a code snippet", xpReward: 50),
        DailyChallenge(id: "dc3", title: "Elevator Pitch", description: "Describe your current project to AI in under 50 words", xpReward: 50),
        DailyChallenge(id: "dc4", title: "Rule Writer", description: "Write a .cursorrules entry for your favorite convention", xpReward: 50),
        DailyChallenge(id: "dc5", title: "Jargon Buster", description: "Explain an error message without using technical jargon", xpReward: 50),
        DailyChallenge(id: "dc6", title: "Prompt Checklist", description: "List 5 things you'd include in a prompt for a login page", xpReward: 50),
        DailyChallenge(id: "dc7", title: "Prompt Diet", description: "Write a prompt, then rewrite it 50% shorter", xpReward: 50),
        DailyChallenge(id: "dc8", title: "Context Detective", description: "Spot what's missing from a vague prompt", xpReward: 50),
        DailyChallenge(id: "dc9", title: "File Navigator", description: "Name 3 files you'd reference when asking AI to add a feature", xpReward: 50),
        DailyChallenge(id: "dc10", title: "One-Liner", description: "Write a one-sentence summary of what your code does", xpReward: 50),
    ]
}

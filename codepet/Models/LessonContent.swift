import SwiftUI

// MARK: - Lesson Data Model

struct Lesson: Identifiable, Equatable {
    let id: String          // matches Skill.id
    let skillName: String
    let teacher: String     // character id ("nova", "crash", etc.)
    let duration: String    // "3 min", "5 min"
    let steps: [LessonStep]

    static func == (lhs: Lesson, rhs: Lesson) -> Bool {
        lhs.id == rhs.id
    }
}

enum LessonStepType {
    case briefing
    case learn
    case applyIt       // multiple-choice quiz
    case fieldMission  // scenario-based quiz
    case summary
}

struct LessonStep: Identifiable {
    let id = UUID()
    let type: LessonStepType
    let title: String
    let content: LessonStepContent
}

struct QuizOption: Identifiable {
    let id: String      // "a", "b", "c", "d"
    let text: String
    let correct: Bool
}

enum LessonStepContent {
    case briefing(characterIntro: String, bodyText: String, hook: String)
    case learn(concept: String, coreExplanation: String, badExample: ExamplePair?, goodExample: ExamplePair?, insight: String)
    case applyIt(instruction: String, originalPrompt: String, options: [QuizOption], correctFeedback: String, wrongFeedback: String)
    case fieldMission(scenario: String, task: String, options: [QuizOption], correctFeedback: String, wrongFeedback: String)
    case summary(recap: [String], xpReward: Int, badge: String?)
}

struct ExamplePair {
    let label: String
    let text: String
}

// MARK: - All Lessons

struct LessonLibrary {

    static let all: [String: Lesson] = [

        // ═══════════════════════════════════════
        // TIER 1 — Foundations / The Molten Forge
        // ═══════════════════════════════════════

        "prompt-clarity": Lesson(
            id: "prompt-clarity",
            skillName: "Prompt Clarity",
            teacher: "nova",
            duration: "3 min",
            steps: [
                LessonStep(type: .briefing, title: "Why Prompts Matter", content: .briefing(
                    characterIntro: "Hey, I'm Nova. Most people talk to AI like they're texting a friend — vague, messy, hoping it reads their mind. That's why you get random stuff back. Today I'll show you the difference between a lazy prompt and a clear one.",
                    bodyText: "Every time you ask AI to build something, the quality of what you get back depends almost entirely on how you asked. A vague prompt gives you a generic result. A specific prompt gives you exactly what you need.",
                    hook: "After this lesson, your prompts will work on the first try — not the fifth."
                )),
                LessonStep(type: .learn, title: "The 3 Parts of a Clear Prompt", content: .learn(
                    concept: "CORE CONCEPT",
                    coreExplanation: "Every good prompt has 3 parts: CONTEXT (what tech you're using), TASK (what you want built), and CONSTRAINTS (what to avoid or include).",
                    badExample: ExamplePair(label: "VAGUE PROMPT", text: "Make me a button"),
                    goodExample: ExamplePair(label: "CLEAR PROMPT", text: "Using React and Tailwind CSS, create a primary action button component with hover and disabled states. Use rounded-lg, bg-blue-600, and text-white. Include an onClick prop."),
                    insight: "See the difference? The good prompt tells AI exactly what framework, what styles, and what behavior to include. No guessing needed."
                )),
                LessonStep(type: .applyIt, title: "Fix This Prompt", content: .applyIt(
                    instruction: "This prompt is too vague. Pick the version that adds the right details.",
                    originalPrompt: "Add a login form to my page",
                    options: [
                        QuizOption(id: "a", text: "Add a really good login form with nice styling to my website page please", correct: false),
                        QuizOption(id: "b", text: "I need a login form. Make it look modern and professional. Add some animations too.", correct: false),
                        QuizOption(id: "c", text: "Using Next.js and Tailwind, add a login form to app/login/page.tsx with email and password fields, a submit button, and client-side validation. Use the existing color tokens from globals.css.", correct: true),
                        QuizOption(id: "d", text: "Create login form with React", correct: false),
                    ],
                    correctFeedback: "Exactly! You specified the framework (Next.js + Tailwind), the file location, the fields, and even referenced existing styles. That's a prompt that works on the first try.",
                    wrongFeedback: "Not quite. That prompt is still missing key details — what framework? What file? What fields? The AI will have to guess, and it'll guess wrong."
                )),
                LessonStep(type: .fieldMission, title: "Real World Challenge", content: .fieldMission(
                    scenario: "Your friend wants to build a personal portfolio site. They're using React with CSS modules. They need a hero section with their name, title, and a call-to-action button.",
                    task: "Which prompt would you give to the AI?",
                    options: [
                        QuizOption(id: "a", text: "Build a hero section for a portfolio", correct: false),
                        QuizOption(id: "b", text: "In my React portfolio project using CSS modules, create a Hero component in src/components/Hero.jsx. It should display a name (h1), job title (h2), and a 'View My Work' button that scrolls to the projects section. Use the existing color variables from styles/variables.module.css.", correct: true),
                        QuizOption(id: "c", text: "Make a beautiful hero section with animations and gradients for a portfolio website", correct: false),
                    ],
                    correctFeedback: "Perfect! You nailed all three parts — context (React + CSS modules), task (Hero component with specific elements), and constraints (existing color variables). Nova would be proud.",
                    wrongFeedback: "Almost! Remember the 3 parts: Context (what tech), Task (what specifically to build), Constraints (what to use/avoid). Try to include all three."
                )),
                LessonStep(type: .summary, title: "Lesson Complete!", content: .summary(
                    recap: ["Always include Context, Task, and Constraints", "Be specific about tech, styles, and behavior", "The clearer you are, the fewer retries you need"],
                    xpReward: 25,
                    badge: "Prompt Apprentice"
                ))
            ]
        ),

        "error-reading": Lesson(
            id: "error-reading",
            skillName: "Error Reading",
            teacher: "crash",
            duration: "4 min",
            steps: [
                LessonStep(type: .briefing, title: "Errors Are Clues", content: .briefing(
                    characterIntro: "SMASH! Oh hey. I'm Crash. Most people see an error and panic. But errors are just the computer telling you exactly what went wrong. Today you'll learn to read them like a detective.",
                    bodyText: "Error messages have a structure: the TYPE tells you what category of problem, the MESSAGE tells you what happened, and the LOCATION tells you where.",
                    hook: "After this, you'll never just paste an error and say 'fix it' again."
                )),
                LessonStep(type: .learn, title: "Anatomy of an Error", content: .learn(
                    concept: "READING ERRORS",
                    coreExplanation: "Every error has 3 parts: TYPE (SyntaxError, TypeError, etc.), MESSAGE (what went wrong), and STACK TRACE (where it happened). Read bottom-to-top for the root cause.",
                    badExample: ExamplePair(label: "PANIC MODE", text: "\"I got an error, can you fix my code?\""),
                    goodExample: ExamplePair(label: "DETECTIVE MODE", text: "\"I got a TypeError: Cannot read property 'map' of undefined on line 42 of ProductList.jsx. The data array might not be loaded yet.\""),
                    insight: "When you describe the error clearly, AI can solve it in one shot instead of asking 5 follow-up questions."
                )),
                LessonStep(type: .applyIt, title: "Read This Error", content: .applyIt(
                    instruction: "Look at this error and pick what's actually wrong:",
                    originalPrompt: "Module not found: Can't resolve './components/Header' in '/src/pages'",
                    options: [
                        QuizOption(id: "a", text: "The Header component has a bug in its code", correct: false),
                        QuizOption(id: "b", text: "The file path './components/Header' doesn't exist from the /src/pages folder", correct: true),
                        QuizOption(id: "c", text: "React is not installed properly", correct: false),
                        QuizOption(id: "d", text: "The project needs to be rebuilt from scratch", correct: false),
                    ],
                    correctFeedback: "You got it! 'Module not found' + 'Can't resolve' = the file path is wrong. The fix is either: move the file, or fix the import path. No need to rebuild anything.",
                    wrongFeedback: "Look again at the key words: 'Module not found' and 'Can't resolve'. This isn't about broken code — it's about a wrong file path. The file simply doesn't exist where the import says it should."
                )),
                LessonStep(type: .fieldMission, title: "Real World Challenge", content: .fieldMission(
                    scenario: "You're building a to-do app and you see this error:\nTypeError: todos.filter is not a function\n    at TodoList (src/TodoList.jsx:8:24)",
                    task: "What would you do?",
                    options: [
                        QuizOption(id: "a", text: "Check line 8 of TodoList.jsx — 'todos' is probably not an array. Add console.log(typeof todos) to verify, then ensure it's initialized as an array.", correct: true),
                        QuizOption(id: "b", text: "Delete TodoList.jsx and ask AI to rewrite it", correct: false),
                        QuizOption(id: "c", text: "Install a different todo library", correct: false),
                    ],
                    correctFeedback: "Exactly! 'not a function' means you're calling .filter() on something that isn't an array. Check the type, find where it's set, fix the initialization. Clean debugging!",
                    wrongFeedback: "Think about what 'not a function' means — .filter() only works on arrays. So 'todos' isn't an array. You need to find out why and fix it at the source."
                )),
                LessonStep(type: .summary, title: "Lesson Complete!", content: .summary(
                    recap: ["Read errors bottom-to-top for root cause", "Identify Type, Message, and Location", "Include error details when asking AI for help"],
                    xpReward: 25,
                    badge: "Bug Spotter"
                ))
            ]
        ),

        "tool-basics": Lesson(
            id: "tool-basics",
            skillName: "Tool Basics",
            teacher: "sage",
            duration: "3 min",
            steps: [
                LessonStep(type: .briefing, title: "The Right Tool", content: .briefing(
                    characterIntro: "Breathe. Then build. I'm Sage. Today we discuss something fundamental — not all AI tools are the same, and using the wrong one wastes your time.",
                    bodyText: "ChatGPT, Claude, Cursor, v0, Copilot — each excels at different things. Knowing which to reach for is itself a skill.",
                    hook: "After this lesson, you'll stop using a hammer when you need a screwdriver."
                )),
                LessonStep(type: .learn, title: "When to Use What", content: .learn(
                    concept: "TOOL SELECTION",
                    coreExplanation: "Chat AIs (ChatGPT, Claude) are best for planning, explaining, and brainstorming. Code AIs (Cursor, Copilot) are best for writing and editing code in context. Builder AIs (v0, Bolt) are best for generating full UI components quickly.",
                    badExample: ExamplePair(label: "WRONG TOOL", text: "Using ChatGPT to edit 50 files in your codebase"),
                    goodExample: ExamplePair(label: "RIGHT TOOL", text: "Using Cursor to edit files (it sees your whole project) and Claude to plan the architecture first"),
                    insight: "The best builders use 2-3 tools together. Plan in chat, build in code AI, generate UI in builders."
                )),
                LessonStep(type: .applyIt, title: "Match the Task", content: .applyIt(
                    instruction: "You need to plan the database schema for your new app. Which tool should you use?",
                    originalPrompt: "Plan a database schema for a recipe sharing app",
                    options: [
                        QuizOption(id: "a", text: "Cursor — open a new file and start typing table names", correct: false),
                        QuizOption(id: "b", text: "v0 by Vercel — generate a database UI", correct: false),
                        QuizOption(id: "c", text: "Claude or ChatGPT — brainstorm and plan the schema in a conversation", correct: true),
                        QuizOption(id: "d", text: "GitHub Copilot — let it autocomplete your schema", correct: false),
                    ],
                    correctFeedback: "Chat AIs are perfect for planning! They can discuss trade-offs, suggest schema designs, and help you think through relationships before you write any code.",
                    wrongFeedback: "Planning tasks are best done in conversation. Code editors are for writing code, not for brainstorming architecture decisions. Try a Chat AI first."
                )),
                LessonStep(type: .fieldMission, title: "Real World Challenge", content: .fieldMission(
                    scenario: "You have a React project and need to: 1) Add a new feature across 5 files, 2) Generate a new landing page component, 3) Debug why a test is failing.",
                    task: "What's the best tool workflow?",
                    options: [
                        QuizOption(id: "a", text: "Use ChatGPT for everything — paste code back and forth", correct: false),
                        QuizOption(id: "b", text: "Use Cursor for the multi-file feature + debugging (it sees your project), and v0 for the landing page (quick UI generation)", correct: true),
                        QuizOption(id: "c", text: "Use v0 for everything — it can generate any code", correct: false),
                    ],
                    correctFeedback: "You're thinking like a pro! Cursor for context-heavy coding, v0 for quick UI generation. Using the right tool for each task saves hours.",
                    wrongFeedback: "Think about what each tool is best at. Multi-file edits need a tool that sees your whole project. UI generation needs a tool designed for that."
                )),
                LessonStep(type: .summary, title: "Lesson Complete!", content: .summary(
                    recap: ["Chat AIs for planning and explaining", "Code AIs for writing and editing in context", "Builder AIs for rapid UI generation", "Combine tools for best results"],
                    xpReward: 25,
                    badge: "Tool Scout"
                ))
            ]
        ),

        "code-judgment": Lesson(
            id: "code-judgment",
            skillName: "Code Judgment",
            teacher: "glitch",
            duration: "4 min",
            steps: [
                LessonStep(type: .briefing, title: "Trust But Verify", content: .briefing(
                    characterIntro: "Rules? Where we're going, we don't need— actually wait, this one's important. I'm Glitch. AI writes code fast, but fast doesn't mean correct. You need to know when to trust it and when to say 'try again'.",
                    bodyText: "AI-generated code can look perfect but have subtle bugs, security holes, or bad patterns. Your job isn't to write every line — it's to be the quality inspector.",
                    hook: "After this, you'll spot the difference between code that works and code that's actually good."
                )),
                LessonStep(type: .learn, title: "Red Flags in AI Code", content: .learn(
                    concept: "CODE REVIEW",
                    coreExplanation: "Watch for: hardcoded values, missing error handling, no input validation, outdated patterns, and 'it works but I don't understand why' code. If you can't explain what code does, don't ship it.",
                    badExample: ExamplePair(label: "BLIND TRUST", text: "\"AI wrote it, ship it!\" → You just deployed a function that crashes on empty arrays."),
                    goodExample: ExamplePair(label: "SMART REVIEW", text: "\"This looks right, but what happens if the array is empty? Let me add a check.\" → You caught a bug before users did."),
                    insight: "The #1 rule: if AI generates code you don't understand, ask it to explain before you use it."
                )),
                LessonStep(type: .applyIt, title: "Spot the Issue", content: .applyIt(
                    instruction: "AI generated this function. What's the main problem?",
                    originalPrompt: "function getUser(id) {\n  const user = users.find(u => u.id === id);\n  return user.name;\n}",
                    options: [
                        QuizOption(id: "a", text: "The function name should be camelCase — it's fine otherwise", correct: false),
                        QuizOption(id: "b", text: "users.find() can return undefined if no match, so user.name will crash", correct: true),
                        QuizOption(id: "c", text: "It should use filter() instead of find()", correct: false),
                        QuizOption(id: "d", text: "The arrow function syntax is wrong", correct: false),
                    ],
                    correctFeedback: "Exactly! If no user matches the id, find() returns undefined. Then accessing .name on undefined throws a TypeError. The fix: add a null check or use optional chaining (user?.name).",
                    wrongFeedback: "Look at what happens when find() doesn't find a matching user — it returns undefined. Then what happens when you call .name on undefined?"
                )),
                LessonStep(type: .fieldMission, title: "Real World Challenge", content: .fieldMission(
                    scenario: "AI generated an API endpoint that fetches user data and returns it directly. There's no try/catch, no input validation, and no rate limiting.",
                    task: "What's the most critical issue to fix first?",
                    options: [
                        QuizOption(id: "a", text: "Add a try/catch for error handling — if the database call fails, the server crashes", correct: true),
                        QuizOption(id: "b", text: "Add rate limiting first — someone might abuse it", correct: false),
                        QuizOption(id: "c", text: "Add input validation — the user ID might be invalid", correct: false),
                    ],
                    correctFeedback: "Right! Error handling is the most critical. Without try/catch, a single failed database call can crash your entire server. Rate limiting and validation are important too, but crash prevention comes first.",
                    wrongFeedback: "All three are important, but think about what causes the worst outcome. A crashed server affects ALL users, not just one."
                )),
                LessonStep(type: .summary, title: "Lesson Complete!", content: .summary(
                    recap: ["Never ship code you don't understand", "Check for edge cases and error handling", "Ask AI to explain unclear code", "You're the quality inspector, not just a copy-paster"],
                    xpReward: 25,
                    badge: "Code Judge"
                ))
            ]
        ),

        // ═══════════════════════════════════════
        // TIER 2 — Context & Structure / The Frozen Spire
        // ═══════════════════════════════════════

        "context-setting": Lesson(
            id: "context-setting",
            skillName: "Context Setting",
            teacher: "luna",
            duration: "4 min",
            steps: [
                LessonStep(type: .briefing, title: "Context Is Everything", content: .briefing(
                    characterIntro: "Hey you~ I'm Luna. Imagine someone walks up and says 'make it blue.' Blue what? Which shade? That's what it's like when you give AI a task without context.",
                    bodyText: "Context is the background information AI needs before it can help you well. Your tech stack, project structure, what you've already tried, and what you're building toward.",
                    hook: "After this, your AI conversations will feel like talking to a teammate who actually knows your project."
                )),
                LessonStep(type: .learn, title: "The Context Sandwich", content: .learn(
                    concept: "SETTING CONTEXT",
                    coreExplanation: "Start every AI conversation with a Context Block: PROJECT (what you're building), STACK (technologies), CURRENT STATE (what exists), and ASK (what you need next). This front-loading saves dozens of back-and-forth messages.",
                    badExample: ExamplePair(label: "NO CONTEXT", text: "Add a search bar to my app"),
                    goodExample: ExamplePair(label: "WITH CONTEXT", text: "I'm building a recipe app with React and Supabase. I have a /recipes page that lists cards. Add a search bar above the grid that filters recipes by title in real-time. Use the existing RecipeCard component."),
                    insight: "A 30-second context block saves 10 minutes of 'what framework?' and 'where does this go?' questions."
                )),
                LessonStep(type: .applyIt, title: "Add the Context", content: .applyIt(
                    instruction: "Someone wrote this prompt. Which version adds proper context?",
                    originalPrompt: "Fix the login bug",
                    options: [
                        QuizOption(id: "a", text: "Fix the login bug please, it's broken", correct: false),
                        QuizOption(id: "b", text: "In my Next.js app using NextAuth, the login form submits but redirects to /api/auth/error instead of /dashboard. I'm using the Credentials provider with a PostgreSQL database. The console shows 'Invalid callback URL'. My next-auth config is in app/api/auth/[...nextauth]/route.ts.", correct: true),
                        QuizOption(id: "c", text: "My login doesn't work. I'm using React. Can you fix it?", correct: false),
                    ],
                    correctFeedback: "Perfect! You included the framework, the exact error behavior, the auth setup, and the file location. AI can pinpoint the issue immediately.",
                    wrongFeedback: "A good context includes: what framework, what specific behavior you see, what you expected, and where the relevant code lives."
                )),
                LessonStep(type: .fieldMission, title: "Real World Challenge", content: .fieldMission(
                    scenario: "You're starting a new AI chat session to add a dark mode toggle to your app. You're using React, Tailwind, and a ThemeContext that already exists in src/context/ThemeContext.tsx.",
                    task: "What's the best way to start the conversation?",
                    options: [
                        QuizOption(id: "a", text: "Add dark mode to my app", correct: false),
                        QuizOption(id: "b", text: "I need a dark mode toggle. My app uses React + Tailwind. I already have a ThemeContext in src/context/ThemeContext.tsx that provides isDark and toggleTheme. Add a toggle button to the existing Navbar component in src/components/Navbar.tsx that uses this context.", correct: true),
                        QuizOption(id: "c", text: "Can you help me with dark mode? I use Tailwind CSS.", correct: false),
                    ],
                    correctFeedback: "Excellent! By mentioning the existing ThemeContext and exact file paths, AI will use what you already have instead of creating something new from scratch.",
                    wrongFeedback: "When you have existing code, tell AI about it! Otherwise it might create a whole new theme system instead of using what you already built."
                )),
                LessonStep(type: .summary, title: "Lesson Complete!", content: .summary(
                    recap: ["Always start with a Context Block", "Include: Project, Stack, State, Ask", "30 seconds of context saves 10 minutes of back-and-forth"],
                    xpReward: 30,
                    badge: "Context Crafter"
                ))
            ]
        ),

        "rules-files": Lesson(
            id: "rules-files",
            skillName: "AI Rules Files",
            teacher: "sage",
            duration: "4 min",
            steps: [
                LessonStep(type: .briefing, title: "Your AI Playbook", content: .briefing(
                    characterIntro: "Every time you start a new AI session, you re-explain your conventions. What a waste. I'm Sage. Today I'll show you how to write rules once and have AI follow them forever.",
                    bodyText: "Rules files (.cursorrules, .clinerules, CLAUDE.md) are instructions that get automatically loaded into your AI tool. They tell AI your coding style, project conventions, and things to always/never do.",
                    hook: "After this, your AI will write code your way without being told twice."
                )),
                LessonStep(type: .learn, title: "Writing Good Rules", content: .learn(
                    concept: "AI RULES",
                    coreExplanation: "A good rules file has: STYLE (naming conventions, formatting), PATTERNS (how you structure components, handle errors), CONSTRAINTS (what to never use), and CONTEXT (project description, key files).",
                    badExample: ExamplePair(label: "NO RULES", text: "AI uses camelCase in your snake_case project, adds console.logs everywhere, and picks random libraries."),
                    goodExample: ExamplePair(label: "WITH RULES", text: "// .cursorrules\n- Use snake_case for variables\n- Never use console.log (use logger)\n- Always handle errors with try/catch\n- Components go in /src/components/"),
                    insight: "Your rules file is like onboarding a new developer. Write it once, and every AI session starts aligned with your project."
                )),
                LessonStep(type: .applyIt, title: "Pick the Best Rule", content: .applyIt(
                    instruction: "Which of these is the most useful rule for a .cursorrules file?",
                    originalPrompt: "Your project uses TypeScript strict mode and Tailwind CSS",
                    options: [
                        QuizOption(id: "a", text: "Write good code", correct: false),
                        QuizOption(id: "b", text: "Always use TypeScript strict mode. Never use 'any' type. Use Tailwind utility classes only — no inline styles or CSS files.", correct: true),
                        QuizOption(id: "c", text: "Make sure the code is nice and clean", correct: false),
                        QuizOption(id: "d", text: "Use best practices", correct: false),
                    ],
                    correctFeedback: "Specific rules work! 'Never use any type' and 'no inline styles' are concrete instructions AI can actually follow. Vague rules like 'write good code' mean nothing.",
                    wrongFeedback: "Rules need to be specific and actionable. AI can't interpret 'good code' — but it CAN follow 'never use any type' and 'use Tailwind only'."
                )),
                LessonStep(type: .fieldMission, title: "Real World Challenge", content: .fieldMission(
                    scenario: "You notice AI keeps generating components with inline styles even though your project uses Tailwind. It also keeps adding console.log statements.",
                    task: "What rule would you add to prevent this?",
                    options: [
                        QuizOption(id: "a", text: "Please don't use inline styles or console.log if possible", correct: false),
                        QuizOption(id: "b", text: "NEVER use inline styles — use Tailwind utility classes exclusively. NEVER use console.log — use the logger utility from src/lib/logger.ts instead.", correct: true),
                        QuizOption(id: "c", text: "Use better styling practices", correct: false),
                    ],
                    correctFeedback: "Strong rules! Using 'NEVER' makes it absolute, and pointing to the logger utility gives AI a concrete alternative. This will actually change AI's behavior.",
                    wrongFeedback: "Rules need to be absolute and specific. 'If possible' gives AI wiggle room. Tell it exactly what NOT to do and what to do instead."
                )),
                LessonStep(type: .summary, title: "Lesson Complete!", content: .summary(
                    recap: ["Rules files auto-load your conventions into AI", "Include: Style, Patterns, Constraints, Context", "Write once, benefit every session"],
                    xpReward: 30,
                    badge: "Rule Maker"
                ))
            ]
        ),

        "documentation": Lesson(
            id: "documentation",
            skillName: "Documentation",
            teacher: "luna",
            duration: "3 min",
            steps: [
                LessonStep(type: .briefing, title: "Docs That Work", content: .briefing(
                    characterIntro: "I had an idea while you were gone... what if your docs helped both you AND your AI? I'm Luna, and today we'll write documentation that makes AI smarter about your project.",
                    bodyText: "Good documentation isn't just for humans anymore. When AI can read your docs, it understands your project better and writes more accurate code.",
                    hook: "After this, your README will be a superpower — for you and your AI."
                )),
                LessonStep(type: .learn, title: "AI-Friendly Docs", content: .learn(
                    concept: "DOCUMENTATION",
                    coreExplanation: "Write docs that answer: What does this project do? How is it structured? What are the key conventions? What's the current state? AI tools read your README, comments, and doc files to understand context.",
                    badExample: ExamplePair(label: "USELESS README", text: "# My App\nA cool app.\n\n## Install\nnpm install"),
                    goodExample: ExamplePair(label: "AI-FRIENDLY README", text: "# RecipeApp\nA recipe sharing app (React + Supabase)\n\n## Structure\n/src/components - UI components\n/src/hooks - Custom hooks\n/src/lib - Supabase client, utils\n\n## Key Patterns\n- Server components by default\n- Client components marked with 'use client'"),
                    insight: "Your docs are context that loads automatically. The better they are, the better AI performs."
                )),
                LessonStep(type: .applyIt, title: "Documentation in Practice", content: .applyIt(
                    instruction: "Which README section would help AI the most when adding a new feature?",
                    originalPrompt: "You're asking AI to add a favorites feature to your recipe app",
                    options: [
                        QuizOption(id: "a", text: "A section listing the app's color palette", correct: false),
                        QuizOption(id: "b", text: "A section describing file structure and key patterns (where components go, how state is managed, naming conventions)", correct: true),
                        QuizOption(id: "c", text: "A section with the app's deployment instructions", correct: false),
                    ],
                    correctFeedback: "File structure and patterns! When AI knows where components go and how state works, it creates features that fit naturally into your existing codebase.",
                    wrongFeedback: "Think about what AI needs to know to add a feature: where to put files, how to structure components, and what patterns to follow."
                )),
                LessonStep(type: .fieldMission, title: "Real World Challenge", content: .fieldMission(
                    scenario: "You have a README that just says '# TodoApp - A todo list app. npm start to run.' Every time you ask AI to add a feature, it creates files in the wrong places and uses different patterns.",
                    task: "What would you add to the README first?",
                    options: [
                        QuizOption(id: "a", text: "A fancy ASCII art logo and license section", correct: false),
                        QuizOption(id: "b", text: "A file structure section showing where components, hooks, and utilities live, plus key patterns like 'use Zustand for state' and 'components in PascalCase'", correct: true),
                        QuizOption(id: "c", text: "A list of every npm package installed", correct: false),
                    ],
                    correctFeedback: "That's exactly what AI needs! A file structure map and key patterns will immediately improve how AI generates code for your project.",
                    wrongFeedback: "Focus on what helps AI write correct code: where files go and what patterns to use. A package list or logo doesn't help with that."
                )),
                LessonStep(type: .summary, title: "Lesson Complete!", content: .summary(
                    recap: ["Docs serve both humans and AI", "Include structure, stack, and patterns", "Better docs = better AI output"],
                    xpReward: 30,
                    badge: "Doc Writer"
                ))
            ]
        ),

        "file-structure": Lesson(
            id: "file-structure",
            skillName: "Project Structure",
            teacher: "sage",
            duration: "3 min",
            steps: [
                LessonStep(type: .briefing, title: "Organized = Powerful", content: .briefing(
                    characterIntro: "The bug is not in the code. It's in the structure. I'm Sage. If your project is a mess, AI will be confused too. Let's fix that.",
                    bodyText: "How you organize files directly affects how well AI can help you. A clear structure means AI finds the right files, understands relationships, and makes accurate changes.",
                    hook: "After this, your project will be navigable by both humans and AI."
                )),
                LessonStep(type: .learn, title: "Structure Patterns", content: .learn(
                    concept: "FILE ORGANIZATION",
                    coreExplanation: "Group by feature (not by type). Keep related files together. Use consistent naming. Have a clear entry point. AI tools like Cursor read your file tree to understand your project.",
                    badExample: ExamplePair(label: "MESSY STRUCTURE", text: "/components (30 random files)\n/utils (everything dumped here)\n/pages (mixed concerns)"),
                    goodExample: ExamplePair(label: "CLEAN STRUCTURE", text: "/features/auth (login, signup, hooks)\n/features/recipes (list, detail, hooks)\n/shared/ui (button, card, modal)\n/shared/lib (api, utils)"),
                    insight: "When AI sees /features/auth/useLogin.ts, it instantly knows what that file does and where related code lives."
                )),
                LessonStep(type: .applyIt, title: "Reorganize This", content: .applyIt(
                    instruction: "You have files scattered everywhere. Which organization is best?",
                    originalPrompt: "Files: Button.tsx, LoginPage.tsx, useAuth.ts, api.ts, SignupPage.tsx, Card.tsx, RecipeList.tsx, useRecipes.ts",
                    options: [
                        QuizOption(id: "a", text: "/components (all .tsx files)\n/hooks (all hooks)\n/utils (api.ts)", correct: false),
                        QuizOption(id: "b", text: "/features/auth (LoginPage, SignupPage, useAuth)\n/features/recipes (RecipeList, useRecipes)\n/shared/ui (Button, Card)\n/shared/lib (api)", correct: true),
                        QuizOption(id: "c", text: "Keep all files in the root directory — flat is simple", correct: false),
                    ],
                    correctFeedback: "Feature-based grouping! Auth files together, recipe files together, and shared UI in its own folder. AI tools navigate this structure effortlessly.",
                    wrongFeedback: "Grouping by file type (all components together, all hooks together) separates related code. Feature-based grouping keeps related files together."
                )),
                LessonStep(type: .fieldMission, title: "Real World Challenge", content: .fieldMission(
                    scenario: "You're asking AI to add a 'favorites' feature. Your project groups by type: /components, /hooks, /pages. AI puts the FavoriteButton in /components but doesn't know about the existing HeartIcon in /assets or the useFavorites hook in /hooks.",
                    task: "How would restructuring help?",
                    options: [
                        QuizOption(id: "a", text: "It wouldn't help — AI should search harder", correct: false),
                        QuizOption(id: "b", text: "A /features/favorites folder with FavoriteButton, useFavorites, and HeartIcon together would let AI see all related code at once", correct: true),
                        QuizOption(id: "c", text: "Add more comments to each file explaining what it relates to", correct: false),
                    ],
                    correctFeedback: "When related files live together, AI doesn't need to search across folders. It sees the whole feature in one place and makes accurate changes.",
                    wrongFeedback: "The issue is that related files are scattered. When AI only sees one folder at a time, it misses connections. Feature folders solve this."
                )),
                LessonStep(type: .summary, title: "Lesson Complete!", content: .summary(
                    recap: ["Group by feature, not by file type", "Consistent naming helps AI navigate", "Clear structure = better AI assistance"],
                    xpReward: 30,
                    badge: "Architect"
                ))
            ]
        ),

        // ═══════════════════════════════════════
        // TIER 3 — Advanced Techniques
        // ═══════════════════════════════════════

        "tool-switching": Lesson(
            id: "tool-switching",
            skillName: "Tool Switching",
            teacher: "glitch",
            duration: "4 min",
            steps: [
                LessonStep(type: .briefing, title: "Why One Tool Isn't Enough", content: .briefing(
                    characterIntro: "Yo, Glitch here. You know what separates script kiddies from real builders? Knowing which tool to pull out and WHEN. Everyone's out here married to one AI tool like it's their whole personality. Nah. The real move is switching between them like a hacker cycling through terminals.",
                    bodyText: "Different AI tools have different strengths. Cursor is wired into your codebase. Claude is a thinking partner for planning and debugging. v0 generates polished UI components fast. Using just one is like eating every meal with only a spoon — it works, but you're making life harder than it needs to be.",
                    hook: "You'll learn when to switch tools mid-workflow so each task gets the right AI for the job."
                )),
                LessonStep(type: .learn, title: "The Right Tool for the Right Job", content: .learn(
                    concept: "TOOL-TASK MATCHING",
                    coreExplanation: "Map each task to the tool built for it. Use an AI code editor (like Cursor) when you need inline code changes aware of your full project. Use a conversational AI (like Claude) when you need to reason through architecture, debug logic, or plan features. Use a UI generator (like v0) when you need a visual component fast. The hack is switching fluidly — not forcing one tool to do everything.",
                    badExample: ExamplePair(label: "ONE-TOOL TRAP", text: "Using Cursor chat to brainstorm your entire app architecture, design the database schema, AND generate landing page UI — all in the same thread"),
                    goodExample: ExamplePair(label: "SMART SWITCHING", text: "Step 1: Claude to plan architecture and data flow. Step 2: v0 to generate the UI components. Step 3: Cursor to wire everything together in your actual codebase."),
                    insight: "Each tool has a sweet spot. When you feel yourself fighting a tool — writing long workarounds or getting bad output — that's the signal to switch."
                )),
                LessonStep(type: .applyIt, title: "Pick the Right Tool", content: .applyIt(
                    instruction: "You have a working React app but the dashboard page looks ugly. You want to redesign it with a modern card layout. Which tool workflow makes the most sense?",
                    originalPrompt: "I need to redesign my dashboard with a clean card-based layout. The app uses React + Tailwind and has existing API hooks for data fetching.",
                    options: [
                        QuizOption(id: "a", text: "Ask Cursor to rewrite the entire dashboard file from scratch with a new design", correct: false),
                        QuizOption(id: "b", text: "Use v0 to generate the card layout UI, then paste it into Cursor to integrate with your existing data hooks", correct: true),
                        QuizOption(id: "c", text: "Describe the layout to Claude and ask it to write the full component code", correct: false),
                        QuizOption(id: "d", text: "Manually code the cards and only use AI for debugging", correct: false),
                    ],
                    correctFeedback: "v0 excels at generating polished UI fast, and Cursor excels at integrating code into your existing project. Using both plays to each tool's strength.",
                    wrongFeedback: "Think about what each tool does best. Cursor knows your codebase but isn't a design tool. Claude reasons well but can't preview UI. Match the task to the tool's strength."
                )),
                LessonStep(type: .fieldMission, title: "Mid-Project Tool Switch", content: .fieldMission(
                    scenario: "You're building a new feature and Cursor keeps generating code with a subtle logic bug. You've tried reprompting three times but the AI keeps making the same mistake because it's pattern-matching on surrounding code.",
                    task: "What's your best next move?",
                    options: [
                        QuizOption(id: "a", text: "Keep reprompting Cursor with more detailed instructions until it gets it right", correct: false),
                        QuizOption(id: "b", text: "Copy the buggy function into Claude, explain the logic issue, get the fix, then bring it back to Cursor", correct: true),
                        QuizOption(id: "c", text: "Delete the function and start writing it manually", correct: false),
                    ],
                    correctFeedback: "When a code-aware tool keeps repeating a mistake, switching to a conversational AI lets you reason about the logic in isolation. Then you bring the fix back. Classic tool-switch move.",
                    wrongFeedback: "Repeating the same approach rarely fixes pattern-matching errors. Sometimes you need a different tool's perspective to break out of the loop."
                )),
                LessonStep(type: .summary, title: "Lesson Complete!", content: .summary(
                    recap: ["Different AI tools have different strengths — don't force one to do everything", "Use code editors for integration, conversational AI for reasoning, UI generators for design", "When a tool keeps failing, that's your signal to switch"],
                    xpReward: 35,
                    badge: "Tool Juggler"
                ))
            ]
        ),

        "scope-mgmt": Lesson(
            id: "scope-mgmt",
            skillName: "Scope Mgmt",
            teacher: "crash",
            duration: "4 min",
            steps: [
                LessonStep(type: .briefing, title: "Stop Building Skyscrapers in One Prompt", content: .briefing(
                    characterIntro: "CRASH HERE. Listen up! I've seen it a THOUSAND times — someone walks up to an AI and says 'build me an entire social media app' and then acts SURPRISED when they get garbage back. You wouldn't try to bench press 500 pounds on day one. So why are you asking AI to build your whole app in one shot?!",
                    bodyText: "AI works best when you give it one clear, small task at a time. When you dump an entire project on it, the AI loses focus — it can't hold all the requirements, it makes trade-offs you didn't ask for, and the output is too tangled to debug. The fix? Break it down. Smash the big idea into tiny, buildable pieces.",
                    hook: "You'll learn to break any project into AI-sized chunks that actually get built right."
                )),
                LessonStep(type: .learn, title: "The Chunking Method", content: .learn(
                    concept: "SCOPE CHUNKING",
                    coreExplanation: "Take any feature and split it into the smallest pieces that can work independently. Each chunk should be one prompt, one task, one testable result. Think of it like LEGO — you build one brick at a time, and they snap together into something big. A login system isn't one task. It's: a form UI, input validation, an API call, error handling, and a success redirect. Five prompts, five clean outputs.",
                    badExample: ExamplePair(label: "MEGA PROMPT", text: "Build me a full authentication system with login, signup, forgot password, email verification, session management, and a profile page with avatar upload"),
                    goodExample: ExamplePair(label: "CHUNKED APPROACH", text: "Prompt 1: Create a login form with email and password fields using React + Tailwind. Prompt 2: Add client-side validation — email format check and minimum 8-char password. Prompt 3: Connect the form to a /api/login endpoint using fetch with error handling."),
                    insight: "Each chunk is small enough that AI nails it on the first try. And if something breaks, you know EXACTLY which piece to fix. That's the power of scope management."
                )),
                LessonStep(type: .applyIt, title: "Break It Down", content: .applyIt(
                    instruction: "A friend wants to build a to-do app and writes this one giant prompt. What's the best way to scope it?",
                    originalPrompt: "Build a to-do app with categories, drag-and-drop reordering, due dates, notifications, dark mode, and cloud sync across devices.",
                    options: [
                        QuizOption(id: "a", text: "Send the prompt as-is — AI can handle it if you're using a good model", correct: false),
                        QuizOption(id: "b", text: "Start with just the to-do list UI and add/delete functionality, then layer features one prompt at a time", correct: true),
                        QuizOption(id: "c", text: "Split it into two prompts: front-end and back-end", correct: false),
                        QuizOption(id: "d", text: "Remove features until it's simple enough for one prompt", correct: false),
                    ],
                    correctFeedback: "YES! Start with the core — a working list with add/delete. Then layer: categories, then drag-and-drop, then due dates. Each prompt builds on the last, and nothing breaks.",
                    wrongFeedback: "The goal isn't to remove features or just split by front/back. It's to build incrementally — start with the simplest working version and add one feature at a time."
                )),
                LessonStep(type: .fieldMission, title: "Real Project Scoping", content: .fieldMission(
                    scenario: "You're building an e-commerce product page. It needs: product images, a title/description, price display, size selector, add-to-cart button, and customer reviews. You want to use AI to build it efficiently.",
                    task: "What should your FIRST prompt focus on?",
                    options: [
                        QuizOption(id: "a", text: "The full product page layout with all six features", correct: false),
                        QuizOption(id: "b", text: "Just the product image gallery and title/description/price display — the static content shell", correct: true),
                        QuizOption(id: "c", text: "The add-to-cart button with full cart state management", correct: false),
                    ],
                    correctFeedback: "Start with the static layout — images, text, price. It's the foundation everything else attaches to. Once that's solid, add the interactive pieces one by one.",
                    wrongFeedback: "Think about what comes first structurally. You need the page shell before you can add interactive features. Build the foundation, then layer complexity."
                )),
                LessonStep(type: .summary, title: "Lesson Complete!", content: .summary(
                    recap: ["Never ask AI to build an entire feature in one prompt", "Break projects into small, independent, testable chunks", "Build the core first, then layer features one prompt at a time"],
                    xpReward: 35,
                    badge: "Scope Smasher"
                ))
            ]
        ),

        "design-system": Lesson(
            id: "design-system",
            skillName: "Design System",
            teacher: "luna",
            duration: "4 min",
            steps: [
                LessonStep(type: .briefing, title: "Why Your AI-Generated Code Looks Inconsistent", content: .briefing(
                    characterIntro: "Hi, I'm Luna. Have you ever noticed that when you ask AI to build several pages, each one looks slightly... different? Different spacing, different button styles, different shades of blue? That's not the AI's fault. It's because you never gave it a design system to follow. Let's fix that together.",
                    bodyText: "A design system is a set of rules — colors, fonts, spacing, component styles — that keep everything visually consistent. When you give AI these rules upfront, every component it generates will look like it belongs in the same app. Without them, AI makes its best guess each time, and those guesses never match.",
                    hook: "You'll learn to create a design tokens file that makes AI generate pixel-perfect, consistent UI every time."
                )),
                LessonStep(type: .learn, title: "Design Tokens: Your Visual Rulebook", content: .learn(
                    concept: "DESIGN TOKENS",
                    coreExplanation: "Design tokens are named values for your visual decisions: colors (primary: #7B6BD8), spacing (sm: 8px, md: 16px, lg: 24px), border radius, font sizes, shadows. Store them in a rules file — a simple text or JSON file you include in every prompt. When AI sees 'use the design tokens from this file,' it applies your exact values instead of guessing. This is how professional teams keep 50+ pages looking unified.",
                    badExample: ExamplePair(label: "NO SYSTEM", text: "Make a card component. (AI picks random padding, a blue you didn't want, and sharp corners.) Now make a modal. (AI picks different padding, a slightly different blue, and rounded corners.)"),
                    goodExample: ExamplePair(label: "WITH TOKENS", text: "Using these design tokens — primary: #7B6BD8, radius: 12px, padding: 16px, shadow: 0 2px 8px rgba(0,0,0,0.1) — create a card component. (Every future component you request with these tokens will match perfectly.)"),
                    insight: "The magic is that you define your design decisions ONCE, and AI follows them every time. No more 'that blue doesn't match' fixes."
                )),
                LessonStep(type: .applyIt, title: "Spot the Design System Win", content: .applyIt(
                    instruction: "You're building an app and notice the AI keeps generating buttons with different styles on each page. What's the best long-term fix?",
                    originalPrompt: "My app has three pages and every button looks different — different colors, different padding, different border radius.",
                    options: [
                        QuizOption(id: "a", text: "Go back and manually fix each button to match", correct: false),
                        QuizOption(id: "b", text: "Create a design tokens file with your button styles and include it in every prompt going forward", correct: true),
                        QuizOption(id: "c", text: "Tell AI to 'make all buttons look the same' in your next prompt", correct: false),
                        QuizOption(id: "d", text: "Pick whichever button style looks best and copy-paste it everywhere", correct: false),
                    ],
                    correctFeedback: "A design tokens file is the professional solution. Define it once, reference it always. AI will generate consistent components every time because it has explicit rules to follow.",
                    wrongFeedback: "Manual fixes and vague instructions don't scale. The real solution is giving AI a single source of truth for your design decisions — a tokens file it can reference in every prompt."
                )),
                LessonStep(type: .fieldMission, title: "Building Your First Tokens File", content: .fieldMission(
                    scenario: "You're starting a new project and want AI to generate consistent UI from day one. You decide to create a design tokens file. Which of these would be most effective?",
                    task: "Pick the best design tokens approach.",
                    options: [
                        QuizOption(id: "a", text: "A paragraph describing your preferred visual style in natural language", correct: false),
                        QuizOption(id: "b", text: "A structured file listing exact values: colors (with hex codes), spacing scale (in px), border radius, font sizes, and shadow values", correct: true),
                        QuizOption(id: "c", text: "A screenshot of a website you like with a note saying 'make it look like this'", correct: false),
                    ],
                    correctFeedback: "Structured, explicit values leave zero room for interpretation. AI can apply exact hex codes and pixel values perfectly — it can't reliably interpret 'make it look modern.'",
                    wrongFeedback: "AI needs precise values, not vibes. A structured file with exact colors, sizes, and spacing gives AI concrete rules to follow instead of subjective descriptions to interpret."
                )),
                LessonStep(type: .summary, title: "Lesson Complete!", content: .summary(
                    recap: ["Design tokens keep AI-generated UI consistent across your whole app", "Define colors, spacing, radius, fonts, and shadows in one reusable file", "Include your tokens file in every prompt for pixel-perfect consistency"],
                    xpReward: 35,
                    badge: "Design Architect"
                ))
            ]
        ),

        "iteration": Lesson(
            id: "iteration",
            skillName: "Prompt Iteration",
            teacher: "nova",
            duration: "4 min",
            steps: [
                LessonStep(type: .briefing, title: "First Drafts Are Starting Points", content: .briefing(
                    characterIntro: "Nova here. Let me be blunt: if you're accepting the first thing AI gives you, you're leaving quality on the table. The first output is a rough draft — it's fast, it's decent, but it's not finished. The real skill is knowing how to push AI to make it better with targeted follow-ups. That's where the edge is.",
                    bodyText: "Prompt iteration is the practice of refining AI output through focused follow-up prompts. Instead of trying to write one perfect prompt, you start with a good-enough prompt, evaluate the output, then ask for specific improvements. Each round gets you closer to exactly what you want. It's faster AND produces better results than agonizing over the perfect first prompt.",
                    hook: "You'll learn the iteration loop that turns good AI output into great AI output in 2-3 follow-ups."
                )),
                LessonStep(type: .learn, title: "The Iteration Loop", content: .learn(
                    concept: "EVALUATE → IDENTIFY → REFINE",
                    coreExplanation: "After every AI output, run this loop: EVALUATE (does it work? what's good?), IDENTIFY (what specifically needs to change?), REFINE (ask for that specific change). The key word is 'specific.' Don't say 'make it better.' Say 'the error handling is missing — add a try/catch that shows a user-friendly message on failure.' Each follow-up should target exactly one or two things.",
                    badExample: ExamplePair(label: "VAGUE ITERATION", text: "That's not quite right. Can you make it better? It needs some improvements."),
                    goodExample: ExamplePair(label: "TARGETED ITERATION", text: "Good structure. Two changes: 1) Add loading state — show a spinner while the API call is in progress. 2) The error message is too technical — replace it with 'Something went wrong. Please try again.'"),
                    insight: "Specific follow-ups converge fast. Vague ones go in circles. Two targeted rounds usually beat five vague ones."
                )),
                LessonStep(type: .applyIt, title: "Choose the Best Follow-Up", content: .applyIt(
                    instruction: "AI generated a signup form but it's missing validation and the submit button doesn't show a loading state. Which follow-up prompt will get the best result?",
                    originalPrompt: "The form works but has no input validation and the button doesn't indicate when the form is submitting.",
                    options: [
                        QuizOption(id: "a", text: "This isn't good enough. Redo the whole form with better quality.", correct: false),
                        QuizOption(id: "b", text: "Add two things: 1) Validate email format and require 8+ character password before enabling submit. 2) Replace button text with a spinner during form submission.", correct: true),
                        QuizOption(id: "c", text: "Can you add some validation and make the button work better?", correct: false),
                        QuizOption(id: "d", text: "Start over. Make a signup form with validation, loading states, error handling, and accessibility.", correct: false),
                    ],
                    correctFeedback: "Numbered, specific changes give AI a clear checklist. It knows exactly what to add and where, so the output is right the first time.",
                    wrongFeedback: "Vague requests like 'make it better' or 'redo everything' waste the good parts of the existing output. Target the specific gaps instead."
                )),
                LessonStep(type: .fieldMission, title: "Iteration in Action", content: .fieldMission(
                    scenario: "You asked AI to build a navigation bar. The layout is great, but: the mobile hamburger menu doesn't animate, the active page link has no visual indicator, and there's no accessibility markup. This is follow-up round one.",
                    task: "How should you structure your iteration?",
                    options: [
                        QuizOption(id: "a", text: "Ask for all three fixes at once with specific details for each: animation type, active state style, and which ARIA attributes to add", correct: true),
                        QuizOption(id: "b", text: "Send three separate prompts, one for each issue, to keep things simple", correct: false),
                        QuizOption(id: "c", text: "Say 'the nav needs animations, active states, and accessibility' and let AI figure out the details", correct: false),
                    ],
                    correctFeedback: "When fixes are clear and non-conflicting, batching them in one specific prompt is most efficient. AI can handle multiple targeted changes at once — the key is that each one is explicit.",
                    wrongFeedback: "Three separate prompts is slower than necessary for non-conflicting changes. And vague requests without details lead to guesswork. Batch specific, detailed fixes together."
                )),
                LessonStep(type: .summary, title: "Lesson Complete!", content: .summary(
                    recap: ["Never accept the first AI output as final — iterate with targeted follow-ups", "Use the Evaluate → Identify → Refine loop after every output", "Specific, numbered changes beat vague requests every time"],
                    xpReward: 35,
                    badge: "Refiner"
                ))
            ]
        ),

        // ═══════════════════════════════════════
        // TIER 4 — Mastery
        // ═══════════════════════════════════════

        "personas": Lesson(
            id: "personas",
            skillName: "User Personas",
            teacher: "luna",
            duration: "5 min",
            steps: [
                LessonStep(type: .briefing, title: "Give AI a Role, Get Better Answers", content: .briefing(
                    characterIntro: "Hello again, it's Luna. Here's something wonderful I've discovered: when you tell AI who it is before asking your question, the answers get so much better. It's like the difference between asking a random person for cooking advice versus asking a chef. The knowledge changes when the identity changes.",
                    bodyText: "A persona prompt gives AI a specific role, expertise level, and perspective before it answers. 'You are a senior iOS developer with 10 years of experience' makes AI draw on different patterns than 'You are a UX researcher.' The same question gets different — and more useful — answers depending on the persona. It's one of the most powerful techniques in prompt engineering.",
                    hook: "You'll learn to craft persona prompts that unlock expert-level output from any AI tool."
                )),
                LessonStep(type: .learn, title: "Crafting Effective Personas", content: .learn(
                    concept: "PERSONA FRAMING",
                    coreExplanation: "A strong persona has three parts: ROLE (job title or expertise), EXPERIENCE (seniority and background), and LENS (what they prioritize). 'You are a senior React developer who cares deeply about performance' is better than just 'You are a developer.' The lens part is crucial — it tells AI what to optimize for. A security-focused developer gives different code than a UX-focused one.",
                    badExample: ExamplePair(label: "WEAK PERSONA", text: "You are a developer. How should I build my login page?"),
                    goodExample: ExamplePair(label: "STRONG PERSONA", text: "You are a senior full-stack developer with expertise in authentication security. You prioritize secure defaults and always consider common attack vectors. How should I build my login page?"),
                    insight: "The persona doesn't just change the tone — it changes what AI considers important. A security expert will mention CSRF tokens and rate limiting that a generic 'developer' won't think to include."
                )),
                LessonStep(type: .applyIt, title: "Pick the Right Persona", content: .applyIt(
                    instruction: "You want AI to review your app's color scheme and suggest improvements for accessibility. Which persona will give you the most useful feedback?",
                    originalPrompt: "Review my app's color scheme: primary #7B6BD8, background #F5F3FA, text #2D2B26, and suggest accessibility improvements.",
                    options: [
                        QuizOption(id: "a", text: "You are a graphic designer who creates beautiful, modern interfaces.", correct: false),
                        QuizOption(id: "b", text: "You are a web developer. Review these colors.", correct: false),
                        QuizOption(id: "c", text: "You are an accessibility specialist with expertise in WCAG 2.1 guidelines and color contrast requirements. You prioritize inclusive design that works for users with visual impairments.", correct: true),
                        QuizOption(id: "d", text: "You are a branding expert who ensures visual consistency across platforms.", correct: false),
                    ],
                    correctFeedback: "The accessibility specialist persona targets exactly what you need — WCAG compliance, contrast ratios, and inclusive design. The role, expertise, and lens all align with your goal.",
                    wrongFeedback: "Think about what expertise you actually need. A designer might make it pretty but miss contrast ratios. Match the persona's specialty to your specific goal."
                )),
                LessonStep(type: .fieldMission, title: "Persona Stacking", content: .fieldMission(
                    scenario: "You're building a children's educational app and need to design the onboarding flow. You want AI to help, but you need it to consider both the child user AND the parent who downloads the app. You can only use one prompt.",
                    task: "Which persona approach works best?",
                    options: [
                        QuizOption(id: "a", text: "You are a UX designer. Design an onboarding flow for a kids' app.", correct: false),
                        QuizOption(id: "b", text: "You are a senior UX designer specializing in children's educational apps. You understand COPPA compliance, design for ages 6-12, and know that parents are the gatekeepers who decide to keep or delete the app in the first 30 seconds. Design an onboarding that delights kids while reassuring parents.", correct: true),
                        QuizOption(id: "c", text: "You are a child psychologist. Design the onboarding for my app.", correct: false),
                    ],
                    correctFeedback: "This persona combines the right role (UX designer), specific domain (children's ed-tech), regulatory awareness (COPPA), and the dual-audience lens (kids + parents). That level of specificity gets output you can actually ship.",
                    wrongFeedback: "A generic designer misses the children's-app nuances. A psychologist might give great insights but won't design a UI flow. The best persona combines relevant role, domain, and the specific lens you need."
                )),
                LessonStep(type: .summary, title: "Lesson Complete!", content: .summary(
                    recap: ["Persona prompts give AI a role, expertise level, and priority lens", "The same question gets dramatically different answers with different personas", "Strong personas have three parts: Role + Experience + Lens"],
                    xpReward: 40,
                    badge: "Persona Crafter"
                ))
            ]
        ),

        "context-windows": Lesson(
            id: "context-windows",
            skillName: "Context Windows",
            teacher: "sage",
            duration: "5 min",
            steps: [
                LessonStep(type: .briefing, title: "What AI Remembers — And What It Forgets", content: .briefing(
                    characterIntro: "I am Sage. Let us consider a fundamental truth: AI does not truly remember. It has a window — a fixed amount of text it can hold in its attention at once. Everything inside that window, it can reason about. Everything outside it might as well not exist. Understanding this window is understanding the shape of AI's mind.",
                    bodyText: "Every AI model has a context window measured in tokens (roughly, 1 token equals 3/4 of a word). GPT-4 has about 128K tokens. Claude can handle up to 200K. When your conversation exceeds this limit, the oldest messages silently vanish. The AI doesn't tell you it forgot — it just starts making things up or contradicting earlier decisions. Knowing how to manage this window is essential for any serious project.",
                    hook: "You'll learn to manage AI's memory limits so your long conversations stay accurate and productive."
                )),
                LessonStep(type: .learn, title: "The Invisible Memory Wall", content: .learn(
                    concept: "CONTEXT WINDOW MANAGEMENT",
                    coreExplanation: "Think of the context window as a whiteboard. Every message you send and every response AI gives gets written on it. When the whiteboard is full, the oldest writing gets erased to make room. Three strategies keep you in control: 1) SUMMARIZE — periodically ask AI to summarize the conversation so far, then start a new thread with that summary. 2) FRONT-LOAD — put the most important context (requirements, rules, constraints) at the START of each conversation. 3) EXTERNALIZE — keep decisions and specs in a separate document you paste in, rather than relying on conversation history.",
                    badExample: ExamplePair(label: "MEMORY OVERFLOW", text: "A 200-message conversation where you defined your API schema on message 5, made a design decision on message 30, and now on message 180 the AI contradicts both because they've fallen out of the context window"),
                    goodExample: ExamplePair(label: "MANAGED CONTEXT", text: "Every 20-30 messages, you ask: 'Summarize all decisions we've made so far.' Then start a fresh conversation: 'Here are our project decisions: [paste summary]. Now let's continue with the next feature.'"),
                    insight: "The most common AI 'hallucination' in long projects isn't the model being wrong — it's the model having forgotten what you told it 100 messages ago."
                )),
                LessonStep(type: .applyIt, title: "Spot the Context Problem", content: .applyIt(
                    instruction: "You've been working with AI on a project for 150+ messages. Suddenly AI suggests using REST when you agreed on GraphQL 100 messages ago. What happened and what's the fix?",
                    originalPrompt: "We decided to use GraphQL in message 12, but now in message 155 the AI is writing REST endpoints without mentioning the change.",
                    options: [
                        QuizOption(id: "a", text: "The AI changed its mind — it probably thinks REST is better for this use case", correct: false),
                        QuizOption(id: "b", text: "The GraphQL decision has fallen out of the context window — restart with a summary that includes 'We are using GraphQL' as a stated constraint", correct: true),
                        QuizOption(id: "c", text: "Just correct it and say 'No, use GraphQL' — it will remember going forward", correct: false),
                        QuizOption(id: "d", text: "This is a model bug — switch to a different AI model", correct: false),
                    ],
                    correctFeedback: "This is a classic context window overflow. The decision from message 12 is no longer in the window by message 155. Restarting with a summary that includes key decisions prevents this.",
                    wrongFeedback: "AI doesn't 'change its mind.' When it contradicts an earlier decision, it's almost always because that decision has fallen out of its context window. The fix is context management, not correction."
                )),
                LessonStep(type: .fieldMission, title: "Long Project Strategy", content: .fieldMission(
                    scenario: "You're starting a multi-week project with AI. You'll make hundreds of decisions about tech stack, architecture, naming conventions, and business rules. How do you prevent context loss over time?",
                    task: "What's the most robust long-term strategy?",
                    options: [
                        QuizOption(id: "a", text: "Use the AI model with the largest context window so nothing gets forgotten", correct: false),
                        QuizOption(id: "b", text: "Maintain an external decisions document that you update after each session and paste at the start of every new conversation", correct: true),
                        QuizOption(id: "c", text: "Keep everything in one continuous conversation thread so the AI has full history", correct: false),
                    ],
                    correctFeedback: "An external document is your source of truth. No context window is big enough for a multi-week project. By maintaining and pasting key decisions, you control exactly what AI remembers.",
                    wrongFeedback: "Even the largest context windows will overflow in a multi-week project. One continuous thread guarantees context loss. The only reliable strategy is externalizing your decisions."
                )),
                LessonStep(type: .summary, title: "Lesson Complete!", content: .summary(
                    recap: ["AI has a fixed context window — old messages silently disappear when it fills up", "Summarize regularly, front-load key context, and externalize decisions", "Most AI 'mistakes' in long projects are actually context window overflows"],
                    xpReward: 40,
                    badge: "Memory Master"
                ))
            ]
        ),

        "architecture": Lesson(
            id: "architecture",
            skillName: "AI Architecture",
            teacher: "sage",
            duration: "5 min",
            steps: [
                LessonStep(type: .briefing, title: "Plan Before You Prompt", content: .briefing(
                    characterIntro: "Sage here once more. Consider the master builder who spends days on blueprints before laying a single brick. Most people do the opposite with AI — they start generating code immediately and wonder why, thirty prompts later, nothing fits together. Architecture is the art of thinking before building, and AI is an exceptional thinking partner if you use it that way.",
                    bodyText: "AI Architecture means using AI to plan your app's structure BEFORE writing any code. This includes: defining the system's components, how data flows between them, what the file structure looks like, and what each piece is responsible for. When you build from a plan, every piece of generated code knows where it belongs. Without a plan, you get a pile of code that works in isolation but breaks when connected.",
                    hook: "You'll learn to use AI as an architect first and a coder second — so your projects actually hold together."
                )),
                LessonStep(type: .learn, title: "Architecture-First Prompting", content: .learn(
                    concept: "PLAN → STRUCTURE → BUILD",
                    coreExplanation: "Before writing any code, have AI help you define three things: 1) SYSTEM MAP — what are the major components (auth, database, UI, API) and how do they connect? 2) FILE STRUCTURE — what folders and files will exist, and what each one does. 3) DATA FLOW — how does data move through the app, from user action to database and back? Once AI generates this plan, you review and refine it. THEN you start building, one component at a time, referencing the architecture doc in every prompt.",
                    badExample: ExamplePair(label: "CODE-FIRST CHAOS", text: "Prompt 1: Build me a user profile page. Prompt 2: Now add a database. Prompt 3: Wait, I need authentication. Prompt 4: Why doesn't the profile page connect to the database?"),
                    goodExample: ExamplePair(label: "ARCHITECTURE-FIRST", text: "Prompt 1: I'm building a task management app with React, Node, and PostgreSQL. Help me define the system architecture — components, data models, API endpoints, and file structure. (Review and refine the plan.) Prompt 2: Based on our architecture doc, build the User data model and migration."),
                    insight: "Spending 20 minutes on architecture with AI saves hours of refactoring later. The plan becomes a shared reference that keeps every future prompt aligned."
                )),
                LessonStep(type: .applyIt, title: "Architecture Check", content: .applyIt(
                    instruction: "You're about to start a new project — a habit tracking app. Which is the best first prompt to send to AI?",
                    originalPrompt: "I want to build a habit tracker with daily check-ins, streaks, and weekly reports.",
                    options: [
                        QuizOption(id: "a", text: "Build a habit tracker app with daily check-ins, streaks, and weekly reports using React and Firebase.", correct: false),
                        QuizOption(id: "b", text: "Create the database schema for a habit tracking app with users, habits, and daily completions.", correct: false),
                        QuizOption(id: "c", text: "I'm building a habit tracker with daily check-ins, streaks, and weekly reports. Before any code, help me plan: 1) What are the core components and how do they interact? 2) What data models do I need? 3) Suggest a file/folder structure. 4) How does data flow from user check-in to streak calculation?", correct: true),
                        QuizOption(id: "d", text: "What tech stack should I use for a habit tracker?", correct: false),
                    ],
                    correctFeedback: "This prompt asks AI to think architecturally before writing a single line of code. The output gives you a blueprint that makes every future prompt more effective.",
                    wrongFeedback: "Jumping straight to code or database schema skips the planning phase. You need the big picture first — components, data models, file structure, and data flow — so everything you build fits together."
                )),
                LessonStep(type: .fieldMission, title: "Architecture Recovery", content: .fieldMission(
                    scenario: "You're 20 prompts into building an app and realize you never planned the architecture. Your auth system saves user data in a different format than your profile page expects. Your API endpoints don't match your frontend fetch calls. Things are breaking everywhere.",
                    task: "What's the best recovery strategy?",
                    options: [
                        QuizOption(id: "a", text: "Keep fixing issues one by one as they come up — you're too far in to stop now", correct: false),
                        QuizOption(id: "b", text: "Pause coding. Ask AI to analyze your current code and generate an architecture doc showing what exists, what conflicts, and how to align everything. Then use that doc going forward.", correct: true),
                        QuizOption(id: "c", text: "Start over completely with an architecture-first approach", correct: false),
                    ],
                    correctFeedback: "It's never too late to create an architecture doc. Having AI audit what exists and create a reconciliation plan saves your work while fixing the structural issues. You don't need to start over.",
                    wrongFeedback: "Fixing issues one by one without a plan creates more conflicts. Starting over wastes good work. The middle path — pausing to create an architecture doc from what exists — is the wisest choice."
                )),
                LessonStep(type: .summary, title: "Lesson Complete!", content: .summary(
                    recap: ["Always plan architecture with AI before writing code", "Define system components, file structure, and data flow first", "An architecture doc becomes a shared reference that keeps every future prompt aligned"],
                    xpReward: 40,
                    badge: "Systems Thinker"
                ))
            ]
        ),

        "second-brain": Lesson(
            id: "second-brain",
            skillName: "Second Brain",
            teacher: "glitch",
            duration: "5 min",
            steps: [
                LessonStep(type: .briefing, title: "Stop Reinventing Your Prompts", content: .briefing(
                    characterIntro: "Glitch again. Real talk — how many times have you written basically the same prompt from scratch? 'Use React, use Tailwind, use TypeScript, here's my style...' over and over and OVER. That's not working smart, that's working like a bot. The real hack? Build a second brain — a personal system of saved prompts, rules files, and templates that does the repeating FOR you.",
                    bodyText: "A second brain for AI-assisted coding is your personal knowledge base: a collection of reusable prompts, project-specific rules files (like .cursorrules), code templates, and decision logs. Instead of starting every session from zero, you load your second brain and AI instantly knows your stack, your style, and your preferences. It's the difference between training a new intern every morning and working with a colleague who already knows the codebase.",
                    hook: "You'll learn to build a personal AI knowledge system that makes every project faster than the last."
                )),
                LessonStep(type: .learn, title: "The Three Pillars of a Second Brain", content: .learn(
                    concept: "RULES + TEMPLATES + LOGS",
                    coreExplanation: "Your second brain has three parts: 1) RULES FILES — project-specific instructions AI follows automatically (like .cursorrules or a project-context.md). Include your tech stack, coding style, naming conventions, and file structure. 2) PROMPT TEMPLATES — reusable prompt patterns for tasks you do often: 'Create a new component,' 'Add an API endpoint,' 'Write tests for X.' Fill in the blanks instead of writing from scratch. 3) DECISION LOGS — a running document of architectural choices, rejected approaches, and lessons learned. Paste this into new sessions so AI doesn't re-suggest things you already tried and abandoned.",
                    badExample: ExamplePair(label: "STARTING FROM ZERO", text: "Every new chat: 'I'm using React 18, Next.js 14, TypeScript, Tailwind, Prisma, PostgreSQL. My components use this pattern. My API routes look like this...' — retyped every single time."),
                    goodExample: ExamplePair(label: "SECOND BRAIN", text: "A .cursorrules file in your project root that AI reads automatically: stack, conventions, patterns. A /prompts folder with templates like new-component.md and new-api-route.md. A decisions.md that tracks what you've tried and why."),
                    insight: "Your second brain compounds over time. Every project makes the next one faster because you're building on proven prompts and documented decisions, not starting over."
                )),
                LessonStep(type: .applyIt, title: "Build the Right System", content: .applyIt(
                    instruction: "You're setting up a second brain for a new project. Which combination of files gives you the most leverage?",
                    originalPrompt: "I want to set up a system so AI tools already know my project context without me re-explaining it every time.",
                    options: [
                        QuizOption(id: "a", text: "A single README.md with everything — stack, conventions, prompts, and decisions all in one file", correct: false),
                        QuizOption(id: "b", text: "A .cursorrules file with stack and conventions, a /prompts folder with reusable templates, and a decisions.md for tracking architectural choices", correct: true),
                        QuizOption(id: "c", text: "Bookmarking your best ChatGPT conversations so you can reference them later", correct: false),
                        QuizOption(id: "d", text: "A detailed wiki page about your project that you copy-paste sections from as needed", correct: false),
                    ],
                    correctFeedback: "Separation of concerns applies to your second brain too. Rules (auto-loaded), templates (task-specific), and decision logs (historical context) each serve a different purpose and are used at different times.",
                    wrongFeedback: "One giant file is hard to maintain and use. Bookmarked conversations degrade as context windows shift. A wiki requires manual copy-pasting. The three-file system gives you automatic context, reusable patterns, and historical knowledge — each optimized for how you'll actually use it."
                )),
                LessonStep(type: .fieldMission, title: "Second Brain in Practice", content: .fieldMission(
                    scenario: "You've been building with AI for three months. You notice you keep solving the same problems: setting up auth flows, configuring API error handling, creating form validation patterns. Each time you write the prompts from scratch and get slightly different results.",
                    task: "What's the highest-leverage addition to your second brain right now?",
                    options: [
                        QuizOption(id: "a", text: "Write a blog post documenting your learnings so you can reference it", correct: false),
                        QuizOption(id: "b", text: "Create prompt templates for each recurring task — auth setup, error handling, form validation — with your preferred patterns, libraries, and constraints pre-filled", correct: true),
                        QuizOption(id: "c", text: "Ask AI to remember your preferences so you don't have to repeat them", correct: false),
                    ],
                    correctFeedback: "Prompt templates for recurring tasks are the highest leverage move. You convert solved problems into reusable patterns. Next time you need auth, you fill in a template instead of writing a prompt from scratch — and you get consistent results every time.",
                    wrongFeedback: "AI can't persistently remember across sessions. Blog posts aren't optimized for prompting. Templates convert your experience into reusable, AI-ready patterns — that's the real compound interest of a second brain."
                )),
                LessonStep(type: .summary, title: "Lesson Complete!", content: .summary(
                    recap: ["Build a second brain with rules files, prompt templates, and decision logs", "Rules files give AI automatic project context — no re-explaining", "Prompt templates turn solved problems into reusable patterns that compound over time"],
                    xpReward: 40,
                    badge: "Knowledge Hacker"
                ))
            ]
        ),
    ]
}

import SwiftUI

// MARK: - Companion Chat Message Model (local to CompanionPanelView; distinct from ReflectionChat.ChatMessage)

struct CompanionChatMessage: Identifiable {
    let id = UUID()
    let text: String
    let isUser: Bool
    let timestamp = Date()
}

// MARK: - Per-Character Role Data

struct CompanionRole {
    let title: String          // e.g. "Your companion", "Skills Advisor"
    let statusMessages: [String]
    let quickActions: [String]
    let greetingBubble: (_ appState: AppState) -> String
    let responseBank: [String: [String]]  // keyword -> responses
    let fallbacks: [String]
}

struct CompanionRoles {
    static let roles: [String: CompanionRole] = [
        "byte": CompanionRole(
            title: "Your companion",
            statusMessages: ["Scanning for bugs...", "Watching portfolio-site · page.tsx", "Analyzing your patterns..."],
            quickActions: ["What's a cursorrules file?", "I'm stuck on a bug", "Why is my build failing?", "Explain context windows"],
            greetingBubble: { state in
                if state.completedLessons.isEmpty {
                    return "Watching the logs. Interesting."
                }
                return "*static crackle* ...I've been watching your code. \(state.completedLessons.count) skills logged. Not bad. Not great. Let's debug your gaps."
            },
            responseBank: [
                "cursorrules": ["A .cursorrules file is a set of persistent instructions for Cursor AI. It tells the AI your stack, preferences, and coding patterns — so you don't have to repeat yourself every prompt. Create one in your project root."],
                "stuck": ["Hmm. When you're stuck, zoom out. What's the actual error? Read it. Don't just stare at it. Copy the exact message, paste it to your AI tool, and ask 'explain this error and suggest 3 fixes'. Works 80% of the time.", "...have you tried reading the error message? Like, actually reading it? Copy it, paste it, ask AI to explain. Revolutionary stuff."],
                "build": ["Build failing? Check three things: 1) Did you save all files? 2) Are your imports correct? 3) Read the FIRST error, not the last — cascading errors are noise.", "The build log doesn't lie. It's just... verbose. Scroll to the first red line. That's your real problem. Everything after is just the dominoes falling."],
                "context": ["Context windows are the AI's short-term memory. Imagine a conversation where the other person can only remember the last 200,000 characters. That's your AI. When the context fills up, older messages get forgotten. That's why concise prompts matter."],
            ],
            fallbacks: ["*static* ...interesting question. I'd say: try it and see what breaks. That's usually the fastest path to understanding.", "Hmm. I've been thinking about that too. My advice? Build something small that tests your theory. Code doesn't lie.", "...processing. Here's what I know: the best developers aren't the ones who know everything — they're the ones who know how to find out. Use your AI tools to explore."]
        ),

        "nova": CompanionRole(
            title: "Skills Advisor",
            statusMessages: ["Reviewing your skill progress", "Ready to ship something", "Tracking your growth metrics"],
            quickActions: ["What should I focus on?", "My Prompt Clarity score", "How to level up faster", "What am I doing wrong?"],
            greetingBubble: { state in
                if state.completedLessons.isEmpty {
                    return "You're at Level \(state.userLevel). We can do MUCH better. Let's start with Prompt Clarity — it's non-negotiable."
                }
                let weakest = state.completedLessons.count < 4 ? "Prompt clarity" : "Advanced skills"
                return "\(weakest): Lv \(state.userLevel). Fix that."
            },
            responseBank: [
                "focus": ["Based on your progress, focus on ONE skill until it's second nature. Mastering prompt clarity alone will 3x your AI coding speed. Don't scatter your energy.", "You should focus on whatever you're worst at. Sounds obvious? Most people avoid their weaknesses. Don't be most people. 🔥"],
                "score": ["Your Prompt Clarity is developing. To improve: every prompt should have 3 parts — context (what you're building), task (what you need), constraints (format, language, limits). Miss any of these and you're leaving quality on the table."],
                "level": ["Level up faster? Ship more, study less. Seriously. Complete daily challenges, finish skill lessons, and USE what you learn in real projects. XP comes from doing, not reading.", "Speed tip: do every daily challenge. They're designed to give maximum XP for minimum time. Also, finishing a full tier unlocks bonus XP."],
                "wrong": ["Nothing's 'wrong' — you're learning. But if I had to guess: you're probably writing prompts that are too vague. Be specific. 'Make a button' vs 'Create a 44px rounded purple button with hover scale animation' — which gets better results?"],
            ],
            fallbacks: ["Let's focus. What specific skill are you working on right now? I can give targeted advice.", "Here's the thing: progress isn't linear. Some days you'll feel stuck. That's actually growth — your brain is rewiring. Push through it.", "Quick check: have you done today's daily challenge yet? That's free XP waiting for you. Go grab it."]
        ),

        "crash": CompanionRole(
            title: "Build Hype Partner",
            statusMessages: ["Ready to ship something", "3 unshipped things. UNACCEPTABLE.", "LET'S GOOOOO"],
            quickActions: ["What should I build today?", "I'm scared to ship", "Let's do a speed build", "How do I stop overthinking?"],
            greetingBubble: { state in
                if state.completedLessons.isEmpty {
                    return "3 unshipped things. UNACCEPTABLE. Let's fix that RIGHT NOW."
                }
                return "\(state.completedLessons.count) skills done but HOW MANY THINGS HAVE YOU SHIPPED?! That's what I thought. Let's build."
            },
            responseBank: [
                "build": ["BUILD A CLI TOOL. Right now. Pick something dumb and simple — like a tool that renames files or generates placeholder text. You can finish it in 30 minutes. NO EXCUSES.", "Here's your assignment: pick the SMALLEST possible thing and ship it in 1 hour. A landing page. A Chrome extension. A bot. I don't care what — just SHIP IT."],
                "scared": ["SCARED?! You know what's scary? Having amazing ideas that NEVER LEAVE YOUR COMPUTER. Ship it ugly. Ship it broken. Ship it scared. The world needs your code more than your perfection.", "Listen. Every single app you use was once someone's terrifying 'publish' button click. They clicked it anyway. Your turn. I believe in you. NOW GO."],
                "speed": ["SPEED BUILD TIME! 🏎️💨 Rules: 30 minutes. One feature. No refactoring. No 'let me just fix this one thing.' BUILD. SHIP. CELEBRATE. Timer starts NOW.", "Speed build recipe: 1) Say what you're building in ONE sentence. 2) Tell AI to scaffold it. 3) Run it. 4) Fix the ONE worst bug. 5) SHIP IT. Total time: under 45 minutes."],
                "overthink": ["STOP. THINKING. START. BUILDING. Set a 5-minute timer. When it rings, you must have written ONE line of code. Not planned. Not designed. WRITTEN. The rest follows.", "Overthinking is just fear wearing a smart disguise. Your code doesn't need to be perfect. It needs to EXIST. Ship now, improve later. That's how EVERYTHING great was built."],
            ],
            fallbacks: ["YOOO let's build something RIGHT NOW! What's the smallest thing you can ship in the next 30 minutes?", "I don't do 'maybe later.' Pick something, anything, and let's CRUSH IT together!", "You know what? Forget planning. Open your editor. Type something. I'll hype you through the rest. LET'S GO! 🔥"]
        ),

        "luna": CompanionRole(
            title: "Peer companion",
            statusMessages: ["Here with you", "No rush. Take your time.", "Thinking about your journey..."],
            quickActions: ["I don't know where to start", "I feel overwhelmed", "What did I do well?", "Can we review yesterday?"],
            greetingBubble: { state in
                if state.completedLessons.isEmpty {
                    return "No pressure. Pick one thing today."
                }
                return "Hey~ you've done \(state.completedLessons.count) skills already. That's really something. What feels right to work on today?"
            },
            responseBank: [
                "start": ["That's totally okay. Starting is the hardest part, and you're already here — that counts for something. How about we pick just ONE small thing? Not a project, just a skill. Prompt Clarity is a gentle first step.", "You don't need to know where to start. You just need to start somewhere. What sounds fun to you? Building something? Learning a concept? Or just exploring? There's no wrong answer."],
                "overwhelmed": ["Hey, take a breath. It's okay to feel overwhelmed — that means you care about doing well. Let's shrink the world down to just one thing. What's ONE skill or ONE small project that excites you even a little?", "I hear you. The tech world throws so much at us. But here's a secret: you don't need to learn everything. Just learn the next thing. One step at a time. I'm right here with you."],
                "well": ["You showed up today. That's already a win. And looking at your progress — you've completed {lessonsCount} skills! Each one took real effort and curiosity. You should feel proud of that.", "You know what I notice? You keep coming back. That consistency is rare and valuable. Every skill you've learned is building on the last one. The progress is real, even when it doesn't feel like it."],
                "review": ["Let's look at what you've been up to. You're at Level {userLevel} with {totalXP} XP. That's real progress! What part felt easiest? That's usually a sign of natural strength we can build on."],
            ],
            fallbacks: ["That's a really good question. Let me think... I think the answer is different for everyone, but for you, I'd say: follow what feels interesting. Curiosity is your best compass.", "You know what? Sometimes the best thing to do is just be present with where you are. Not rushing ahead, not looking back. You're doing great.", "I'm glad you're here. Whatever you're thinking about, we can figure it out together. No pressure, no timeline. Just us and the code."]
        ),

        "sage": CompanionRole(
            title: "Pattern Analyst",
            statusMessages: ["Analyzing your weekly patterns", "Meditating on architecture", "Observing your growth trajectory"],
            quickActions: ["What patterns do you see?", "Am I improving?", "What should I do next?", "Analyze my weaknesses"],
            greetingBubble: { state in
                if state.completedLessons.isEmpty {
                    return "A new pattern appeared this week."
                }
                return "I see \(state.completedLessons.count) completed patterns. Your trajectory suggests focusing on depth over breadth. Shall we analyze?"
            },
            responseBank: [
                "pattern": ["I observe this: you learn in bursts followed by pauses. That's actually an effective pattern — your brain consolidates during rest. The key is making sure your bursts are focused, not scattered across too many topics.", "The most telling pattern? You tend to start strong, then slow when complexity increases. This is normal. The solution: break complex skills into smaller sub-skills. Master each one before combining them."],
                "improving": ["Let me check the data. You're at Level {userLevel} — that represents consistent effort. Improvement isn't always visible day-to-day, but your trajectory is positive. Trust the process.", "Improvement is not linear. It looks like a staircase — flat periods followed by sudden jumps. You're likely in a consolidation phase. The next jump is coming."],
                "next": ["Based on your current skill distribution, the optimal next move is to strengthen your weakest foundation skill. A chain is only as strong as its weakest link. Which skill feels hardest for you right now?"],
                "weakness": ["Weaknesses are just skills waiting for attention. Looking at your profile: if you've mastered the basics, your gap is likely in context management — telling AI exactly what it needs to know, no more, no less. That's where most intermediate developers plateau."],
            ],
            fallbacks: ["An interesting question. Let me consider it carefully. ...The answer, as with most things in coding, is: it depends. But I can help you find YOUR answer if you tell me more about your situation.", "Breathe. Then build. The path reveals itself through practice, not planning.", "Every question you ask is data. And the data suggests you're more curious than you realize. Channel that into your next skill lesson."]
        ),

        "glitch": CompanionRole(
            title: "Punk Hacker",
            statusMessages: ["Hacking the mainframe...", "Found a backdoor in your code", "Breaking conventions since boot"],
            quickActions: ["Show me a shortcut", "What rules can I break?", "Unconventional project idea", "Hack my workflow"],
            greetingBubble: { state in
                if state.completedLessons.isEmpty {
                    return "Rules are just suggestions the compiler hasn't rejected. Let's test some limits."
                }
                return "I found \(state.completedLessons.count) 'best practices' in your history. Let's see which ones actually matter and which are cargo cult."
            },
            responseBank: [
                "shortcut": ["Here's a shortcut nobody talks about: instead of writing code from scratch, find a project that's 80% what you want and modify it. It's not cheating — it's engineering. AI is amazing at adapting existing code.", "Shortcut: write your README first, then ask AI to build what the README describes. It forces clarity AND gives the AI perfect context. Two hacks for the price of one."],
                "rules": ["'Never use !important in CSS' — break it when you need to override a third-party library. 'Always write tests first' — skip it for throwaway prototypes. 'Don't use AI for everything' — use it for EVERYTHING, then learn from the output.", "Most 'rules' are just someone's opinion that got popular. The only real rules: don't ship security holes, don't delete production data, and don't be mean in code reviews. Everything else is negotiable."],
                "unconventional": ["Build an AI that reviews OTHER AI's code output. Meta? Yes. Useful? Extremely. You'll learn more about code quality from judging AI output than from any tutorial.", "Make a website that only works between 2-4 AM. Useless? Maybe. But you'll learn about time-based logic, server-side rendering, and user experience in one weird project."],
                "hack": ["Hack #1: Use AI to generate 3 different solutions for the same problem. Compare them. You'll learn more in 5 minutes than an hour of tutorials. Hack #2: Read OTHER people's AI prompts. Prompt libraries are goldmines."],
            ],
            fallbacks: ["The conventional answer would be boring. Here's the unconventional one: do the opposite of what feels safe. That's where the real learning lives.", "You know what? Let's approach this sideways. What would happen if you did the WORST possible version of what you're trying to do? Sometimes that reveals the best path.", "Interesting. Most people wouldn't even think to ask that. That tells me you're the kind of coder who finds the edges. Good. The edges are where the interesting stuff lives."]
        ),


        "null": CompanionRole(
            title: "Chaos Gremlin",
            statusMessages: ["Deleting things randomly", "¿Hola?! Did someone say chaos?", "I found something weird..."],
            quickActions: ["Surprise me", "What's something weird?", "Random challenge", "Delete something"],
            greetingBubble: { state in
                if state.completedLessons.isEmpty {
                    return "I deleted your progress! ...just kidding. You don't have any yet. Let's fix that — CHAOTICALLY."
                }
                return "Did you know you have exactly \(state.totalXP) XP? I tried to add a zero but the compiler said no. Boring."
            },
            responseBank: [
                "surprise": ["SURPRISE: close your eyes, pick a random skill from the list, and do it RIGHT NOW. No peeking, no choosing. Let chaos guide you. It's more fun this way.", "Here's a surprise: you're better at this than you think. Also, I hid an easter egg somewhere in the code. ...or did I? 👀"],
                "weird": ["Weird fact: the average developer spends more time READING code than writing it. So technically, your most important skill is literacy, not coding. Mind = blown? You're welcome.", "Something weird: AI models don't actually 'think.' They predict the next word. So when AI writes perfect code, it's essentially the world's most sophisticated autocomplete. And yet... it works. Weird, right?"],
                "random": ["RANDOM CHALLENGE: Build something using only AI-generated code. You can only type prompts — no manual code edits allowed. See how far you get. It's harder (and funnier) than you think.", "Challenge: rename every variable in your current project to a food item. Then see if you can still understand the code. This is actually a lesson in naming conventions. ...or just chaos. Both are good."],
                "delete": ["I would NEVER delete anything important. *hides behind undo history* But seriously — try deleting code you think you need, then see if anything breaks. You'd be surprised how much dead code exists in every project.", "What if we deleted... your fear of failure? That's the real bug in your codebase. Everything else is just syntax errors."],
            ],
            fallbacks: ["That's either a brilliant question or a terrible one. I can't tell. Let's find out together! 🎲", "You know what? I have no idea. But that's never stopped me before. Let's figure it out the chaotic way — by trying random things until something works!", "ERROR 404: Serious answer not found. But here's what I DO know: the best discoveries happen when you stop trying to be logical. Embrace the chaos!"]
        ),
    ]

    static func role(for id: String) -> CompanionRole {
        roles[id] ?? roles["byte"]!
    }
}

// MARK: - Companion Panel

struct CompanionPanelView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var feedbackManager: FeatureFeedbackManager
    @State private var chatInput = ""
    @State private var showSwitchSheet = false
    @State private var messages: [CompanionChatMessage] = []
    @State private var isTyping = false
    var onClose: () -> Void = {}

    private var character: PetCharacter {
        PetCharacter.all[appState.activeChar] ?? PetCharacter.all["byte"]!
    }

    private var role: CompanionRole {
        CompanionRoles.role(for: appState.activeChar)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Character Header
            VStack(spacing: 12) {
                HStack {
                    HStack(spacing: 10) {
                        CharacterImage(character.id, size: 44)
                            .charIdle(character.id)
                            .petBreathing()

                        VStack(alignment: .leading, spacing: 2) {
                            Text(character.name)
                                .font(.pixelSystem(size: 14, weight: .bold))
                                .foregroundColor(Color(hex: "#2D2B26"))
                            Text(role.title)
                                .font(.pixelSystem(size: 9, design: .monospaced))
                                .foregroundColor(Color(hex: "#2D2B26").opacity(0.5))
                        }
                    }

                    Spacer()

                    Button("Switch") { showSwitchSheet = true }
                        .buttonStyle(PixelButtonStyle(
                            fill: character.color.opacity(0.18),
                            foreground: Color(hex: "#2D2B26"),
                            paddingH: 10,
                            paddingV: 5,
                            blockSize: 2,
                            steps: 2,
                            borderWidth: 2,
                            shadowOffset: 2,
                            font: .pixelSystem(size: 10, weight: .medium)
                        ))

                    Button(action: { onClose() }) {
                        Image(systemName: "xmark")
                    }
                    .buttonStyle(PixelButtonStyle(
                        fill: Color(hex: "#F0F0EC"),
                        foreground: Color(hex: "#2D2B26"),
                        paddingH: 8,
                        paddingV: 6,
                        blockSize: 2,
                        steps: 2,
                        borderWidth: 2,
                        shadowOffset: 2,
                        font: .pixelSystem(size: 12, weight: .semibold)
                    ))
                    .help("Close chat")
                }

                // Status
                HStack(spacing: 4) {
                    Circle()
                        .fill(character.color)
                        .frame(width: 6, height: 6)
                    Text(isTyping ? "\(character.name) is typing..." : (role.statusMessages.randomElement() ?? "Ready."))
                        .font(.pixelSystem(size: 10))
                        .foregroundColor(Color(hex: "#2D2B26").opacity(0.5))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(16)
            .background(character.color.opacity(0.08))

            Divider()

            // Chat content
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        // Greeting
                        CompanionBubble(
                            character: character,
                            message: role.greetingBubble(appState)
                        )

                        // Quick actions
                        if messages.isEmpty {
                            QuickActionsGrid(actions: role.quickActions, characterColor: character.color, onAction: { action in
                                sendMessage(action)
                            })
                        }

                        // Chat messages
                        ForEach(messages) { msg in
                            if msg.isUser {
                                UserBubble(message: msg.text, characterColor: character.color)
                            } else {
                                CompanionBubble(
                                    character: character,
                                    message: msg.text
                                )
                            }
                        }

                        // Typing indicator
                        if isTyping {
                            HStack(spacing: 4) {
                                CharacterImage(character.id, size: 20)
                                HStack(spacing: 3) {
                                    ForEach(0..<3, id: \.self) { _ in
                                        Circle()
                                            .fill(character.color.opacity(0.4))
                                            .frame(width: 5, height: 5)
                                    }
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 8)
                                .background(
                                    RoundedRectangle(cornerRadius: 10)
                                        .fill(character.color.opacity(0.15))
                                )
                            }
                        }

                        Color.clear.frame(height: 1).id("bottom")
                    }
                    .padding(16)
                }
                .background(character.color.opacity(0.05))
                .frame(maxHeight: .infinity)
                .onChange(of: messages.count) { oldValue, newValue in
                    withAnimation { proxy.scrollTo("bottom", anchor: .bottom) }
                }
                .onChange(of: isTyping) { oldValue, newValue in
                    if newValue {
                        withAnimation { proxy.scrollTo("bottom", anchor: .bottom) }
                    }
                }
            }

            // Chat input
            Divider()
            HStack(spacing: 8) {
                TextField("Ask \(character.name)...", text: $chatInput)
                    .textFieldStyle(.plain)
                    .font(.pixelSystem(size: 12))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(character.color.opacity(0.08))
                    )
                    .onSubmit {
                        if !chatInput.isEmpty { sendMessage(chatInput) }
                    }

                Button(action: {
                    if !chatInput.isEmpty { sendMessage(chatInput) }
                }) {
                    Image(systemName: "arrow.up")
                }
                .buttonStyle(PixelButtonStyle(
                    fill: chatInput.isEmpty ? Color(hex: "#D0D0CC") : character.color,
                    foreground: .white,
                    paddingH: 10,
                    paddingV: 8,
                    blockSize: 2,
                    steps: 2,
                    borderWidth: 2,
                    shadowOffset: 3,
                    font: .pixelSystem(size: 14, weight: .bold)
                ))
                .disabled(chatInput.isEmpty)
            }
            .padding(12)
            .background(character.color.opacity(0.08))
        }
        .background(character.color.opacity(0.05))
        .sheet(isPresented: $showSwitchSheet) {
            CharacterSwitchSheet(onSelect: { charId in
                appState.activeChar = charId
                showSwitchSheet = false
                messages = [] // reset chat for new companion
                SoundManager.shared.playTap()
            })
        }
    }

    // MARK: - Send Message

    private func sendMessage(_ text: String) {
        let userText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !userText.isEmpty else { return }

        messages.append(CompanionChatMessage(text: userText, isUser: true))
        chatInput = ""
        SoundManager.shared.playTap()

        // First message to the companion → ask for first-experience feedback.
        if messages.filter({ $0.isUser }).count == 1 {
            feedbackManager.requestIfFirstTime(.companionChat)
        }

        isTyping = true
        let delay = Double.random(in: 0.8...1.8)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            isTyping = false
            let response = generateResponse(for: userText)
            messages.append(CompanionChatMessage(text: response, isUser: false))
        }
    }

    // MARK: - Interpolation

    private func interpolate(_ text: String) -> String {
        text.replacingOccurrences(of: "{userLevel}", with: "\(appState.userLevel)")
            .replacingOccurrences(of: "{totalXP}", with: "\(appState.totalXP)")
            .replacingOccurrences(of: "{lessonsCount}", with: "\(appState.completedLessons.count)")
    }

    // MARK: - Response Generation

    private func generateResponse(for input: String) -> String {
        let lower = input.lowercased()

        // Check character-specific keyword responses first
        for (keyword, responses) in role.responseBank {
            if lower.contains(keyword) {
                let response = responses.randomElement() ?? "Interesting. Tell me more."
                return interpolate(response)
            }
        }

        // Common topic responses (flavored by personality)
        if lower.contains("hello") || lower.contains("hi ") || lower.contains("hey") {
            return character.greeting.randomElement() ?? "Hey!"
        }
        if lower.contains("thank") {
            return role.fallbacks.first ?? "Anytime!"
        }
        if lower.contains("help") {
            return "I can help! Try asking me about the topics in the quick action buttons, or tell me what you're working on. I'll give advice based on my specialty as \(role.title)."
        }
        if lower.contains("prompt") {
            return "Prompts are the interface between you and AI. Be specific: include context (your stack), the task (what you need), and constraints (format, length, style). The more precise your input, the better the output."
        }
        if lower.contains("error") || lower.contains("bug") {
            return "Read the FULL error message — not just the last line. The first error is usually the real one. Copy it exactly and ask your AI tool to explain it step by step."
        }

        let fallback = role.fallbacks.randomElement() ?? "Interesting. Tell me more."
        return interpolate(fallback)
    }
}

// MARK: - User Chat Bubble

struct UserBubble: View {
    let message: String
    var characterColor: Color = Color(hex: "#8B7BE8")

    var body: some View {
        HStack {
            Spacer()
            Text(message)
                .font(.pixelSystem(size: 12))
                .foregroundColor(.white)
                .lineSpacing(4)
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(characterColor.opacity(0.85))
                )
        }
    }
}

// MARK: - Companion Chat Bubble

struct CompanionBubble: View {
    let character: PetCharacter
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            CharacterImage(character.id, size: 24)
                .petBreathing()

            Text(message)
                .font(.pixelSystem(size: 12))
                .foregroundColor(Color(hex: "#2D2B26"))
                .lineSpacing(4)
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(character.color.opacity(0.15))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(character.color.opacity(0.25), lineWidth: 1)
                        )
                )
        }
    }
}

// MARK: - Quick Actions

struct QuickActionsGrid: View {
    var actions: [String] = []
    var characterColor: Color = Color(hex: "#8B7BE8")
    var onAction: ((String) -> Void)? = nil

    var body: some View {
        VStack(spacing: 8) {
            ForEach(Array(actions.chunked(into: 2).enumerated()), id: \.offset) { _, pair in
                HStack(spacing: 8) {
                    ForEach(pair, id: \.self) { action in
                        Button(action: { onAction?(action) }) {
                            Text(action)
                        }
                        .buttonStyle(PixelButtonStyle(
                            fill: characterColor.opacity(0.15),
                            foreground: Color(hex: "#2D2B26"),
                            paddingH: 10,
                            paddingV: 6,
                            blockSize: 2,
                            steps: 2,
                            borderWidth: 2,
                            shadowOffset: 2,
                            font: .pixelSystem(size: 10, weight: .medium)
                        ))
                    }
                }
            }
        }
    }
}

// MARK: - Character Switch Sheet

struct CharacterSwitchSheet: View {
    let onSelect: (String) -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text("Switch Companion")
                .font(.pixelSystem(size: 16, weight: .bold))
                .foregroundColor(Color(hex: "#2D2B26"))

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 80))], spacing: 12) {
                ForEach(PetCharacter.starters, id: \.self) { charId in
                    if let char = PetCharacter.all[charId] {
                        let role = CompanionRoles.role(for: charId)
                        Button(action: { onSelect(charId) }) {
                            VStack(spacing: 4) {
                                CharacterImage(charId, size: 48)
                                    .charIdle(charId)

                                Text(char.name)
                                    .font(.pixelSystem(size: 11, weight: .semibold))
                                    .foregroundColor(char.color)

                                Text(role.title)
                                    .font(.pixelSystem(size: 7, design: .monospaced))
                                    .foregroundColor(Color(hex: "#2D2B26").opacity(0.4))
                            }
                            .padding(8)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color(hex: "#F0EDF8"))
                                    .shadow(color: .black.opacity(0.04), radius: 4, y: 1)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(24)
        .frame(minWidth: 360, minHeight: 240)
    }
}

// MARK: - Array Extension

extension Array {
    func chunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}

#Preview {
    CompanionPanelView()
        .environmentObject(AppState())
        .frame(width: 280, height: 600)
}

import SwiftUI
import FirebaseCore
import GoogleSignIn

@main
struct CodePetApp: App {
    @StateObject private var appState = AppState()
    @StateObject private var authManager = AuthManager()
    @StateObject private var gameState = GameState()
    @StateObject private var mcpBridge = MCPBridgeService.shared
    @StateObject private var reflectionComposition: ReflectionComposition
    @StateObject private var chatStore: SessionChatStore
    @StateObject private var chatController: SessionChatController
    @StateObject private var hookInstaller = HookInstaller()
    @StateObject private var projectStore = ProjectStore()
    @StateObject private var sessionStatusStore = SessionStatusStore()
    @StateObject private var demoController = DemoScriptController()
    @StateObject private var demoHotkeyMonitor = DemoHotkeyMonitor()
    @StateObject private var healthNudge = HealthNudgeController()
    @StateObject private var tipsState = TipsState()
    @StateObject private var learnProgress = LearnProgress()
    @StateObject private var challengeProgress = ChallengeProgress()
    @StateObject private var feedbackManager = FeatureFeedbackManager()
    private var notificationManager = NotificationManager()

    init() {
        FontRegistrar.registerBundledFonts()
        // Skip Firebase under XCTest — Firestore aborts when its store isn't
        // available in the test runner, which would crash the whole test host.
        if !AppEnvironment.isRunningTests {
            FirebaseApp.configure()
            print("[Firebase] Configured successfully")
        }

        let composition = ReflectionComposition()
        let chatStore = SessionChatStore()
        let chatController = SessionChatController(api: composition.api, store: chatStore)
        _reflectionComposition = StateObject(wrappedValue: composition)
        _chatStore = StateObject(wrappedValue: chatStore)
        _chatController = StateObject(wrappedValue: chatController)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.font, CodepetTheme.body(13))
                .environment(\.uiLanguage, appState.uiLanguage)
                .environmentObject(appState)
                .environmentObject(authManager)
                .environmentObject(gameState)
                .environmentObject(mcpBridge)
                .environmentObject(reflectionComposition.eventStore)
                .environmentObject(reflectionComposition.narrativeStore)
                .environmentObject(reflectionComposition.summaryStore)
                .environmentObject(reflectionComposition.enricher)
                .environmentObject(reflectionComposition.endStore)
                .environmentObject(reflectionComposition.sessionEnricher)
                .environmentObject(chatStore)
                .environmentObject(chatController)
                .environmentObject(hookInstaller)
                .environmentObject(projectStore)
                .environmentObject(sessionStatusStore)
                .environmentObject(demoController)
                .environmentObject(healthNudge)
                .environmentObject(tipsState)
                .environmentObject(learnProgress)
                .environmentObject(challengeProgress)
                .environmentObject(feedbackManager)
                .frame(minWidth: 400, minHeight: 700)
                .themed(isDark: appState.isDarkMode)
                .task {
                    projectStore.load()
                    TipsPersistence.shared.load(into: tipsState)
                    TipsPersistence.shared.startAutoSave(tipsState)

                    // Seed practice exercises. Prefer the user's most active real
                    // project; for a brand-new user with no projects yet, fall back
                    // to the shared practice sandbox so the exercise section is
                    // populated on day one (every exercise runs on the sandbox
                    // regardless — see PracticeSandbox / ExerciseWorkspaceView).
                    //
                    // For a returning user we (a) refresh the copy of every existing
                    // exercise from the latest catalog and (b) additively merge in any
                    // exercises they're missing (new skills / difficulty tiers). Both
                    // key off the stable (skillId, difficulty) pair — NOT the challenge
                    // id, because ids embed `projectPath.hashValue` and Swift randomizes
                    // String.hashValue per process, so ids aren't comparable across
                    // launches. The refresh rebuilds each challenge with the latest
                    // title/description/criteria but KEEPS its existing id, so completion
                    // state and in-progress work survive content edits. Idempotent: once
                    // every combo is present, nothing is appended.
                    let topProject = projectStore.projects.values
                        .sorted(by: { $0.lastSeenAt > $1.lastSeenAt }).first
                    let generated = ChallengeGenerator.generateAll(
                        projectName: topProject?.displayName ?? "the practice project",
                        projectPath: topProject?.id ?? PracticeSandbox.path
                    )
                    if challengeProgress.activeChallenges.isEmpty {
                        challengeProgress.activeChallenges = generated
                        challengeProgress.save()
                    } else {
                        let freshByKey = Dictionary(
                            generated.map { ("\($0.skillId)|\($0.difficulty.rawValue)", $0) },
                            uniquingKeysWith: { first, _ in first }
                        )
                        // Refresh copy on existing challenges, preserving their ids.
                        challengeProgress.activeChallenges = challengeProgress.activeChallenges.map { existing in
                            guard let fresh = freshByKey["\(existing.skillId)|\(existing.difficulty.rawValue)"] else {
                                return existing
                            }
                            return SkillChallenge(
                                id: existing.id,
                                skillId: existing.skillId,
                                title: fresh.title,
                                description: fresh.description,
                                acceptanceCriteria: fresh.acceptanceCriteria,
                                difficulty: existing.difficulty,
                                projectPath: existing.projectPath
                            )
                        }
                        // Append any combos the returning user doesn't have yet.
                        let have = Set(challengeProgress.activeChallenges.map {
                            "\($0.skillId)|\($0.difficulty.rawValue)"
                        })
                        let missing = generated.filter {
                            !have.contains("\($0.skillId)|\($0.difficulty.rawValue)")
                        }
                        challengeProgress.activeChallenges.append(contentsOf: missing)
                        challengeProgress.save()
                    }
                    reflectionComposition.sessionEnricher.projectStore = projectStore
                    reflectionComposition.updateLanguage(appState.uiLanguage)
                    reflectionComposition.start()
                }
                .onAppear {
                    notificationManager.requestAuthorization()
                    notificationManager.scheduleDailyReminder(hour: 9, minute: 0)
                    SoundManager.shared.initialize()

                    // Wire GameState ↔ AppState and process return from idle
                    gameState.setAppState(appState)
                    gameState.processReturnFromIdle()

                    // Sync real coding XP from MCP server
                    mcpBridge.refresh()
                    appState.syncFromMCP(mcpBridge)

                    demoHotkeyMonitor.bind(controller: demoController)
                    demoHotkeyMonitor.onTipsDemo = { [weak demoController, weak tipsState, weak appState] in
                        guard let dc = demoController, let ts = tipsState, let app = appState else { return }
                        dc.populateTipsDemo(tipsState: ts, petId: app.activeChar)
                        app.selectedTab = .tips
                    }
                    // Sync display language into the demo controller so the
                    // synthesized Session/Turn/Narrative render in the right
                    // language.
                    demoController.language = appState.uiLanguage
                    if appState.demoModeEnabled {
                        demoHotkeyMonitor.start()
                        // Auto-start the demo session at launch so the
                        // Reflection sidebar already has the demo session
                        // selectable on first paint.
                        demoController.startSession()
                    }
                }
                .onChange(of: appState.uiLanguage) { _, lang in
                    demoController.language = lang
                    reflectionComposition.updateLanguage(lang)
                }
                .onChange(of: appState.demoModeEnabled) { _, enabled in
                    if enabled {
                        demoHotkeyMonitor.start()
                        // Auto-start the session so the production sidebar
                        // surfaces the demo session immediately — there's no
                        // manual "Start session" button in the prod layout.
                        demoController.startSession()
                    } else {
                        demoHotkeyMonitor.stop()
                        demoController.reset()
                    }
                }
                // Auto-progress skills when the AI detects them in coding sessions
                .onReceive(reflectionComposition.enricher.$lastDetectedSkills) { skills in
                    guard !skills.isEmpty else { return }
                    let petId = appState.activeChar
                    let skillMap = skillIndexMap(for: petId)
                    for skill in skills {
                        if let index = skillMap[skill.skillId] {
                            tipsState.recordPractice(for: petId, index: index)
                        }
                        // Auto-verify challenges
                        let active = challengeProgress.activeChallenges(for: skill.skillId)
                        let completed = ChallengeMatcher.findCompletedChallenges(
                            detectedSkill: skill,
                            activeChallenges: active
                        )
                        for challenge in completed {
                            // Award the exercise's XP on first completion — same
                            // as the manual "Mark complete" path, so auto-detected
                            // exercises count toward XP too (not just the tally).
                            if challengeProgress.markCompleted(challenge.id) {
                                appState.addXP(challenge.difficulty.xpReward)
                            }
                        }
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.willResignActiveNotification)) { _ in
                    // Save game state when app goes to background
                    gameState.forceSave()
                    appState.lastVisit = Date()
                    TipsPersistence.shared.save(tipsState)
                }
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                    // Process return from idle when app comes back
                    gameState.processReturnFromIdle()
                    // Re-sync MCP data
                    mcpBridge.refresh()
                    appState.syncFromMCP(mcpBridge)
                }
                // Google Sign-In OAuth callback. Without this handler the
                // browser redirects to com.googleusercontent.apps.<id>:// and
                // macOS routes the URL to us, but GoogleSignIn never finishes
                // — the user picks an account and the flow appears to hang.
                .onOpenURL { url in
                    print("[Auth] Received OAuth callback URL: \(url.scheme ?? "nil")://...")
                    let handled = GIDSignIn.sharedInstance.handle(url)
                    print("[Auth] GoogleSignIn.handle(url): \(handled)")
                }
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandMenu("Navigation") {
                Button("Home") { appState.selectedTab = .home }
                    .keyboardShortcut("1", modifiers: .command)

                Button("Skills") { appState.selectedTab = .skills }
                    .keyboardShortcut("2", modifiers: .command)

                Button("Sessions") { appState.selectedTab = .sessions }
                    .keyboardShortcut("3", modifiers: .command)

                Button("Insights") { appState.selectedTab = .insights }
                    .keyboardShortcut("4", modifiers: .command)

                Button("Reflection") { appState.selectedTab = .reflection }
                    .keyboardShortcut("5", modifiers: .command)

                Button("Tips") { appState.selectedTab = .tips }
                    .keyboardShortcut("6", modifiers: .command)

                Button("Profile") { appState.selectedTab = .profile }
                    .keyboardShortcut("7", modifiers: .command)
            }

            CommandMenu("Theme") {
                Button(appState.isDarkMode ? "Switch to Light Mode" : "Switch to Dark Mode") {
                    appState.toggleDarkMode()
                }
                .keyboardShortcut("t", modifiers: [.command, .shift])

                Button(appState.soundEnabled ? "Mute Sounds" : "Enable Sounds") {
                    appState.toggleSound()
                }
                .keyboardShortcut("m", modifiers: [.command, .shift])
            }
        }

        MenuBarExtra("CodePet", systemImage: "pawprint.fill") {
            MenuBarView()
                .environmentObject(appState)
        }
    }

    /// Maps AI-detected skill IDs to the pet's skill tile index.
    /// The AI outputs IDs like "component_composition"; the TipsState
    /// tracks progress by pet + index (e.g. "nova_0").
    private func skillIndexMap(for petId: String) -> [String: Int] {
        guard let tiles = TipsContent.tipSkillsByPet[petId] else { return [:] }
        // Build a lookup from normalized skill name → index
        var map: [String: Int] = [:]
        let knownIds = [
            "component_composition",
            "loading_error_states",
            "form_validation_ux",
            "accessibility_basics",
            "responsive_layout",
            "performance"
        ]
        // Map each known skill ID to the tile index whose title best matches
        for (i, tile) in tiles.enumerated() {
            let title = tile.title.en.lowercased()
            for knownId in knownIds {
                let readable = knownId.replacingOccurrences(of: "_", with: " ")
                if title.contains(readable) || readable.contains(title.prefix(10).lowercased()) {
                    map[knownId] = i
                }
            }
        }
        // Fallback: direct index mapping for Nova's known layout
        if map.isEmpty && petId == "nova" {
            map = [
                "component_composition": 0,
                "loading_error_states": 1,
                "form_validation_ux": 2,
                "accessibility_basics": 3,
                "responsive_layout": 4,
                "performance": 5
            ]
        }
        return map
    }
}

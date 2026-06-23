import SwiftUI

struct MainTabView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var gameState: GameState
    @EnvironmentObject var challengeProgress: ChallengeProgress
    @EnvironmentObject var authManager: AuthManager
    @EnvironmentObject var tipsState: TipsState
    @EnvironmentObject var feedbackManager: FeatureFeedbackManager
    @State private var showChat = false
    @State private var didSetLaunchTab = false
    // Baselines for first-experience feedback triggers — an increase past these
    // means a feature was just finished, so we fire its one-time feedback toast.
    @State private var lastExerciseCount = 0
    @State private var lastLessonCount = 0
    @State private var lastMasteredCount = 0

    /// Skills mastered across all pets (global, so switching pets doesn't look
    /// like a new mastery).
    private var masteredSkillCount: Int {
        tipsState.skillProgress.values.filter { $0.isMastered }.count
    }
    @AppStorage("cp_lastStreakRewardDay") private var lastStreakRewardDay = ""
    /// Drives the character-narrated spotlight tour (started from Profile).
    @StateObject private var tour = TourController()

    private var character: PetCharacter {
        PetCharacter.all[appState.activeChar] ?? PetCharacter.all["byte"]!
    }

    var body: some View {
        HStack(spacing: 0) {
            // Custom narrow sidebar
            SidebarNav(
                selectedTab: $appState.selectedTab,
                showChat: $showChat,
                soundEnabled: $appState.soundEnabled,
                character: character,
                charColor: character.color,
                streak: appState.streak
            )

            // Divider line
            Rectangle()
                .fill(Color(hex: "#EBE8DF"))
                .frame(width: 1)

            // Main content
            ZStack {
                VStack(spacing: 0) {
                    // Game HUD (hearts, coins, streak) — dropped on the new .home (Your learning)
                    if appState.selectedTab == .skills || appState.selectedTab == .sessions {
                        GameHUDBar()
                        Rectangle()
                            .fill(Color(hex: "#EBE8DF"))
                            .frame(height: 1)
                    }

                    Group {
                        switch appState.selectedTab {
                        case .home:
                            HomeView()
                        case .skills:
                            SkillsView(showCompanion: $showChat)
                        case .sessions:
                            SessionsView()
                        case .insights:
                            InsightsView()
                        case .reflection:
                            ReflectionTab(companionOpen: showChat)
                        case .tips:
                            TipsTabView()
                        case .learn:
                            TipsTabView() // Learn content lives inside Tips now
                        case .dictionary:
                            DictionaryView()
                        case .profile:
                            ProfileView()
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }

                // Level-up overlay
                if appState.showLevelUp {
                    LevelUpOverlay(
                        level: appState.userLevel,
                        characterColor: character.color,
                        onDismiss: { appState.showLevelUp = false }
                    )
                }

                // Tier unlock overlay
                if appState.showTierUnlock {
                    TierUnlockOverlay(
                        tierNumber: appState.newTierNum,
                        characterId: appState.activeChar,
                        onDismiss: { appState.showTierUnlock = false }
                    )
                }

                // Skill "Leveled Up" celebration
                if let celebration = appState.skillCelebration {
                    SkillLeveledUpOverlay(
                        celebration: celebration,
                        characterId: appState.activeChar,
                        onDismiss: { appState.skillCelebration = nil }
                    )
                }

                // Global pet chat bubble — visible on all tabs except when chat is already open
                if !showChat && appState.selectedTab != .skills {
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            SessionChatBubble(onTap: {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    showChat = true
                                }
                            })
                            .padding(.trailing, 20)
                            .padding(.bottom, 20)
                        }
                    }
                    .zIndex(100)
                }

                // Welcome back overlay (after idle)
                if gameState.showWelcomeBack {
                    WelcomeBackView(
                        idleXP: gameState.idleXPEarned,
                        previousEnergy: max(5, appState.petEnergy + Int(Double(100 - appState.petEnergy) * 0.3)),
                        previousHunger: max(0, gameState.petHunger + Int(Double(100 - gameState.petHunger) * 0.3)),
                        dismissAction: {
                            withAnimation(.easeOut(duration: 0.3)) {
                                gameState.showWelcomeBack = false
                            }
                        }
                    )
                    .transition(.opacity)
                }

                // Practice workspace — large centered modal (exercises need room)
                if let exercise = appState.activeExercise {
                    Color.black.opacity(0.45)
                        .ignoresSafeArea()
                        .onTapGesture { }
                    GeometryReader { geo in
                        ExerciseWorkspaceView(
                            challenge: exercise,
                            character: PetCharacter.all[appState.activeChar] ?? PetCharacter.all["byte"]!,
                            onClose: { withAnimation(.easeOut(duration: 0.2)) { appState.activeExercise = nil } }
                        )
                        // Fresh state (sandbox, prompt, runner) per exercise so
                        // "Next" starts the next one clean.
                        .id(exercise.id)
                        .frame(width: max(520, geo.size.width * 0.5), height: geo.size.height * 0.86)
                        .background(Color(hex: "#F7F5FC"))
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .shadow(color: .black.opacity(0.25), radius: 30, y: 10)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                    }
                    .zIndex(200)
                    .transition(.opacity.combined(with: .scale(scale: 0.97)))
                }

                // Per-exercise "Exercise complete!" celebration — full-screen,
                // above the workspace, so there's no modal box behind it.
                if let cel = appState.exerciseCelebration {
                    ExerciseCompleteOverlay(
                        characterId: appState.activeChar,
                        earnedXP: cel.earnedXP,
                        isLast: cel.nextChallengeId == nil,
                        onAdvance: {
                            if let nextId = cel.nextChallengeId,
                               let next = challengeProgress.activeChallenges.first(where: { $0.id == nextId }) {
                                appState.activeExercise = next
                            } else {
                                appState.activeExercise = nil
                            }
                            appState.exerciseCelebration = nil
                        }
                    )
                    .zIndex(300)
                }

                if let m = appState.streakMilestoneCelebration {
                    StreakMilestoneOverlay(
                        characterId: appState.activeChar,
                        milestone: m,
                        onDismiss: { appState.streakMilestoneCelebration = nil }
                    )
                    .zIndex(310)
                }
            }

            // Chat companion panel (right sidebar, non-Skills tabs)
            if showChat && appState.selectedTab != .skills {
                Rectangle()
                    .fill(Color(hex: "#EBE8DF"))
                    .frame(width: 1)

                CompanionPanelView(onClose: { withAnimation(.easeInOut(duration: 0.2)) { showChat = false } })
                    .frame(width: 280)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .environmentObject(tour)
        // First-experience feedback — a centered pop-up over a dimmed backdrop,
        // floating over any tab.
        .overlay {
            if let feature = feedbackManager.pending {
                ZStack {
                    Color.black.opacity(0.45)
                        .ignoresSafeArea()
                        .onTapGesture { feedbackManager.dismiss() }
                    FeatureFeedbackPopup(
                        feature: feature,
                        onSubmit: { rating, comment in
                            feedbackManager.submit(feature: feature, rating: rating, comment: comment,
                                                   authManager: authManager, appState: appState)
                        },
                        onDismiss: { feedbackManager.dismiss() }
                    )
                    .transition(.scale(scale: 0.92).combined(with: .opacity))
                }
                .zIndex(320)
            }
        }
        // First-experience feedback triggers: an increase past the baseline means
        // the feature was just finished for the first time.
        .onChange(of: challengeProgress.completedChallengeIds.count) { newCount in
            if newCount > lastExerciseCount { feedbackManager.requestIfFirstTime(.exercise) }
            lastExerciseCount = newCount
        }
        .onChange(of: appState.completedLessons.count) { newCount in
            if newCount > lastLessonCount { feedbackManager.requestIfFirstTime(.lesson) }
            lastLessonCount = newCount
        }
        .onChange(of: masteredSkillCount) { newCount in
            if newCount > lastMasteredCount { feedbackManager.requestIfFirstTime(.skillMastered) }
            lastMasteredCount = newCount
        }
        // Full-window guided-tour layer: resolves each tagged element's frame in
        // this coordinate space and spotlights the current one over the real UI.
        .overlayPreferenceValue(TourAnchorPreferenceKey.self) { prefs in
            GeometryReader { proxy in
                if tour.isActive {
                    let rect = tour.currentStop?.anchor.flatMap { id in
                        prefs[id].map { proxy[$0] }
                    }
                    GuidedTourOverlay(rect: rect, containerSize: proxy.size,
                                      tour: tour, character: character)
                        .onAppear { syncTourTab() }
                        .onChange(of: tour.index) { _ in syncTourTab() }
                }
            }
            .zIndex(400)
        }
        .animation(.easeInOut(duration: 0.2), value: showChat)
        .onChange(of: appState.pendingChatPrompt) { prompt in
            if prompt != nil && !showChat {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showChat = true
                }
            }
        }
        .onChange(of: appState.selectedTab) { newTab in
            SoundManager.shared.playTabSwitch()
            if newTab == .home {
                SoundManager.shared.setPhase("home")
            }
        }
        .onAppear {
            // Always land on Reflection at launch, regardless of any leftover
            // in-session tab state. Runs once per app session.
            if !didSetLaunchTab {
                appState.selectedTab = .reflection
                didSetLaunchTab = true
            }
            // Seed feedback-trigger baselines so we only react to NEW completions
            // this session (not progress restored from a previous launch).
            lastExerciseCount = challengeProgress.completedChallengeIds.count
            lastLessonCount = appState.completedLessons.count
            lastMasteredCount = masteredSkillCount
            // Prime the guided tour with the current pet's voice + language, and
            // mark it seen when it ends (finish or skip) so it won't auto-run again.
            tour.configure(character: character, language: appState.uiLanguage)
            tour.onFinish = {
                appState.hasSeenFeatureGuide = true
                appState.selectedTab = .profile
            }
            // Theme the Reflection tab to the active character's color.
            ReflectionTheme.accent = character.color
            // Streak: rescue a single missed day with a freeze (if any), award
            // the daily coin bonus, then recognize any milestone reached.
            gameState.resolveStreakRescue()
            awardDailyStreakCoinsIfNeeded()
            if let milestone = gameState.checkStreakMilestones() {
                appState.streakMilestoneCelebration = StreakMilestoneCelebration(
                    day: milestone.day,
                    bonusCoins: milestone.bonusCoins,
                    freezeReward: milestone.freezeReward,
                    unlockedCosmetic: gameState.cosmeticName(forStreakDay: milestone.day))
            }
        }
        .onChange(of: appState.activeChar) { _ in
            // Keep the Reflection accent in sync when the pet is switched.
            ReflectionTheme.accent = character.color
            // Re-narrate the tour as the newly chosen pet.
            tour.configure(character: character, language: appState.uiLanguage)
        }
        .onChange(of: appState.uiLanguage) { _ in
            tour.configure(character: character, language: appState.uiLanguage)
        }
    }

    /// Switch to the tab the current tour stop targets (if any) so the spotlight
    /// lands on the real screen behind the dim layer.
    private func syncTourTab() {
        if let tab = tour.currentStop?.tab { appState.selectedTab = tab }
    }

    /// Awards the daily streak coin bonus once per calendar day the app is
    /// opened with an active streak. Date-keyed so it can't double-pay, and
    /// immune to cloud-sync repopulating progress (unlike watching counters).
    private func awardDailyStreakCoinsIfNeeded() {
        guard appState.streak >= 1 else { return }
        let c = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        let key = "\(c.year ?? 0)-\(c.month ?? 0)-\(c.day ?? 0)"
        guard lastStreakRewardDay != key else { return }
        lastStreakRewardDay = key
        gameState.earnCoins(GameEconomy.coinsPerStreakDay)
    }
}

// MARK: - Custom Sidebar Navigation

struct SidebarNav: View {
    @EnvironmentObject var appState: AppState
    @Binding var selectedTab: AppState.Tab
    @Binding var showChat: Bool
    @Binding var soundEnabled: Bool
    let character: PetCharacter
    let charColor: Color
    let streak: Int

    @State private var isAvatarHovered = false

    private let mainTabs: [AppState.Tab] = [.reflection, .tips, .dictionary]

    var body: some View {
        VStack(spacing: 2) {
            // Character avatar at top — tap to open Profile
            Button(action: { appState.selectedTab = .profile }) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(charColor.opacity(isAvatarHovered ? 0.18 : 0.10))
                        .frame(width: 60, height: 60)
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(charColor.opacity(isAvatarHovered ? 0.45 : 0.25), lineWidth: 1.5)
                        )

                    CharacterImage(character.id, size: 46)
                }
            }
            .buttonStyle(.plain)
            .onHover { isAvatarHovered = $0 }
            .help("Open profile")
            .padding(.bottom, 14)
            .tourAnchor(.profileAvatar)

            // Main nav items
            ForEach(mainTabs, id: \.self) { tab in
                NavButton(
                    tab: tab,
                    isSelected: selectedTab == tab,
                    charColor: charColor,
                    action: { selectedTab = tab }
                )
                .tourAnchor(forTab: tab)
            }

            Spacer()
        }
        .padding(.vertical, 16)
        .frame(width: 72)
        .background(Color.white)
    }
}

// MARK: - Nav Button

struct NavButton: View {
    let tab: AppState.Tab
    let isSelected: Bool
    let charColor: Color
    let action: () -> Void
    var customIcon: (() -> AnyView)? = nil

    @State private var isHovered = false
    @Environment(\.uiLanguage) private var uiLanguage

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .leading) {
                // Active indicator bar (left edge)
                if isSelected {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(charColor)
                        .frame(width: 3, height: 20)
                        .offset(x: -20)
                }

                VStack(spacing: 4) {
                    if let customIcon = customIcon {
                        customIcon()
                    } else {
                        NavIconView(tab: tab, isActive: isSelected, charColor: charColor)
                    }

                    Text(tab.displayName(uiLanguage))
                        .font(CodepetTheme.body(10, weight: .semibold))
                        .foregroundColor(isSelected ? Color(hex: "#2D2B26") : Color(hex: "#B0A898"))
                }
                .frame(width: 56, height: 52)
            }
            .frame(width: 56, height: 52)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? charColor.opacity(0.12) : isHovered ? Color(hex: "#FAFAF6") : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

// MARK: - Pixel-Art Nav Icons (SwiftUI)

struct NavIconView: View {
    let tab: AppState.Tab
    let isActive: Bool
    var charColor: Color = Color(hex: "#7F77DD")

    var body: some View {
        Group {
            switch tab {
            case .home:
                HomeNavIcon(isActive: isActive)
            case .skills:
                SkillsNavIcon(isActive: isActive)
            case .sessions:
                SessionsNavIcon(isActive: isActive)
            case .insights:
                InsightsNavIcon(isActive: isActive)
            case .reflection:
                // TODO: replace with pixel-art Canvas icon matching other 4 after feature validation
                Image(systemName: "quote.opening")
                    .font(.pixelSystem(size: 15, weight: .medium))
                    .foregroundColor(isActive ? charColor : Color(hex: "#B0A898"))
            case .tips:
                // TODO: replace with pixel-art Canvas icon — mockup only
                Image(systemName: "lightbulb.fill")
                    .font(.pixelSystem(size: 14, weight: .medium))
                    .foregroundColor(isActive ? charColor : Color(hex: "#B0A898"))
            case .learn:
                Image(systemName: "graduationcap.fill")
                    .font(.pixelSystem(size: 14, weight: .medium))
                    .foregroundColor(isActive ? charColor : Color(hex: "#B0A898"))
            case .dictionary:
                Image(systemName: "book.fill")
                    .font(.pixelSystem(size: 14, weight: .medium))
                    .foregroundColor(isActive ? charColor : Color(hex: "#B0A898"))
            case .profile:
                Image(systemName: "person.fill")
                    .font(.pixelSystem(size: 14))
                    .foregroundColor(isActive ? Color(hex: "#2D2B26") : Color(hex: "#B0A898"))
            }
        }
        .frame(width: 24, height: 24)
        .opacity(isActive ? 1.0 : 0.55)
    }
}

// Home icon — cute house with roof, door, windows
struct HomeNavIcon: View {
    let isActive: Bool

    var body: some View {
        Canvas { context, size in
            let s = size.width / 24

            // Roof
            var roofPath = Path()
            roofPath.move(to: CGPoint(x: 2 * s, y: 12 * s))
            roofPath.addLine(to: CGPoint(x: 12 * s, y: 3 * s))
            roofPath.addLine(to: CGPoint(x: 22 * s, y: 12 * s))
            roofPath.closeSubpath()
            context.fill(roofPath, with: .color(Color(hex: "#E8735A")))

            // Inner roof highlight
            var roofInner = Path()
            roofInner.move(to: CGPoint(x: 4 * s, y: 12 * s))
            roofInner.addLine(to: CGPoint(x: 12 * s, y: 5 * s))
            roofInner.addLine(to: CGPoint(x: 20 * s, y: 12 * s))
            roofInner.closeSubpath()
            context.fill(roofInner, with: .color(Color(hex: "#F4886E")))

            // House body
            let body = RoundedRectangle(cornerRadius: 1 * s).path(in: CGRect(x: 4 * s, y: 12 * s, width: 16 * s, height: 10 * s))
            context.fill(body, with: .color(Color(hex: "#FCE8C8")))
            context.stroke(body, with: .color(Color(hex: "#E6D5B5")), lineWidth: 0.8 * s)

            // Door
            let door = RoundedRectangle(cornerRadius: 3 * s).path(in: CGRect(x: 9.5 * s, y: 15 * s, width: 5 * s, height: 7 * s))
            context.fill(door, with: .color(Color(hex: "#E8735A")))
            let doorInner = RoundedRectangle(cornerRadius: 2 * s).path(in: CGRect(x: 10.5 * s, y: 16 * s, width: 3 * s, height: 5 * s))
            context.fill(doorInner, with: .color(Color(hex: "#D4604A")))

            // Door knob
            let knob = Circle().path(in: CGRect(x: 12.5 * s, y: 19 * s, width: 1 * s, height: 1 * s))
            context.fill(knob, with: .color(Color(hex: "#FCE8C8")))

            // Window left
            let winL = RoundedRectangle(cornerRadius: 0.5 * s).path(in: CGRect(x: 5.5 * s, y: 13.5 * s, width: 3 * s, height: 3 * s))
            context.fill(winL, with: .color(Color(hex: "#AEE2F5")))
            context.stroke(winL, with: .color(Color(hex: "#E6D5B5")), lineWidth: 0.5 * s)

            // Window right
            let winR = RoundedRectangle(cornerRadius: 0.5 * s).path(in: CGRect(x: 15.5 * s, y: 13.5 * s, width: 3 * s, height: 3 * s))
            context.fill(winR, with: .color(Color(hex: "#AEE2F5")))
            context.stroke(winR, with: .color(Color(hex: "#E6D5B5")), lineWidth: 0.5 * s)

            // Chimney
            let chimney = RoundedRectangle(cornerRadius: 0.5 * s).path(in: CGRect(x: 17 * s, y: 4 * s, width: 3 * s, height: 6 * s))
            context.fill(chimney, with: .color(Color(hex: "#C4856C")))
            let chimneyCap = RoundedRectangle(cornerRadius: 0.5 * s).path(in: CGRect(x: 16.5 * s, y: 3.5 * s, width: 4 * s, height: 1.5 * s))
            context.fill(chimneyCap, with: .color(Color(hex: "#D4967D")))
        }
    }
}

// Skills icon — tree with layered crown
struct SkillsNavIcon: View {
    let isActive: Bool

    var body: some View {
        Canvas { context, size in
            let s = size.width / 24

            // Trunk
            let trunk = RoundedRectangle(cornerRadius: 1 * s).path(in: CGRect(x: 10 * s, y: 14 * s, width: 4 * s, height: 9 * s))
            context.fill(trunk, with: .color(Color(hex: "#A0785A")))
            let trunkHighlight = RoundedRectangle(cornerRadius: 0.5 * s).path(in: CGRect(x: 11 * s, y: 14 * s, width: 1.5 * s, height: 9 * s))
            context.fill(trunkHighlight, with: .color(Color(hex: "#B8906C").opacity(0.6)))

            // Crown layers (bottom to top)
            let crown1 = Ellipse().path(in: CGRect(x: 3 * s, y: 7 * s, width: 18 * s, height: 11 * s))
            context.fill(crown1, with: .color(Color(hex: "#6EAE5E")))
            let crown2 = Ellipse().path(in: CGRect(x: 5 * s, y: 4 * s, width: 14 * s, height: 9 * s))
            context.fill(crown2, with: .color(Color(hex: "#7EC06A")))
            let crown3 = Ellipse().path(in: CGRect(x: 7 * s, y: 2 * s, width: 10 * s, height: 7 * s))
            context.fill(crown3, with: .color(Color(hex: "#8ED47C")))

            // Highlights
            let h1 = Ellipse().path(in: CGRect(x: 8 * s, y: 3 * s, width: 4 * s, height: 3 * s))
            context.fill(h1, with: .color(Color(hex: "#A4E292").opacity(0.6)))

            // Fruits
            let fruit1 = Circle().path(in: CGRect(x: 6 * s, y: 10 * s, width: 2 * s, height: 2 * s))
            context.fill(fruit1, with: .color(Color(hex: "#F4886E")))
            let fruit2 = Circle().path(in: CGRect(x: 15 * s, y: 6 * s, width: 1.5 * s, height: 1.5 * s))
            context.fill(fruit2, with: .color(Color(hex: "#FCDE5A")))
        }
    }
}

// Sessions icon — book with spine, pages, bookmark
struct SessionsNavIcon: View {
    let isActive: Bool

    var body: some View {
        Canvas { context, size in
            let s = size.width / 24

            // Book back cover
            let back = RoundedRectangle(cornerRadius: 1.5 * s).path(in: CGRect(x: 4 * s, y: 3 * s, width: 16 * s, height: 18 * s))
            context.fill(back, with: .color(Color(hex: "#5B8C6E")))

            // Pages
            let pages = RoundedRectangle(cornerRadius: 1 * s).path(in: CGRect(x: 5.5 * s, y: 4 * s, width: 14 * s, height: 16 * s))
            context.fill(pages, with: .color(Color(hex: "#FFFEF8")))

            // Spine
            let spine = RoundedRectangle(cornerRadius: 1.5 * s).path(in: CGRect(x: 4 * s, y: 3 * s, width: 3.5 * s, height: 18 * s))
            context.fill(spine, with: .color(Color(hex: "#4A7A5C")))
            let spineEdge = Rectangle().path(in: CGRect(x: 5.8 * s, y: 3 * s, width: 1 * s, height: 18 * s))
            context.fill(spineEdge, with: .color(Color(hex: "#5B8C6E")))

            // Page lines
            for y in [8, 11, 14] {
                let line = RoundedRectangle(cornerRadius: 0.5 * s).path(in: CGRect(x: 8.5 * s, y: CGFloat(y) * s, width: 9 * s, height: 0.8 * s))
                context.fill(line, with: .color(Color(hex: "#D8D4C8")))
            }

            // Bookmark ribbon
            var ribbon = Path()
            ribbon.move(to: CGPoint(x: 15.5 * s, y: 3 * s))
            ribbon.addLine(to: CGPoint(x: 15.5 * s, y: 7 * s))
            ribbon.addLine(to: CGPoint(x: 16.5 * s, y: 6 * s))
            ribbon.addLine(to: CGPoint(x: 17.5 * s, y: 7 * s))
            ribbon.addLine(to: CGPoint(x: 17.5 * s, y: 3 * s))
            ribbon.closeSubpath()
            context.fill(ribbon, with: .color(Color(hex: "#E8735A")))
        }
    }
}

// Insights icon — bar chart with varying heights
struct InsightsNavIcon: View {
    let isActive: Bool

    var body: some View {
        Canvas { context, size in
            let s = size.width / 24

            // Base line
            let base = RoundedRectangle(cornerRadius: 0.5 * s).path(in: CGRect(x: 3 * s, y: 20 * s, width: 18 * s, height: 1 * s))
            context.fill(base, with: .color(Color(hex: "#D8D4C8")))

            // Bar 1 (short)
            let bar1 = RoundedRectangle(cornerRadius: 1 * s).path(in: CGRect(x: 4 * s, y: 14 * s, width: 3.5 * s, height: 6 * s))
            context.fill(bar1, with: .color(Color(hex: "#FCDE5A")))

            // Bar 2 (tall)
            let bar2 = RoundedRectangle(cornerRadius: 1 * s).path(in: CGRect(x: 8.5 * s, y: 7 * s, width: 3.5 * s, height: 13 * s))
            context.fill(bar2, with: .color(Color(hex: "#6BCB77")))

            // Bar 3 (medium)
            let bar3 = RoundedRectangle(cornerRadius: 1 * s).path(in: CGRect(x: 13 * s, y: 10 * s, width: 3.5 * s, height: 10 * s))
            context.fill(bar3, with: .color(Color(hex: "#5BA8C8")))

            // Bar 4 (tallest)
            let bar4 = RoundedRectangle(cornerRadius: 1 * s).path(in: CGRect(x: 17.5 * s, y: 4 * s, width: 3.5 * s, height: 16 * s))
            context.fill(bar4, with: .color(Color(hex: "#E8735A")))
        }
    }
}

#Preview {
    MainTabView()
        .environmentObject(AppState())
        .environmentObject(AuthManager())
}

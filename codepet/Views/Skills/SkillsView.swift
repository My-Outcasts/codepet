import SwiftUI
import UniformTypeIdentifiers

struct SkillsView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var gameState: GameState
    @State private var selectedLesson: Lesson? = nil
    @State private var previewSkill: Skill? = nil
    @State private var showShareCard = false
    @State private var selectedChallenge: Challenge? = nil
    @State private var showTreeView = false
    @State private var selectedPlayground: PlaygroundScenario? = nil
    @Binding var showCompanion: Bool

    private var nextSkill: Skill? {
        for tier in GameData.skillTiers {
            if tier.id > appState.currentTier { break }
            for skill in tier.skills {
                if !appState.completedLessons.contains(skill.id) {
                    return skill
                }
            }
        }
        return nil
    }

    private var nextTier: SkillTier? {
        GameData.skillTiers.first { tier in
            tier.skills.contains { !appState.completedLessons.contains($0.id) }
        }
    }

    var body: some View {
        ZStack {
            HStack(spacing: 0) {
                // Main Content
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        // Header
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("◆ CODEPET")
                                    .font(.pixelSystem(size: 9, weight: .semibold, design: .monospaced))
                                    .foregroundColor(PetCharacter.all[appState.activeChar]?.color ?? .gray)
                                Text("Your Skills")
                                    .font(.pixelSystem(size: 26, weight: .bold))
                                    .foregroundColor(Color(hex: "#2D2B26"))
                                Text("Learn the skills you need to build with AI – one lesson at a time.")
                                    .font(.pixelSystem(size: 13))
                                    .foregroundColor(Color(hex: "#2D2B26").opacity(0.6))
                            }
                            Spacer()
                            Button(action: { showShareCard = true; SoundManager.shared.playTap() }) {
                                HStack(spacing: 4) {
                                    Image(systemName: "square.and.arrow.up")
                                        .font(.pixelSystem(size: 11))
                                    Text("Share")
                                        .font(.pixelSystem(size: 11, weight: .semibold))
                                }
                                .foregroundColor(Color(hex: "#2D2B26").opacity(0.5))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(Color.white)
                                        .shadow(color: .black.opacity(0.06), radius: 4, y: 1)
                                )
                            }
                            .buttonStyle(.plain)
                        }

                        // Level Progress Card
                        LevelProgressCard()

                        // Daily Goal & Streak
                        SkillsDailyGoalCard()

                        // Prompt Playground
                        PlaygroundQuickAccess(onSelectScenario: { scenario in
                            selectedPlayground = scenario
                            SoundManager.shared.playTap()
                        })

                        // Review Ready
                        if !appState.lessonsReadyForReview.isEmpty {
                            ReviewReadySection(
                                reviewSkillIds: appState.lessonsReadyForReview,
                                onStartReview: { skill in openLesson(for: skill) }
                            )
                        }

                        // Start Here
                        if let skill = nextSkill, let tier = nextTier {
                            StartHereCard(skill: skill, tier: tier, onStart: {
                                openLesson(for: skill)
                            })
                        }

                        // Learning Path
                        // View toggle + Learning Path
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("YOUR LEARNING PATH")
                                    .font(.pixelSystem(size: 9, weight: .bold, design: .monospaced))
                                    .foregroundColor(Color(hex: "#2D2B26").opacity(0.4))
                                Spacer()
                                HStack(spacing: 0) {
                                    Button(action: { withAnimation { showTreeView = false } }) {
                                        Image(systemName: "list.bullet")
                                            .font(.pixelSystem(size: 10))
                                            .foregroundColor(!showTreeView ? .white : Color(hex: "#B0A898"))
                                            .frame(width: 28, height: 22)
                                            .background(!showTreeView ? Color(hex: "#2D2B26") : Color.clear)
                                            .cornerRadius(6)
                                    }
                                    .buttonStyle(.plain)
                                    Button(action: { withAnimation { showTreeView = true } }) {
                                        Image(systemName: "circle.grid.cross")
                                            .font(.pixelSystem(size: 10))
                                            .foregroundColor(showTreeView ? .white : Color(hex: "#B0A898"))
                                            .frame(width: 28, height: 22)
                                            .background(showTreeView ? Color(hex: "#2D2B26") : Color.clear)
                                            .cornerRadius(6)
                                    }
                                    .buttonStyle(.plain)
                                }
                                .padding(2)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(Color(hex: "#F0F0EC"))
                                )
                            }

                            if showTreeView {
                                SkillTreeView(
                                    onStartLesson: { skill in openLesson(for: skill) },
                                    onPreviewLocked: { skill in
                                        previewSkill = skill
                                        SoundManager.shared.playTap()
                                    },
                                    onStartChallenge: { challenge in
                                        selectedChallenge = challenge
                                        SoundManager.shared.playTap()
                                    }
                                )
                            } else {
                                ForEach(GameData.skillTiers) { tier in
                                    KingdomSectionView(tier: tier, onStartLesson: { skill in
                                        openLesson(for: skill)
                                    }, onPreviewLocked: { skill in
                                        previewSkill = skill
                                        SoundManager.shared.playTap()
                                    }, onStartChallenge: { challenge in
                                        selectedChallenge = challenge
                                        SoundManager.shared.playTap()
                                    })
                                }
                            }
                        }
                    }
                    .padding(24)
                }
                .background(Color(hex: "#FBF9F1"))

                // Companion Panel
                if showCompanion {
                    CompanionPanelView(onClose: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showCompanion = false
                        }
                    })
                    .frame(width: 280)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }

            // Lesson Overlay
            if let lesson = selectedLesson {
                Color.black.opacity(0.4)
                    .ignoresSafeArea()
                    .onTapGesture { selectedLesson = nil }

                LessonModalView(lesson: lesson, onComplete: { xp in
                    withAnimation(.easeOut(duration: 0.2)) {
                        let isReview = appState.completedLessons.contains(lesson.id)
                        let levelBefore = appState.userLevel
                        if !isReview {
                            appState.addXP(xp)
                            appState.completedLessons.append(lesson.id)
                            appState.checkTierProgression()
                            gameState.earnCoins(GameEconomy.coinsPerLesson)
                        } else {
                            // Review mode — mark reviewed, award small XP bonus
                            appState.markReviewed(lesson.id)
                            appState.addXP(10)
                        }
                        if appState.userLevel > levelBefore {
                            gameState.earnCoins(GameEconomy.coinsPerLevelUp * (appState.userLevel - levelBefore))
                        }
                        selectedLesson = nil
                    }
                }, onClose: {
                    withAnimation(.easeOut(duration: 0.2)) {
                        selectedLesson = nil
                    }
                })
                .frame(width: 560, height: 620)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .shadow(color: .black.opacity(0.2), radius: 30, y: 10)
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }

            // Locked Skill Preview Overlay
            if let skill = previewSkill {
                Color.black.opacity(0.4)
                    .ignoresSafeArea()
                    .onTapGesture { withAnimation { previewSkill = nil } }

                LockedSkillPreview(skill: skill, onDismiss: {
                    withAnimation(.easeOut(duration: 0.2)) { previewSkill = nil }
                })
                .frame(width: 420, height: 360)
                .clipShape(RoundedRectangle(cornerRadius: 20))
                .shadow(color: .black.opacity(0.2), radius: 30, y: 10)
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }

            // Share Progress Overlay
            if showShareCard {
                Color.black.opacity(0.4)
                    .ignoresSafeArea()
                    .onTapGesture { withAnimation { showShareCard = false } }

                ShareProgressCard(onDismiss: {
                    withAnimation(.easeOut(duration: 0.2)) { showShareCard = false }
                })
                .frame(width: 400, height: 480)
                .clipShape(RoundedRectangle(cornerRadius: 20))
                .shadow(color: .black.opacity(0.2), radius: 30, y: 10)
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }

            // Challenge Overlay
            if let challenge = selectedChallenge {
                Color.black.opacity(0.4)
                    .ignoresSafeArea()
                    .onTapGesture { }

                ChallengeOverlayView(
                    challenge: challenge,
                    difficultyLevel: appState.difficultyLevel,
                    onComplete: { xpEarned, attempt in
                        withAnimation(.easeOut(duration: 0.2)) {
                            appState.addXP(xpEarned)
                            if !appState.completedChallenges.contains(challenge.id) {
                                appState.completedChallenges.append(challenge.id)
                            }
                            appState.performanceHistory.append(
                                PerformanceEntry(score: 100, date: Date(), skillId: challenge.id)
                            )
                            selectedChallenge = nil
                        }
                    },
                    onClose: {
                        withAnimation(.easeOut(duration: 0.2)) {
                            selectedChallenge = nil
                        }
                    }
                )
                .frame(width: 620, height: 650)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .shadow(color: .black.opacity(0.2), radius: 30, y: 10)
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }

            // Prompt Playground Overlay
            if let scenario = selectedPlayground {
                Color.black.opacity(0.4)
                    .ignoresSafeArea()
                    .onTapGesture { }

                PromptPlaygroundView(
                    scenario: scenario,
                    onComplete: { xp in
                        withAnimation(.easeOut(duration: 0.2)) {
                            appState.addXP(xp)
                            selectedPlayground = nil
                        }
                    },
                    onClose: {
                        withAnimation(.easeOut(duration: 0.2)) {
                            selectedPlayground = nil
                        }
                    }
                )
                .frame(width: 700, height: 550)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .shadow(color: .black.opacity(0.2), radius: 30, y: 10)
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }
        }
        .animation(.easeInOut(duration: 0.25), value: selectedLesson != nil)
        .animation(.easeInOut(duration: 0.25), value: previewSkill != nil)
        .animation(.easeInOut(duration: 0.25), value: showShareCard)
        .animation(.easeInOut(duration: 0.25), value: selectedChallenge != nil)
        .animation(.easeInOut(duration: 0.25), value: selectedPlayground != nil)
    }

    private func openLesson(for skill: Skill) {
        if let lesson = LessonLibrary.all[skill.id] {
            selectedLesson = lesson
            SoundManager.shared.playTap()
        }
    }
}

// MARK: - Level Progress Card

struct LevelProgressCard: View {
    @EnvironmentObject var appState: AppState

    private var xpForLevel: Int { appState.userLevel * 100 }
    private var xpPrev: Int { (appState.userLevel - 1) * 100 }
    private var xpInLevel: Int { appState.totalXP - xpPrev }
    private var xpNeeded: Int { xpForLevel - xpPrev }
    private var xpPct: Double { min(1.0, Double(xpInLevel) / Double(max(1, xpNeeded))) }

    var body: some View {
        HStack(spacing: 16) {
            Circle()
                .fill(PetCharacter.all[appState.activeChar]?.color ?? .gray)
                .frame(width: 48, height: 48)
                .overlay(
                    Text("\(appState.userLevel)")
                        .font(.pixelSystem(size: 20, weight: .black, design: .monospaced))
                        .foregroundColor(.white)
                )

            VStack(alignment: .leading, spacing: 6) {
                Text("Level \(appState.userLevel) – \(levelTitle)")
                    .font(.pixelSystem(size: 15, weight: .bold))
                    .foregroundColor(Color(hex: "#2D2B26"))

                Text("\(xpInLevel) / \(xpNeeded) XP • Complete your \(ordinalLesson) lesson!")
                    .font(.pixelSystem(size: 11))
                    .foregroundColor(Color(hex: "#2D2B26").opacity(0.5))

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color(hex: "#EBE8DF"))
                        RoundedRectangle(cornerRadius: 4)
                            .fill(PetCharacter.all[appState.activeChar]?.color ?? .gray)
                            .frame(width: geo.size.width * xpPct)
                            .animation(.spring(response: 0.5), value: xpPct)
                    }
                }
                .frame(height: 8)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white)
                .shadow(color: .black.opacity(0.04), radius: 8, y: 2)
        )
    }

    private var levelTitle: String {
        switch appState.userLevel {
        case 1: return "Just Getting Started"
        case 2: return "Finding Your Feet"
        case 3...5: return "Building Momentum"
        case 6...9: return "Getting Confident"
        case 10...14: return "Skilled Builder"
        case 15...19: return "Advanced Crafter"
        case 20...29: return "Expert Navigator"
        default: return "AI Master"
        }
    }

    private var ordinalLesson: String {
        let count = appState.completedLessons.count + 1
        switch count {
        case 1: return "first"
        case 2: return "second"
        case 3: return "third"
        default: return "\(count)th"
        }
    }
}

// MARK: - Start Here Card

struct StartHereCard: View {
    let skill: Skill
    let tier: SkillTier
    let onStart: () -> Void

    private var teacher: PetCharacter? {
        if let lesson = LessonLibrary.all[skill.id] {
            return PetCharacter.all[lesson.teacher]
        }
        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("START HERE")
                .font(.pixelSystem(size: 9, weight: .bold, design: .monospaced))
                .foregroundColor(Color(hex: "#D4960A"))

            HStack(spacing: 16) {
                if let t = teacher {
                    VStack(spacing: 4) {
                        CharacterImage(t.id, size: 56)
                            .charIdle(t.id)
                            .petBreathing()
                        Text(t.name)
                            .font(.pixelSystem(size: 10, weight: .semibold))
                            .foregroundColor(t.color)
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text("TIER \(tier.id)")
                            .font(.pixelSystem(size: 8, weight: .bold, design: .monospaced))
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(tier.kingdomColor)
                            .cornerRadius(4)
                        Text(LessonLibrary.all[skill.id]?.duration ?? "3 min")
                            .font(.pixelSystem(size: 10))
                            .foregroundColor(Color(hex: "#2D2B26").opacity(0.4))
                    }

                    Text(skill.name)
                        .font(.pixelSystem(size: 17, weight: .bold))
                        .foregroundColor(Color(hex: "#2D2B26"))

                    Text(skill.desc)
                        .font(.pixelSystem(size: 12))
                        .foregroundColor(Color(hex: "#2D2B26").opacity(0.6))
                        .lineLimit(2)

                    Button(action: onStart) {
                        Text("Start lesson →")
                            .font(.pixelSystem(size: 13, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 10)
                            .background(Color(hex: "#2D2B26"))
                            .cornerRadius(10)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color(hex: "#D4960A").opacity(0.4), lineWidth: 1.5)
                )
                .shadow(color: .black.opacity(0.04), radius: 8, y: 2)
        )
    }
}

// MARK: - Kingdom Section

struct KingdomSectionView: View {
    let tier: SkillTier
    let onStartLesson: (Skill) -> Void
    var onPreviewLocked: ((Skill) -> Void)? = nil
    var onStartChallenge: ((Challenge) -> Void)? = nil
    @EnvironmentObject var appState: AppState

    private var completedCount: Int {
        tier.skills.filter { appState.completedLessons.contains($0.id) }.count
    }

    private var isLocked: Bool { tier.id > appState.currentTier }

    private var nextSkillIndex: Int? {
        tier.skills.firstIndex { !appState.completedLessons.contains($0.id) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Circle()
                    .fill(tier.kingdomColor)
                    .frame(width: 24, height: 24)
                    .overlay(
                        Text("\(tier.id)")
                            .font(.pixelSystem(size: 11, weight: .bold))
                            .foregroundColor(.white)
                    )
                Text(tier.kingdom)
                    .font(.pixelSystem(size: 14, weight: .bold))
                    .foregroundColor(isLocked ? Color(hex: "#2D2B26").opacity(0.35) : Color(hex: "#2D2B26"))
                Spacer()

                // Navigate to kingdom on World Map
                if !isLocked {
                    Button(action: {
                        SoundManager.shared.playTap()
                        appState.pendingKingdomId = tier.id
                        appState.selectedTab = .home
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "map.fill")
                                .font(.pixelSystem(size: 9))
                            Text("View Kingdom")
                                .font(.pixelSystem(size: 9, weight: .semibold))
                        }
                        .foregroundColor(tier.kingdomColor)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            Capsule()
                                .fill(tier.kingdomColor.opacity(0.1))
                        )
                    }
                    .buttonStyle(.plain)
                }

                Text("\(completedCount) / \(tier.skills.count)")
                    .font(.pixelSystem(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(completedCount == tier.skills.count ? Color(hex: "#D4960A") : .gray)
            }

            ForEach(Array(tier.skills.enumerated()), id: \.element.id) { index, skill in
                let isCompleted = appState.completedLessons.contains(skill.id)
                let isNext = !isLocked && index == nextSkillIndex
                let isSkillLocked = isLocked || (!isCompleted && index != nextSkillIndex && (nextSkillIndex == nil || index > nextSkillIndex!))

                let challenge = GameData.challenges.first { $0.skillName == skill.name }
                let challengeDone = challenge.map { appState.completedChallenges.contains($0.id) } ?? false

                SkillRowView(
                    skill: skill,
                    index: index + 1,
                    isCompleted: isCompleted,
                    isNext: isNext,
                    isLocked: isSkillLocked,
                    tierColor: tier.kingdomColor,
                    teacher: LessonLibrary.all[skill.id]?.teacher,
                    onStart: { onStartLesson(skill) },
                    onLockedTap: { onPreviewLocked?(skill) },
                    onChallenge: { if let c = challenge { onStartChallenge?(c) } },
                    challengeAvailable: challenge != nil && isCompleted,
                    challengeCompleted: challengeDone
                )
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white)
                .shadow(color: .black.opacity(0.03), radius: 6, y: 2)
        )
        .opacity(isLocked ? 0.5 : 1)
        .saturation(isLocked ? 0.3 : 1)
    }
}

// MARK: - Skill Row

struct SkillRowView: View {
    let skill: Skill
    let index: Int
    let isCompleted: Bool
    let isNext: Bool
    let isLocked: Bool
    let tierColor: Color
    let teacher: String?
    let onStart: () -> Void
    var onLockedTap: (() -> Void)? = nil
    var onChallenge: (() -> Void)? = nil
    var challengeAvailable: Bool = false
    var challengeCompleted: Bool = false

    private var teacherChar: PetCharacter? {
        if let t = teacher { return PetCharacter.all[t] }
        return nil
    }

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(isCompleted ? Color(hex: "#6BCB77") : (isNext ? tierColor : Color(hex: "#E8E6E0")))
                .frame(width: 30, height: 30)
                .overlay(
                    Group {
                        if isCompleted {
                            Image(systemName: "checkmark")
                                .font(.pixelSystem(size: 12, weight: .bold))
                                .foregroundColor(.white)
                        } else {
                            Text("\(index)")
                                .font(.pixelSystem(size: 12, weight: .bold))
                                .foregroundColor(isNext ? .white : .gray)
                        }
                    }
                )

            if let t = teacherChar {
                CharacterImage(t.id, size: 28)
                    .charIdle(t.id)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(skill.name)
                    .font(.pixelSystem(size: 13, weight: .semibold))
                    .foregroundColor(isLocked ? Color(hex: "#2D2B26").opacity(0.35) : Color(hex: "#2D2B26"))
                if let t = teacherChar {
                    Text("with \(t.name)")
                        .font(.pixelSystem(size: 10))
                        .foregroundColor(Color(hex: "#2D2B26").opacity(0.4))
                }
                if isLocked && !isCompleted {
                    Text("Unlocks after \(previousSkillName)")
                        .font(.pixelSystem(size: 9))
                        .foregroundColor(Color(hex: "#2D2B26").opacity(0.3))
                }
            }

            Spacer()

            if isCompleted {
                HStack(spacing: 6) {
                    if challengeAvailable && !challengeCompleted {
                        Button(action: { onChallenge?() }) {
                            Text("Challenge")
                                .font(.pixelSystem(size: 9, weight: .bold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(Color(hex: "#D4960A"))
                                )
                        }
                        .buttonStyle(.plain)
                    } else if challengeCompleted {
                        Image(systemName: "star.fill")
                            .font(.pixelSystem(size: 12))
                            .foregroundColor(Color(hex: "#D4960A"))
                    }
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(Color(hex: "#6BCB77"))
                        .font(.pixelSystem(size: 16))
                    Button(action: onStart) {
                        Text("Review")
                            .font(.pixelSystem(size: 10, weight: .semibold))
                            .foregroundColor(Color(hex: "#2D2B26").opacity(0.4))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(Color(hex: "#F0F0EC"))
                            )
                    }
                    .buttonStyle(.plain)
                }
            } else if isNext {
                Button(action: onStart) {
                    Text("Start →")
                        .font(.pixelSystem(size: 11, weight: .bold))
                        .foregroundColor(tierColor)
                }
                .buttonStyle(.plain)
            } else {
                Button(action: { onLockedTap?() }) {
                    HStack(spacing: 4) {
                        Image(systemName: "lock.fill")
                            .font(.pixelSystem(size: 11))
                            .foregroundColor(Color(hex: "#2D2B26").opacity(0.2))
                        Text("Preview")
                            .font(.pixelSystem(size: 9))
                            .foregroundColor(Color(hex: "#2D2B26").opacity(0.2))
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(isNext ? tierColor.opacity(0.06) : Color.clear)
                .overlay(
                    isNext ? RoundedRectangle(cornerRadius: 12).stroke(tierColor.opacity(0.2), lineWidth: 1) : nil
                )
        )
    }

    private var previousSkillName: String {
        for tier in GameData.skillTiers {
            if let idx = tier.skills.firstIndex(where: { $0.id == skill.id }), idx > 0 {
                return tier.skills[idx - 1].name
            }
        }
        return "previous lesson"
    }
}

// MARK: - Prompt Playground Quick Access

struct PlaygroundQuickAccess: View {
    let onSelectScenario: (PlaygroundScenario) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "hammer.fill")
                        .font(.pixelSystem(size: 10))
                        .foregroundColor(Color(hex: "#7B8CE0"))
                    Text("PROMPT PLAYGROUND")
                        .font(.pixelSystem(size: 9, weight: .bold, design: .monospaced))
                        .foregroundColor(Color(hex: "#7B8CE0"))
                }
                Spacer()
                Text("Write real prompts, not quizzes")
                    .font(.pixelSystem(size: 9))
                    .foregroundColor(Color(hex: "#2D2B26").opacity(0.35))
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(PlaygroundLibrary.scenarios) { scenario in
                        let teacher = PetCharacter.all[scenario.teacher]
                        Button(action: { onSelectScenario(scenario) }) {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack(spacing: 6) {
                                    if let t = teacher {
                                        CharacterImage(t.id, size: 22)
                                            .charIdle(t.id)
                                    }
                                    Text(scenario.difficulty.rawValue.uppercased())
                                        .font(.pixelSystem(size: 7, weight: .bold, design: .monospaced))
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 4)
                                        .padding(.vertical, 1)
                                        .background(scenario.difficulty.color)
                                        .cornerRadius(3)
                                }
                                Text(scenario.title)
                                    .font(.pixelSystem(size: 11, weight: .bold))
                                    .foregroundColor(Color(hex: "#2D2B26"))
                                    .lineLimit(1)
                                Text("\(scenario.xpReward) XP")
                                    .font(.pixelSystem(size: 9, weight: .bold, design: .monospaced))
                                    .foregroundColor(Color(hex: "#D4960A"))
                            }
                            .frame(width: 130)
                            .padding(10)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color(hex: "#7B8CE0").opacity(0.04))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12)
                                            .stroke(Color(hex: "#7B8CE0").opacity(0.12), lineWidth: 1)
                                    )
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white)
                .shadow(color: .black.opacity(0.04), radius: 8, y: 2)
        )
    }
}

// MARK: - Skill Tree View

struct SkillTreeView: View {
    let onStartLesson: (Skill) -> Void
    var onPreviewLocked: ((Skill) -> Void)? = nil
    var onStartChallenge: ((Challenge) -> Void)? = nil
    @EnvironmentObject var appState: AppState

    private let nodeWidth: CGFloat = 110
    private let nodeHeight: CGFloat = 120
    private let tierSpacing: CGFloat = 60
    private let nodeSpacing: CGFloat = 16

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            VStack(spacing: 0) {
                ForEach(Array(GameData.skillTiers.enumerated()), id: \.element.id) { tierIdx, tier in
                    let isLocked = tier.id > appState.currentTier

                    // Tier label
                    HStack(spacing: 8) {
                        Circle()
                            .fill(tier.kingdomColor)
                            .frame(width: 20, height: 20)
                            .overlay(
                                Text("\(tier.id)")
                                    .font(.pixelSystem(size: 9, weight: .bold))
                                    .foregroundColor(.white)
                            )
                        Text(tier.kingdom)
                            .font(.pixelSystem(size: 11, weight: .bold))
                            .foregroundColor(isLocked ? Color(hex: "#2D2B26").opacity(0.3) : Color(hex: "#2D2B26"))
                    }
                    .padding(.top, tierIdx == 0 ? 8 : tierSpacing)
                    .padding(.bottom, 12)

                    // Skill nodes row
                    HStack(spacing: nodeSpacing) {
                        ForEach(Array(tier.skills.enumerated()), id: \.element.id) { skillIdx, skill in
                            let isCompleted = appState.completedLessons.contains(skill.id)
                            let nextSkillIdx = tier.skills.firstIndex { !appState.completedLessons.contains($0.id) }
                            let isNext = !isLocked && skillIdx == nextSkillIdx
                            let isSkillLocked = isLocked || (!isCompleted && !isNext)
                            let teacher = LessonLibrary.all[skill.id].flatMap { PetCharacter.all[$0.teacher] }
                            let challenge = GameData.challenges.first { $0.skillName == skill.name }
                            let challengeDone = challenge.map { appState.completedChallenges.contains($0.id) } ?? false

                            VStack(spacing: 0) {
                                // Connection line to previous node
                                if skillIdx > 0 {
                                    // Handled by HStack spacing
                                }

                                // Node
                                SkillTreeNode(
                                    skill: skill,
                                    teacher: teacher,
                                    tierColor: tier.kingdomColor,
                                    isCompleted: isCompleted,
                                    isNext: isNext,
                                    isLocked: isSkillLocked,
                                    challengeDone: challengeDone,
                                    onTap: {
                                        if isCompleted || isNext {
                                            onStartLesson(skill)
                                        } else if isSkillLocked {
                                            onPreviewLocked?(skill)
                                        }
                                    },
                                    onChallenge: {
                                        if let c = challenge { onStartChallenge?(c) }
                                    }
                                )
                            }

                            // Draw edge to next node
                            if skillIdx < tier.skills.count - 1 {
                                VStack {
                                    Spacer()
                                    Rectangle()
                                        .fill(isCompleted ? tier.kingdomColor : Color(hex: "#E8E6E0"))
                                        .frame(width: 20, height: 2)
                                    Spacer()
                                }
                                .frame(height: nodeHeight)
                                .offset(y: 10)
                            }
                        }
                    }

                    // Vertical edge to next tier
                    if tierIdx < GameData.skillTiers.count - 1 {
                        let allCompleted = tier.skills.allSatisfy { appState.completedLessons.contains($0.id) }
                        VStack(spacing: 2) {
                            ForEach(0..<3, id: \.self) { _ in
                                Circle()
                                    .fill(allCompleted ? tier.kingdomColor : Color(hex: "#E8E6E0"))
                                    .frame(width: 4, height: 4)
                            }
                            Image(systemName: "chevron.down")
                                .font(.pixelSystem(size: 8, weight: .bold))
                                .foregroundColor(allCompleted ? tier.kingdomColor : Color(hex: "#E8E6E0"))
                        }
                        .padding(.top, 8)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white)
                .shadow(color: .black.opacity(0.03), radius: 6, y: 2)
        )
    }
}

struct SkillTreeNode: View {
    let skill: Skill
    let teacher: PetCharacter?
    let tierColor: Color
    let isCompleted: Bool
    let isNext: Bool
    let isLocked: Bool
    let challengeDone: Bool
    let onTap: () -> Void
    let onChallenge: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 6) {
                // Status ring
                ZStack {
                    Circle()
                        .fill(nodeBackground)
                        .frame(width: 56, height: 56)
                        .overlay(
                            Circle()
                                .stroke(nodeBorder, lineWidth: isNext ? 3 : 2)
                        )
                        .shadow(color: isNext ? tierColor.opacity(0.3) : .clear, radius: 8)

                    if let t = teacher {
                        CharacterImage(t.id, size: 32)
                            .charIdle(t.id)
                            .saturation(isLocked ? 0.2 : 1)
                            .opacity(isLocked ? 0.5 : 1)
                    } else {
                        Text(skill.icon)
                            .font(.pixelSystem(size: 20))
                            .opacity(isLocked ? 0.3 : 1)
                    }

                    // Completion badge
                    if isCompleted {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.pixelSystem(size: 16))
                            .foregroundColor(Color(hex: "#6BCB77"))
                            .background(Circle().fill(Color.white).frame(width: 14, height: 14))
                            .offset(x: 20, y: -20)
                    }

                    // Challenge star
                    if challengeDone {
                        Image(systemName: "star.fill")
                            .font(.pixelSystem(size: 10))
                            .foregroundColor(Color(hex: "#D4960A"))
                            .offset(x: -20, y: -20)
                    }

                    // Lock
                    if isLocked {
                        Image(systemName: "lock.fill")
                            .font(.pixelSystem(size: 12))
                            .foregroundColor(Color(hex: "#2D2B26").opacity(0.2))
                    }
                }

                // Skill name
                Text(skill.name)
                    .font(.pixelSystem(size: 9, weight: .semibold))
                    .foregroundColor(isLocked ? Color(hex: "#2D2B26").opacity(0.3) : Color(hex: "#2D2B26"))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .frame(width: 80)

                // Action indicator
                if isNext {
                    Text("START")
                        .font(.pixelSystem(size: 7, weight: .black, design: .monospaced))
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(tierColor)
                        .cornerRadius(4)
                } else if isCompleted && !challengeDone {
                    Button(action: onChallenge) {
                        Text("CHALLENGE")
                            .font(.pixelSystem(size: 6, weight: .bold, design: .monospaced))
                            .foregroundColor(Color(hex: "#D4960A"))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .buttonStyle(.plain)
        .scaleEffect(isHovered ? 1.05 : 1)
        .animation(.easeOut(duration: 0.15), value: isHovered)
        .onHover { hovering in isHovered = hovering }
        .frame(width: 100, height: 120)
    }

    private var nodeBackground: Color {
        if isCompleted { return Color(hex: "#F0FFF4") }
        if isNext { return tierColor.opacity(0.08) }
        return Color(hex: "#F8F7F3")
    }

    private var nodeBorder: Color {
        if isCompleted { return Color(hex: "#6BCB77") }
        if isNext { return tierColor }
        return Color(hex: "#E8E6E0")
    }
}

// MARK: - Review Ready Section

struct ReviewReadySection: View {
    let reviewSkillIds: [String]
    let onStartReview: (Skill) -> Void
    @EnvironmentObject var appState: AppState

    private var reviewSkills: [(Skill, PetCharacter?)] {
        reviewSkillIds.compactMap { skillId in
            for tier in GameData.skillTiers {
                if let skill = tier.skills.first(where: { $0.id == skillId }) {
                    let teacher = LessonLibrary.all[skillId].flatMap { PetCharacter.all[$0.teacher] }
                    return (skill, teacher)
                }
            }
            return nil
        }
    }

    private func reviewInterval(for skillId: String) -> String {
        let count = appState.lessonReviewCounts[skillId] ?? 0
        switch count {
        case 0: return "1st review"
        case 1: return "2nd review"
        case 2: return "3rd review"
        default: return "\(count + 1)th review"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("REVIEW READY")
                    .font(.pixelSystem(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(Color(hex: "#7B8CE0"))
                Image(systemName: "brain.head.profile")
                    .font(.pixelSystem(size: 10))
                    .foregroundColor(Color(hex: "#7B8CE0"))
                Spacer()
                Text("\(reviewSkillIds.count) to review")
                    .font(.pixelSystem(size: 9))
                    .foregroundColor(Color(hex: "#2D2B26").opacity(0.4))
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(reviewSkills.prefix(5), id: \.0.id) { skill, teacher in
                        Button(action: { onStartReview(skill) }) {
                            VStack(spacing: 8) {
                                if let t = teacher {
                                    CharacterImage(t.id, size: 32)
                                        .charIdle(t.id)
                                }
                                Text(skill.name)
                                    .font(.pixelSystem(size: 10, weight: .semibold))
                                    .foregroundColor(Color(hex: "#2D2B26"))
                                    .lineLimit(1)
                                Text(reviewInterval(for: skill.id))
                                    .font(.pixelSystem(size: 8, design: .monospaced))
                                    .foregroundColor(Color(hex: "#7B8CE0"))
                            }
                            .frame(width: 90)
                            .padding(.vertical, 10)
                            .padding(.horizontal, 6)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color(hex: "#7B8CE0").opacity(0.06))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12)
                                            .stroke(Color(hex: "#7B8CE0").opacity(0.15), lineWidth: 1)
                                    )
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white)
                .shadow(color: .black.opacity(0.04), radius: 8, y: 2)
        )
    }
}

// MARK: - Share Progress Card

struct ShareProgressCard: View {
    let onDismiss: () -> Void
    @EnvironmentObject var appState: AppState
    @State private var copied = false

    private var character: PetCharacter? {
        PetCharacter.all[appState.activeChar]
    }

    private var totalSkills: Int { 16 }
    private var completedSkills: Int { appState.completedLessons.count }
    private var progressPct: CGFloat { CGFloat(completedSkills) / CGFloat(totalSkills) }

    var body: some View {
        VStack(spacing: 0) {
            // Top bar
            HStack {
                Text("SHARE PROGRESS")
                    .font(.pixelSystem(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(Color(hex: "#D4960A"))
                Spacer()
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.pixelSystem(size: 11, weight: .bold))
                        .foregroundColor(Color(hex: "#2D2B26").opacity(0.4))
                        .frame(width: 24, height: 24)
                        .background(Color(hex: "#F0F0EC"))
                        .cornerRadius(12)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)
            .padding(.bottom, 12)

            Divider()

            // Shareable card preview
            VStack(spacing: 20) {
                shareableContent
                    .padding(24)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(
                                LinearGradient(
                                    colors: [Color(hex: "#FBF9F1"), Color(hex: "#FFF8F0")],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 16)
                                    .stroke(Color(hex: "#EBE8DF"), lineWidth: 1)
                            )
                    )
                    .padding(.horizontal, 24)

                // Action buttons
                HStack(spacing: 12) {
                    Button(action: copyToClipboard) {
                        HStack(spacing: 6) {
                            Image(systemName: copied ? "checkmark" : "doc.on.doc")
                                .font(.pixelSystem(size: 12))
                            Text(copied ? "Copied!" : "Copy Image")
                                .font(.pixelSystem(size: 12, weight: .semibold))
                        }
                        .foregroundColor(copied ? Color(hex: "#6BCB77") : .white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(copied ? Color(hex: "#F0FFF4") : Color(hex: "#2D2B26"))
                        .cornerRadius(10)
                    }
                    .buttonStyle(.plain)

                    Button(action: saveToDesktop) {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.down.circle")
                                .font(.pixelSystem(size: 12))
                            Text("Save Image")
                                .font(.pixelSystem(size: 12, weight: .semibold))
                        }
                        .foregroundColor(Color(hex: "#2D2B26"))
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(Color(hex: "#E8E6E0"), lineWidth: 1.5)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 16)

            Spacer()
        }
        .background(Color(hex: "#FFFDF8"))
    }

    // The actual shareable content
    private var shareableContent: some View {
        VStack(spacing: 16) {
            // Header
            HStack {
                Text("◆ CODEPET")
                    .font(.pixelSystem(size: 8, weight: .bold, design: .monospaced))
                    .foregroundColor(character?.color ?? .gray)
                Spacer()
                Text("Level \(appState.userLevel)")
                    .font(.pixelSystem(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(Color(hex: "#D4960A"))
            }

            // Character + Name
            HStack(spacing: 14) {
                if let char = character {
                    CharacterImage(char.id, size: 48)
                        .charIdle(char.id)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(appState.displayName.isEmpty ? "CodePet Builder" : appState.displayName)
                        .font(.pixelSystem(size: 16, weight: .bold))
                        .foregroundColor(Color(hex: "#2D2B26"))
                    Text("Tier \(appState.currentTier) • \(characterOutfits[appState.currentTier]?.name ?? "Starter")")
                        .font(.pixelSystem(size: 11))
                        .foregroundColor(Color(hex: "#2D2B26").opacity(0.5))
                }
                Spacer()
            }

            // Stats grid
            HStack(spacing: 0) {
                ShareStat(value: "\(completedSkills)/\(totalSkills)", label: "Skills", color: Color(hex: "#6BCB77"))
                ShareStat(value: "\(appState.totalXP)", label: "Total XP", color: Color(hex: "#D4960A"))
                ShareStat(value: "\(appState.streak)", label: "Streak", color: Color(hex: "#FF8C00"))
                ShareStat(value: "\(appState.longestStreak)", label: "Best", color: Color(hex: "#E04040"))
            }

            // Progress bar
            VStack(spacing: 4) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color(hex: "#EBE8DF"))
                        RoundedRectangle(cornerRadius: 4)
                            .fill(character?.color ?? Color(hex: "#6BCB77"))
                            .frame(width: geo.size.width * progressPct)
                    }
                }
                .frame(height: 6)

                Text("\(Int(progressPct * 100))% complete")
                    .font(.pixelSystem(size: 9, design: .monospaced))
                    .foregroundColor(Color(hex: "#2D2B26").opacity(0.4))
            }

            // Tier badges
            HStack(spacing: 8) {
                ForEach(1...4, id: \.self) { tier in
                    let unlocked = tier <= appState.currentTier
                    VStack(spacing: 2) {
                        Text(characterOutfits[tier]?.badge ?? "?")
                            .font(.pixelSystem(size: 14))
                        Text("T\(tier)")
                            .font(.pixelSystem(size: 7, weight: .bold, design: .monospaced))
                            .foregroundColor(unlocked ? Color(hex: "#2D2B26") : Color(hex: "#C8C0B4"))
                    }
                    .opacity(unlocked ? 1 : 0.3)
                }
            }
        }
    }

    @MainActor
    private func renderImage() -> NSImage? {
        let renderer = ImageRenderer(content:
            shareableContent
                .padding(24)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(
                            LinearGradient(
                                colors: [Color(hex: "#FBF9F1"), Color(hex: "#FFF8F0")],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                )
                .frame(width: 340)
                .environmentObject(appState)
        )
        renderer.scale = 2.0
        return renderer.nsImage
    }

    @MainActor
    private func copyToClipboard() {
        guard let image = renderImage() else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([image])
        SoundManager.shared.playSuccess()
        copied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { copied = false }
    }

    @MainActor
    private func saveToDesktop() {
        guard let image = renderImage(),
              let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:]) else { return }

        let panel = NSSavePanel()
        panel.nameFieldStringValue = "codepet-progress.png"
        panel.allowedContentTypes = [.png]
        panel.begin { response in
            if response == .OK, let url = panel.url {
                try? pngData.write(to: url)
                SoundManager.shared.playSuccess()
            }
        }
    }
}

struct ShareStat: View {
    let value: String
    let label: String
    let color: Color

    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.pixelSystem(size: 14, weight: .black, design: .monospaced))
                .foregroundColor(color)
            Text(label)
                .font(.pixelSystem(size: 8, weight: .medium, design: .monospaced))
                .foregroundColor(Color(hex: "#2D2B26").opacity(0.4))
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Locked Skill Preview

struct LockedSkillPreview: View {
    let skill: Skill
    let onDismiss: () -> Void
    @EnvironmentObject var appState: AppState

    private var teacher: PetCharacter? {
        if let lesson = LessonLibrary.all[skill.id] {
            return PetCharacter.all[lesson.teacher]
        }
        return nil
    }

    private var skillTier: SkillTier? {
        GameData.skillTiers.first { tier in
            tier.skills.contains { $0.id == skill.id }
        }
    }

    private var unlockRequirement: String {
        for tier in GameData.skillTiers {
            if let idx = tier.skills.firstIndex(where: { $0.id == skill.id }) {
                if idx > 0 {
                    return "Complete \"\(tier.skills[idx - 1].name)\" first"
                } else if tier.id > 1 {
                    let prevTier = GameData.skillTiers.first { $0.id == tier.id - 1 }
                    return "Complete all Tier \(tier.id - 1) skills"
                }
            }
        }
        return "Complete previous skills"
    }

    private var tierProgress: (completed: Int, total: Int) {
        guard let tier = skillTier else { return (0, 0) }
        let completed = tier.skills.filter { appState.completedLessons.contains($0.id) }.count
        return (completed, tier.skills.count)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                if let tier = skillTier {
                    Text("TIER \(tier.id)")
                        .font(.pixelSystem(size: 8, weight: .bold, design: .monospaced))
                        .foregroundColor(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(tier.kingdomColor)
                        .cornerRadius(4)
                    Text(tier.kingdom)
                        .font(.pixelSystem(size: 10, weight: .semibold))
                        .foregroundColor(Color(hex: "#2D2B26").opacity(0.5))
                }
                Spacer()
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.pixelSystem(size: 11, weight: .bold))
                        .foregroundColor(Color(hex: "#2D2B26").opacity(0.4))
                        .frame(width: 24, height: 24)
                        .background(Color(hex: "#F0F0EC"))
                        .cornerRadius(12)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)
            .padding(.bottom, 12)

            Divider()

            // Content
            ScrollView {
                VStack(spacing: 20) {
                    // Teacher + Skill info
                    HStack(spacing: 16) {
                        if let t = teacher {
                            VStack(spacing: 4) {
                                CharacterImage(t.id, size: 64)
                                    .charIdle(t.id)
                                    .petBreathing()
                                    .saturation(0.4)
                                    .opacity(0.7)
                                Text(t.name)
                                    .font(.pixelSystem(size: 10, weight: .semibold))
                                    .foregroundColor(t.color.opacity(0.6))
                            }
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 6) {
                                Text(skill.icon)
                                    .font(.pixelSystem(size: 18))
                                Text(skill.name)
                                    .font(.pixelSystem(size: 18, weight: .bold))
                                    .foregroundColor(Color(hex: "#2D2B26"))
                            }

                            Text(skill.desc)
                                .font(.pixelSystem(size: 13))
                                .foregroundColor(Color(hex: "#2D2B26").opacity(0.6))
                                .lineSpacing(3)
                        }
                    }
                    .padding(.horizontal, 24)

                    // Unlock requirement
                    VStack(spacing: 10) {
                        Image(systemName: "lock.fill")
                            .font(.pixelSystem(size: 20))
                            .foregroundColor(Color(hex: "#D4960A"))

                        Text("Locked")
                            .font(.pixelSystem(size: 14, weight: .bold))
                            .foregroundColor(Color(hex: "#2D2B26"))

                        Text(unlockRequirement)
                            .font(.pixelSystem(size: 12))
                            .foregroundColor(Color(hex: "#2D2B26").opacity(0.5))

                        // Progress bar
                        if let tier = skillTier {
                            VStack(spacing: 4) {
                                GeometryReader { geo in
                                    ZStack(alignment: .leading) {
                                        RoundedRectangle(cornerRadius: 4)
                                            .fill(Color(hex: "#EBE8DF"))
                                        RoundedRectangle(cornerRadius: 4)
                                            .fill(tier.kingdomColor)
                                            .frame(width: geo.size.width * CGFloat(tierProgress.completed) / CGFloat(max(1, tierProgress.total)))
                                    }
                                }
                                .frame(height: 6)
                                .frame(maxWidth: 200)

                                Text("\(tierProgress.completed) / \(tierProgress.total) skills completed")
                                    .font(.pixelSystem(size: 9, weight: .medium, design: .monospaced))
                                    .foregroundColor(Color(hex: "#2D2B26").opacity(0.4))
                            }
                        }
                    }
                    .padding(20)
                    .frame(maxWidth: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(Color(hex: "#FFF8F0"))
                            .overlay(
                                RoundedRectangle(cornerRadius: 14)
                                    .stroke(Color(hex: "#D4960A").opacity(0.2), lineWidth: 1)
                            )
                    )
                    .padding(.horizontal, 24)

                    // Teacher quote
                    if let t = teacher {
                        HStack(alignment: .top, spacing: 0) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(t.color)
                                .frame(width: 3)
                                .padding(.trailing, 12)
                            Text("\"\(t.firstWords.replacingOccurrences(of: "\"", with: ""))\"")
                                .font(.pixelSystem(size: 12))
                                .foregroundColor(Color(hex: "#2D2B26").opacity(0.6))
                                .italic()
                                .lineSpacing(3)
                        }
                        .padding(14)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(t.color.opacity(0.05))
                        )
                        .padding(.horizontal, 24)
                    }
                }
                .padding(.vertical, 16)
            }
        }
        .background(Color(hex: "#FFFDF8"))
    }
}

// MARK: - Daily Goal & Streak Card

struct SkillsDailyGoalCard: View {
    @EnvironmentObject var appState: AppState

    private var lessonsToday: Int {
        // Count lessons completed (simple proxy — full tracking would need timestamps)
        // For now show total completed as daily indicator
        appState.completedLessons.count
    }

    private var dailyTarget: Int {
        max(1, appState.dailyGoalMinutes > 0 ? (appState.dailyGoalMinutes / 3) : 1) // ~3 min per lesson
    }

    var body: some View {
        HStack(spacing: 16) {
            // Streak flame
            VStack(spacing: 4) {
                StreakFireView(streak: appState.streak)
                Text("streak")
                    .font(.pixelSystem(size: 8, weight: .medium, design: .monospaced))
                    .foregroundColor(Color(hex: "#2D2B26").opacity(0.4))
            }
            .frame(width: 48)

            // Divider
            Rectangle()
                .fill(Color(hex: "#EBE8DF"))
                .frame(width: 1, height: 36)

            // Goal progress
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("DAILY GOAL")
                        .font(.pixelSystem(size: 9, weight: .bold, design: .monospaced))
                        .foregroundColor(Color(hex: "#D4960A"))
                    Spacer()
                    Text("\(appState.completedLessons.count) skills learned")
                        .font(.pixelSystem(size: 10))
                        .foregroundColor(Color(hex: "#2D2B26").opacity(0.4))
                }

                // Progress dots
                HStack(spacing: 6) {
                    ForEach(0..<min(dailyTarget, 5), id: \.self) { i in
                        Circle()
                            .fill(i < lessonsToday ? Color(hex: "#6BCB77") : Color(hex: "#E8E6E0"))
                            .frame(width: 10, height: 10)
                            .overlay(
                                i < lessonsToday ?
                                Image(systemName: "checkmark")
                                    .font(.pixelSystem(size: 6, weight: .bold))
                                    .foregroundColor(.white)
                                : nil
                            )
                    }
                    if dailyTarget > 5 {
                        Text("+\(dailyTarget - 5)")
                            .font(.pixelSystem(size: 9))
                            .foregroundColor(Color(hex: "#B0A898"))
                    }
                    Spacer()
                }

                // Best streak
                if appState.longestStreak > 0 {
                    Text("Best streak: \(appState.longestStreak) days")
                        .font(.pixelSystem(size: 9))
                        .foregroundColor(Color(hex: "#2D2B26").opacity(0.3))
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white)
                .shadow(color: .black.opacity(0.04), radius: 8, y: 2)
        )
    }
}

#Preview {
    SkillsView(showCompanion: .constant(true))
        .environmentObject(AppState())
}

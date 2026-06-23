import SwiftUI

/// Skill tile — bold brand color, exercises to practice, AI-detected evidence.
struct SkillTileView: View {
    @EnvironmentObject var tipsState: TipsState
    @EnvironmentObject var narrativeStore: NarrativeStore
    @EnvironmentObject var challengeProgress: ChallengeProgress
    @EnvironmentObject var appState: AppState
    @Environment(\.uiLanguage) private var uiLanguage

    let petId: String
    let index: Int
    let tile: TipSkillTile
    var onStartChallenge: ((SkillChallenge) -> Void)? = nil

    @State private var selectedChallenge: SkillChallenge? = nil
    @State private var showLessonDetail = false
    /// Armed only while the skill is incomplete, so the celebration fires on
    /// the transition to 100% — not every time the view appears.
    @State private var celebrationArmed = false

    private var progress: SkillProgress {
        tipsState.progress(for: petId, index: index)
    }

    private let dark = Color(hex: "#2D2B26")

    private var skillColor: Color {
        [Color(hex: "#9538CF"), Color(hex: "#1C40CF"), Color(hex: "#029902"),
         Color(hex: "#F58345"), Color(hex: "#0EA5A5"), Color(hex: "#E0457B")][index % 6]
    }

    /// Same palette as `skillColor`, as hex — passed to the celebration overlay.
    private var skillColorHex: String {
        ["#9538CF", "#1C40CF", "#029902", "#F58345", "#0EA5A5", "#E0457B"][index % 6]
    }

    private var skillColorLight: Color {
        [Color(hex: "#EEEDFE"), Color(hex: "#E6F1FB"), Color(hex: "#E1F5EE"),
         Color(hex: "#FAECE7"), Color(hex: "#E2F6F6"), Color(hex: "#FBE9F0")][index % 6]
    }

    private var skillId: String {
        ["component_composition", "loading_error_states", "form_validation_ux",
         "accessibility_basics", "responsive_layout", "performance"][index % 6]
    }

    /// Active (incomplete) challenges for this skill.
    private var activeChallenges: [SkillChallenge] {
        challengeProgress.activeChallenges(for: skillId)
    }

    /// Completed challenges for this skill.
    private var completedChallenges: [SkillChallenge] {
        challengeProgress.completedChallenges(for: skillId)
    }

    /// Most recent evidence from AI detection.
    private var latestEvidence: String? {
        narrativeStore.narratives.values
            .sorted { $0.generatedAt > $1.generatedAt }
            .flatMap { $0.detectedSkills.filter { $0.skillId == skillId && $0.confidence == "strong" } }
            .first?.evidence
    }

    var body: some View {
        // ── Light tinted "info box" (matches the Profile-tab boxes): a soft
        // tint of the skill color behind a thin pixel border in the same hue,
        // with dark ink. Keeps each skill scannable by color without the loud
        // full-color fill. ──
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 5) {
                // Title line: title + progress meter (or Leveled Up tag).
                HStack(alignment: .center, spacing: 10) {
                    Text(tile.title(uiLanguage))
                        .font(ReflectionTheme.serif(17, weight: .semibold))
                        .foregroundColor(dark)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 8)
                    if allExercisesDone {
                        leveledUpBadge
                    } else if exerciseTotal > 0 {
                        progressMeter
                    }
                }

                // Hint clamped to one line — the wide row keeps it readable while
                // the section stays compact in a single column.
                Text(tile.hint(uiLanguage).emDashesAsCommas)
                    .font(.pixelSystem(size: 12.5))
                    .foregroundColor(dark.opacity(0.72))
                    .lineLimit(1)
                    .truncationMode(.tail)

                Text(exerciseCountLabel)
                    .font(.pixelSystem(size: 11, weight: .bold))
                    .foregroundColor(dark.opacity(0.5))
            }

            arrowButton
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .pixelBox(fill: skillColor.opacity(0.12), borderColor: skillColor,
                  shadowOffset: 2, blockSize: 2, steps: 2, borderWidth: 2)
        .contentShape(PixelStaircaseRectangle(blockSize: 2, steps: 2))
        .onTapGesture { showLessonDetail = true }
        .sheet(isPresented: $showLessonDetail) { lessonDetailSheet }
        .onAppear {
            // Arm only if not already complete, so we celebrate the moment the
            // last exercise is finished — not on every appearance.
            celebrationArmed = !allExercisesDone
        }
        .onChange(of: allExercisesDone) { done in
            if done && celebrationArmed {
                celebrationArmed = false
                appState.skillCelebration = SkillCelebration(
                    skillTitle: tile.title(uiLanguage),
                    colorHex: skillColorHex,
                    exerciseCount: exerciseTotal
                )
            }
        }
    }

    // MARK: - Arrow button + exercise count

    private var exerciseCountLabel: String {
        let n = activeChallenges.count + completedChallenges.count
        if uiLanguage == .vi { return "\(n) bài tập" }
        return "\(n) exercise\(n == 1 ? "" : "s")"
    }

    /// Small pixel chevron in the skill color — the colored affordance on the
    /// neutral card (mirrors the primary action on the reading cards).
    private var arrowButton: some View {
        Button(action: { showLessonDetail = true }) {
            ZStack {
                PixelStaircaseRectangle(blockSize: 2, steps: 1).fill(skillColor)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.white)
            }
            .frame(width: 30, height: 30)
            .overlay(PixelStaircaseRectangle(blockSize: 2, steps: 1).stroke(dark, lineWidth: 2))
            .background(
                PixelStaircaseRectangle(blockSize: 2, steps: 1)
                    .fill(dark.opacity(0.5))
                    .offset(x: 2, y: 2)
            )
        }
        .buttonStyle(.plain)
    }

    /// Total exercises (challenges) for this skill, and how many are done.
    private var exerciseTotal: Int { activeChallenges.count + completedChallenges.count }
    private var exerciseDone: Int { completedChallenges.count }
    /// True once every exercise is complete — earns the "Leveled Up" badge.
    private var allExercisesDone: Bool { exerciseTotal > 0 && exerciseDone == exerciseTotal }

    /// Slim progress meter (track + skill-color fill) — replaces the row of dots
    /// for a calmer signal, matching the Project Health header meter.
    private var progressMeter: some View {
        let total = max(exerciseTotal, 1)
        let frac = CGFloat(exerciseDone) / CGFloat(total)
        return HStack(spacing: 8) {
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(dark.opacity(0.10))
                    .frame(width: 48, height: 5)
                Capsule()
                    .fill(skillColor)
                    .frame(width: 48 * frac, height: 5)
            }
            Text("\(exerciseDone)/\(exerciseTotal)")
                .font(.pixelSystem(size: 10, weight: .bold))
                .foregroundColor(dark.opacity(0.5))
        }
    }

    /// Shown in place of the meter once all exercises are complete — a solid
    /// skill-color tag pops against the white card.
    private var leveledUpBadge: some View {
        Text(uiLanguage == .vi ? "Lên cấp!" : "Leveled Up!")
            .font(.pixelSystem(size: 10, weight: .bold))
            .foregroundColor(.white)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            PixelStaircaseRectangle(blockSize: 2, steps: 1)
                .fill(skillColor)
        )
        .overlay(
            PixelStaircaseRectangle(blockSize: 2, steps: 1)
                .stroke(dark, lineWidth: 1.5)
        )
    }

    // MARK: - Lesson detail popup

    /// Pop-up opened from the main card: a banner header + the full exercise
    /// list. Tapping an exercise opens the existing ChallengeDetailView.
    private var lessonDetailSheet: some View {
        VStack(spacing: 0) {
            // Header band (mirrors the card banner)
            ZStack {
                skillColor
                Circle().fill(Color.white.opacity(0.07))
                    .frame(width: 60, height: 60).offset(x: -40, y: -15)
                Circle().fill(Color.white.opacity(0.05))
                    .frame(width: 40, height: 40).offset(x: 50, y: 10)

                HStack {
                    ZStack {
                        PixelStaircaseRectangle(blockSize: 2, steps: 1).fill(Color.white)
                        Image(systemName: tile.icon)
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(skillColor)
                    }
                    .frame(width: 40, height: 40)
                    .overlay(PixelStaircaseRectangle(blockSize: 2, steps: 1).stroke(dark, lineWidth: 2))

                    Spacer()

                    HStack(spacing: 5) {
                        ForEach(Array(0..<exerciseTotal), id: \.self) { i in
                            Circle()
                                .fill(i < exerciseDone ? Color.white : Color.white.opacity(0.25))
                                .frame(width: 8, height: 8)
                        }
                    }

                    Button(action: { showLessonDetail = false }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.white)
                            .frame(width: 24, height: 24)
                            .background(Circle().fill(Color.white.opacity(0.2)))
                    }
                    .buttonStyle(.plain)
                    .padding(.leading, 6)
                }
                .padding(.horizontal, 14)
            }
            .frame(height: 64)
            .clipped()

            // Body
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text(tile.title(uiLanguage))
                        .font(CodepetTheme.body(18, weight: .bold))
                        .foregroundColor(dark)

                    if let evidence = latestEvidence {
                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: "sparkles")
                                .font(.system(size: 11))
                                .foregroundColor(skillColor)
                                .padding(.top, 2)
                            Text(evidence)
                                .font(.pixelSystem(size: 11))
                                .foregroundColor(dark.opacity(0.6))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    let ordered = challengeProgress.orderedChallenges(for: skillId)
                    if !ordered.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(uiLanguage == .vi ? "BÀI TẬP" : "EXERCISES")
                                .font(.pixelSystem(size: 9, weight: .bold))
                                .tracking(0.8)
                                .foregroundColor(dark.opacity(0.35))
                            ForEach(ordered) { challenge in
                                challengeRow(challenge)
                            }
                        }
                    } else {
                        Text(uiLanguage == .vi ? "Codepet sẽ nhận ra khi bạn luyện tập" : "Codepet will notice when you practice this")
                            .font(.pixelSystem(size: 11))
                            .foregroundColor(dark.opacity(0.35))
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Color(hex: "#FDFCFF"))
        }
        .frame(minWidth: 480, minHeight: 380)
        .sheet(item: $selectedChallenge) { challenge in
            ChallengeDetailView(
                challenge: challenge,
                skillColor: skillColor,
                isCompleted: challengeProgress.isCompleted(challenge.id),
                onStartCoding: {
                    onStartChallenge?(challenge)
                    showLessonDetail = false
                }
            )
        }
    }

    // MARK: - Challenge Row

    private func challengeRow(_ challenge: SkillChallenge) -> some View {
        let done = challengeProgress.isCompleted(challenge.id)
        let unlocked = challengeProgress.isUnlocked(challenge)
        let upNext = !done && unlocked          // exactly one at a time (linear)

        return Button(action: { if upNext { selectedChallenge = challenge } }) {
            HStack(spacing: 10) {
                // Status icon: ✓ done · difficulty (up next) · 🔒 locked
                Group {
                    if done {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(Color(hex: "#029902"))
                    } else if upNext {
                        difficultyIcon(challenge.difficulty)
                    } else {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(dark.opacity(0.3))
                    }
                }
                .frame(width: 22, height: 22)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(challenge.title)
                            .font(.pixelSystem(size: 11, weight: .bold))
                            .foregroundColor(upNext ? dark : dark.opacity(0.45))
                            .lineLimit(1)
                        if upNext {
                            Text(uiLanguage == .vi ? "TIẾP THEO" : "UP NEXT")
                                .font(.pixelSystem(size: 8, weight: .bold))
                                .tracking(0.5)
                                .foregroundColor(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(RoundedRectangle(cornerRadius: 4).fill(skillColor))
                        }
                    }
                    // Only the active exercise shows its description, to keep
                    // the list minimal.
                    if upNext {
                        Text(challenge.description)
                            .font(.pixelSystem(size: 10))
                            .foregroundColor(dark.opacity(0.5))
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(upNext ? skillColorLight.opacity(0.7)
                                 : dark.opacity(done ? 0.03 : 0.02))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(upNext ? skillColor.opacity(0.25) : Color.clear, lineWidth: 1)
            )
            .opacity(done ? 0.7 : (upNext ? 1 : 0.55))
        }
        .buttonStyle(.plain)
        .disabled(!upNext)
    }

    private func difficultyIcon(_ difficulty: SkillChallenge.ChallengeDifficulty) -> some View {
        let (icon, color): (String, Color) = {
            switch difficulty {
            case .starter:  return ("star", Color(hex: "#029902"))
            case .practice: return ("star.leadinghalf.filled", Color(hex: "#D49700"))
            case .stretch:  return ("star.fill", Color(hex: "#E24B4A"))
            case .expert:   return ("crown.fill", Color(hex: "#7B3FE4"))
            }
        }()

        return Image(systemName: icon)
            .font(.system(size: 10, weight: .bold))
            .foregroundColor(color)
            .frame(width: 22, height: 22)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(color.opacity(0.12))
            )
    }
}

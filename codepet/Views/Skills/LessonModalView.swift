import SwiftUI

struct LessonModalView: View {
    let lesson: Lesson
    let onComplete: (Int) -> Void
    let onClose: () -> Void

    @State private var currentStep = 0
    @State private var xpEarned: Int = 0

    // Quiz state
    @State private var selectedAnswer: String? = nil
    @State private var answerSubmitted: Bool = false
    @State private var isCorrect: Bool = false

    private var step: LessonStep { lesson.steps[currentStep] }
    private var totalSteps: Int { lesson.steps.count }
    private var isLastStep: Bool { currentStep == totalSteps - 1 }
    private var teacher: PetCharacter? { PetCharacter.all[lesson.teacher] }

    var body: some View {
        VStack(spacing: 0) {
            // Top bar with progress
            LessonTopBar(
                stepType: step.type,
                currentStep: currentStep,
                totalSteps: totalSteps,
                xpEarned: xpEarned,
                onClose: onClose
            )

            ScrollView {
                VStack(spacing: 24) {
                    // Teacher avatar
                    if let t = teacher {
                        VStack(spacing: 4) {
                            CharacterImage(t.id, size: 64)
                                .charIdle(t.id)
                                .petBreathing()
                            Text(t.name)
                                .font(.pixelSystem(size: 12, weight: .semibold))
                                .foregroundColor(t.color)
                        }
                    }

                    // Title
                    Text(step.title)
                        .font(.pixelSystem(size: 22, weight: .bold))
                        .foregroundColor(Color(hex: "#2D2B26"))
                        .multilineTextAlignment(.center)

                    // Content based on step type
                    switch step.content {
                    case .briefing(let intro, let body, let hook):
                        BriefingContent(intro: intro, bodyText: body, hook: hook)

                    case .learn(let concept, let explanation, let bad, let good, let insight):
                        LearnContent(concept: concept, explanation: explanation, badExample: bad, goodExample: good, insight: insight)

                    case .applyIt(let instruction, let originalPrompt, let options, let correctFeedback, let wrongFeedback):
                        ApplyItContent(
                            instruction: instruction,
                            originalPrompt: originalPrompt,
                            options: options,
                            correctFeedback: correctFeedback,
                            wrongFeedback: wrongFeedback,
                            selectedAnswer: $selectedAnswer,
                            answerSubmitted: $answerSubmitted,
                            isCorrect: $isCorrect,
                            teacherColor: teacher?.color ?? Color(hex: "#D4960A")
                        )

                    case .fieldMission(let scenario, let task, let options, let correctFeedback, let wrongFeedback):
                        FieldMissionContent(
                            scenario: scenario,
                            task: task,
                            options: options,
                            correctFeedback: correctFeedback,
                            wrongFeedback: wrongFeedback,
                            selectedAnswer: $selectedAnswer,
                            answerSubmitted: $answerSubmitted,
                            isCorrect: $isCorrect,
                            teacherColor: teacher?.color ?? Color(hex: "#E0508C")
                        )

                    case .summary(let recap, let xp, let badge):
                        SummaryContent(recap: recap, xpReward: xp, badge: badge, teacherColor: teacher?.color ?? .gray)
                    }
                }
                .padding(32)
                .padding(.bottom, 80)
            }

            // Bottom action button
            VStack {
                Divider()
                Button(action: { advance() }) {
                    Text(buttonLabel)
                        .font(.pixelSystem(size: 14, weight: .bold))
                        .foregroundColor(canAdvance ? .white : Color(hex: "#B0A898"))
                        .frame(maxWidth: 280)
                        .padding(.vertical, 12)
                        .background(canAdvance ? Color(hex: "#2D2B26") : Color(hex: "#E0DDD6"))
                        .cornerRadius(12)
                }
                .buttonStyle(.plain)
                .disabled(!canAdvance)
                .padding(.vertical, 12)
            }
            .background(Color.white)
        }
        .background(Color(hex: "#FFFDF8"))
    }

    private var canAdvance: Bool {
        switch step.type {
        case .applyIt, .fieldMission:
            // Must answer and get feedback before continuing
            return answerSubmitted
        default:
            return true
        }
    }

    private var buttonLabel: String {
        switch step.type {
        case .briefing: return "Let's learn →"
        case .learn: return "Now let me try →"
        case .applyIt:
            if !answerSubmitted { return "Select an answer" }
            return isCorrect ? "Next challenge →" : "Try again"
        case .fieldMission:
            if !answerSubmitted { return "Select an answer" }
            return isCorrect ? (isLastStep ? "Complete Lesson" : "Continue →") : "Try again"
        case .summary: return "Complete Lesson ✓"
        }
    }

    private func advance() {
        // Handle retry for wrong quiz answers
        if (step.type == .applyIt || step.type == .fieldMission) && answerSubmitted && !isCorrect {
            // Reset for retry
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedAnswer = nil
                answerSubmitted = false
                isCorrect = false
            }
            return
        }

        if isLastStep {
            if case .summary(_, let xp, _) = step.content {
                onComplete(xp)
            } else {
                onComplete(25)
            }
        } else {
            withAnimation(.easeInOut(duration: 0.25)) {
                // Award XP for correct quiz answers
                if answerSubmitted && isCorrect {
                    xpEarned += 20
                }
                // Reset quiz state for next step
                selectedAnswer = nil
                answerSubmitted = false
                isCorrect = false
                currentStep += 1
            }
            SoundManager.shared.playNextStep()
        }
    }
}

// MARK: - Top Bar

struct LessonTopBar: View {
    let stepType: LessonStepType
    let currentStep: Int
    let totalSteps: Int
    let xpEarned: Int
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                HStack(spacing: 4) {
                    ForEach(0..<totalSteps, id: \.self) { i in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(i < currentStep ? Color(hex: "#6BCB77") : (i == currentStep ? stepColor : Color(hex: "#E8E6E0")))
                            .frame(height: 4)
                    }
                }

                Text("+\(xpEarned)")
                    .font(.pixelSystem(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(Color(hex: "#D4960A"))

                Text("...")
                    .font(.pixelSystem(size: 12))
                    .foregroundColor(.gray)

                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.pixelSystem(size: 12, weight: .bold))
                        .foregroundColor(Color(hex: "#2D2B26").opacity(0.4))
                        .frame(width: 28, height: 28)
                        .background(Color(hex: "#F0F0EC"))
                        .cornerRadius(14)
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 6) {
                Text(stepIcon)
                Text(stepLabel)
                    .font(.pixelSystem(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(stepColor)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 24)
        .padding(.top, 16)
        .padding(.bottom, 8)
        .background(Color.white)
    }

    private var stepLabel: String {
        switch stepType {
        case .briefing: return "BRIEFING"
        case .learn: return "LEARN IT"
        case .applyIt: return "APPLY IT"
        case .fieldMission: return "FIELD MISSION"
        case .summary: return "COMPLETE"
        }
    }

    private var stepIcon: String {
        switch stepType {
        case .briefing: return "📋"
        case .learn: return "💡"
        case .applyIt: return "👆"
        case .fieldMission: return "🌍"
        case .summary: return "🏆"
        }
    }

    private var stepColor: Color {
        switch stepType {
        case .briefing: return Color(hex: "#D4960A")
        case .learn: return Color(hex: "#6BCB77")
        case .applyIt: return Color(hex: "#7B8CE0")
        case .fieldMission: return Color(hex: "#E0508C")
        case .summary: return Color(hex: "#D4960A")
        }
    }
}

// MARK: - Briefing Content

struct BriefingContent: View {
    let intro: String
    let bodyText: String
    let hook: String

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 0) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color(hex: "#D4960A"))
                    .frame(width: 3)
                    .padding(.trailing, 12)
                Text(intro)
                    .font(.pixelSystem(size: 13))
                    .foregroundColor(Color(hex: "#2D2B26").opacity(0.7))
                    .italic()
                    .lineSpacing(4)
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(hex: "#FFF8F0"))
            )

            Text(bodyText)
                .font(.pixelSystem(size: 14))
                .foregroundColor(Color(hex: "#2D2B26"))
                .lineSpacing(5)

            Text("✦ \(hook)")
                .font(.pixelSystem(size: 13, weight: .medium))
                .foregroundColor(Color(hex: "#D4960A"))
                .italic()
                .lineSpacing(4)
        }
        .frame(maxWidth: 480)
    }
}

// MARK: - Learn Content

struct LearnContent: View {
    let concept: String
    let explanation: String
    let badExample: ExamplePair?
    let goodExample: ExamplePair?
    let insight: String

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text(concept)
                    .font(.pixelSystem(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(Color(hex: "#D4960A"))
                Text(explanation)
                    .font(.pixelSystem(size: 14))
                    .foregroundColor(Color(hex: "#2D2B26"))
                    .lineSpacing(4)
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.white)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color(hex: "#E8E6E0"), lineWidth: 1)
                    )
            )

            if badExample != nil || goodExample != nil {
                HStack(alignment: .top, spacing: 12) {
                    if let bad = badExample {
                        ExampleCard(label: "✕ \(bad.label)", text: bad.text, color: Color(hex: "#E06050"), bgColor: Color(hex: "#FFF5F5"))
                    }
                    if let good = goodExample {
                        ExampleCard(label: "✓ \(good.label)", text: good.text, color: Color(hex: "#6BCB77"), bgColor: Color(hex: "#F0FFF4"))
                    }
                }
            }

            HStack(alignment: .top, spacing: 0) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color(hex: "#D4960A"))
                    .frame(width: 3)
                    .padding(.trailing, 12)
                Text(insight)
                    .font(.pixelSystem(size: 13))
                    .foregroundColor(Color(hex: "#2D2B26").opacity(0.7))
                    .italic()
                    .lineSpacing(4)
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(hex: "#FFFAF0"))
            )
        }
        .frame(maxWidth: 480)
    }
}

struct ExampleCard: View {
    let label: String
    let text: String
    let color: Color
    let bgColor: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(.pixelSystem(size: 9, weight: .bold, design: .monospaced))
                .foregroundColor(color)
            Text(text)
                .font(.pixelSystem(size: 12, design: .monospaced))
                .foregroundColor(Color(hex: "#2D2B26"))
                .lineSpacing(3)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(bgColor)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(color.opacity(0.3), lineWidth: 1)
                )
        )
    }
}

// MARK: - Apply It (Quiz)

struct ApplyItContent: View {
    let instruction: String
    let originalPrompt: String
    let options: [QuizOption]
    let correctFeedback: String
    let wrongFeedback: String
    @Binding var selectedAnswer: String?
    @Binding var answerSubmitted: Bool
    @Binding var isCorrect: Bool
    let teacherColor: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Instruction
            Text(instruction)
                .font(.pixelSystem(size: 13))
                .foregroundColor(Color(hex: "#888888"))

            // Original prompt card
            VStack(alignment: .leading, spacing: 6) {
                Text("ORIGINAL PROMPT")
                    .font(.pixelSystem(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(Color(hex: "#D4960A"))
                Text(originalPrompt)
                    .font(.pixelSystem(size: 13, design: .monospaced))
                    .foregroundColor(Color(hex: "#2D2B26"))
                    .lineSpacing(4)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color(hex: "#FFFAF0"))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(Color(hex: "#D4960A").opacity(0.3), lineWidth: 1.5)
                    )
            )

            // Options
            ForEach(options) { option in
                QuizOptionRow(
                    option: option,
                    selectedAnswer: selectedAnswer,
                    answerSubmitted: answerSubmitted,
                    onSelect: {
                        guard !answerSubmitted else { return }
                        withAnimation(.easeInOut(duration: 0.15)) {
                            selectedAnswer = option.id
                        }
                        SoundManager.shared.playTap()
                        // Auto-submit after selection
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                answerSubmitted = true
                                isCorrect = option.correct
                                if option.correct {
                                    SoundManager.shared.playSuccess()
                                } else {
                                    SoundManager.shared.playError()
                                }
                            }
                        }
                    }
                )
            }

            // Feedback
            if answerSubmitted {
                FeedbackBubble(
                    text: isCorrect ? correctFeedback : wrongFeedback,
                    isCorrect: isCorrect,
                    color: isCorrect ? Color(hex: "#6BCB77") : Color(hex: "#E06050")
                )
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .frame(maxWidth: 480)
    }
}

// MARK: - Field Mission (Scenario Quiz)

struct FieldMissionContent: View {
    let scenario: String
    let task: String
    let options: [QuizOption]
    let correctFeedback: String
    let wrongFeedback: String
    @Binding var selectedAnswer: String?
    @Binding var answerSubmitted: Bool
    @Binding var isCorrect: Bool
    let teacherColor: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Scenario card
            VStack(alignment: .leading, spacing: 8) {
                Text("🌍 SCENARIO")
                    .font(.pixelSystem(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(Color(hex: "#E0508C"))
                Text(scenario)
                    .font(.pixelSystem(size: 13))
                    .foregroundColor(Color(hex: "#2D2B26"))
                    .lineSpacing(4)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.white)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(Color(hex: "#E0508C").opacity(0.3), lineWidth: 1.5)
                    )
            )

            // Task
            Text(task)
                .font(.pixelSystem(size: 14, weight: .bold))
                .foregroundColor(Color(hex: "#2D2B26"))

            // Options
            ForEach(options) { option in
                QuizOptionRow(
                    option: option,
                    selectedAnswer: selectedAnswer,
                    answerSubmitted: answerSubmitted,
                    onSelect: {
                        guard !answerSubmitted else { return }
                        withAnimation(.easeInOut(duration: 0.15)) {
                            selectedAnswer = option.id
                        }
                        SoundManager.shared.playTap()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                answerSubmitted = true
                                isCorrect = option.correct
                                if option.correct {
                                    SoundManager.shared.playSuccess()
                                } else {
                                    SoundManager.shared.playError()
                                }
                            }
                        }
                    }
                )
            }

            // Feedback
            if answerSubmitted {
                FeedbackBubble(
                    text: isCorrect ? correctFeedback : wrongFeedback,
                    isCorrect: isCorrect,
                    color: isCorrect ? Color(hex: "#6BCB77") : Color(hex: "#E0508C")
                )
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .frame(maxWidth: 480)
    }
}

// MARK: - Shared Quiz Components

struct QuizOptionRow: View {
    let option: QuizOption
    let selectedAnswer: String?
    let answerSubmitted: Bool
    let onSelect: () -> Void

    private var isSelected: Bool { selectedAnswer == option.id }

    private var borderColor: Color {
        guard answerSubmitted && isSelected else {
            return isSelected ? Color(hex: "#D4960A") : Color(hex: "#EBE8DF")
        }
        return option.correct ? Color(hex: "#6BCB77") : Color(hex: "#E06050")
    }

    private var bgColor: Color {
        guard answerSubmitted else {
            return isSelected ? Color(hex: "#FFF8F0") : Color.white
        }
        if isSelected {
            return option.correct ? Color(hex: "#F0FFF4") : Color(hex: "#FFF5F5")
        }
        // Show correct answer when wrong one was picked
        if answerSubmitted && option.correct {
            return Color(hex: "#F0FFF4").opacity(0.5)
        }
        return Color.white.opacity(answerSubmitted ? 0.5 : 1)
    }

    private var letterColor: Color {
        guard answerSubmitted && isSelected else {
            return isSelected ? Color(hex: "#D4960A") : Color(hex: "#B0A898")
        }
        return option.correct ? Color(hex: "#6BCB77") : Color(hex: "#E06050")
    }

    var body: some View {
        Button(action: onSelect) {
            HStack(alignment: .top, spacing: 12) {
                // Letter badge
                ZStack {
                    Circle()
                        .fill(letterColor.opacity(0.15))
                        .frame(width: 28, height: 28)
                    if answerSubmitted && isSelected {
                        Image(systemName: option.correct ? "checkmark" : "xmark")
                            .font(.pixelSystem(size: 11, weight: .bold))
                            .foregroundColor(letterColor)
                    } else {
                        Text(option.id.uppercased())
                            .font(.pixelSystem(size: 12, weight: .bold))
                            .foregroundColor(letterColor)
                    }
                }

                Text(option.text)
                    .font(.pixelSystem(size: 12))
                    .foregroundColor(Color(hex: "#2D2B26").opacity(answerSubmitted && !isSelected && !option.correct ? 0.4 : 1))
                    .lineSpacing(3)
                    .multilineTextAlignment(.leading)

                Spacer()
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(bgColor)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(borderColor, lineWidth: isSelected ? 2 : 1)
                    )
            )
        }
        .buttonStyle(.plain)
        .disabled(answerSubmitted)
        .opacity(answerSubmitted && !isSelected && !option.correct ? 0.5 : 1)
    }
}

struct FeedbackBubble: View {
    let text: String
    let isCorrect: Bool
    let color: Color

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            RoundedRectangle(cornerRadius: 2)
                .fill(color)
                .frame(width: 3)
                .padding(.trailing, 12)
            Text(text)
                .font(.pixelSystem(size: 12, weight: .medium))
                .foregroundColor(Color(hex: "#2D2B26").opacity(0.8))
                .lineSpacing(4)
                .italic()
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(isCorrect ? Color(hex: "#F0FFF4") : Color(hex: "#FFF5F5"))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(color.opacity(0.2), lineWidth: 1)
                )
        )
    }
}

// MARK: - Summary Content

struct SummaryContent: View {
    let recap: [String]
    let xpReward: Int
    let badge: String?
    let teacherColor: Color

    @State private var showCelebration = false
    @State private var xpScale: CGFloat = 0.3

    var body: some View {
        ZStack {
            VStack(spacing: 20) {
                ZStack {
                    // Confetti behind XP
                    if showCelebration {
                        ConfettiBurstView(count: 25, colors: [
                            Color(hex: "#D4960A"), Color(hex: "#6BCB77"), teacherColor, .orange, .purple
                        ])
                    }

                    VStack(spacing: 4) {
                        Text("+\(xpReward) XP")
                            .font(.pixelSystem(size: 28, weight: .black, design: .monospaced))
                            .foregroundColor(Color(hex: "#D4960A"))
                            .scaleEffect(xpScale)
                        if let badge = badge {
                            Text("🏅 \(badge)")
                                .font(.pixelSystem(size: 14, weight: .bold))
                                .foregroundColor(teacherColor)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("WHAT YOU LEARNED")
                        .font(.pixelSystem(size: 9, weight: .bold, design: .monospaced))
                        .foregroundColor(Color(hex: "#2D2B26").opacity(0.4))

                    ForEach(Array(recap.enumerated()), id: \.offset) { i, item in
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.pixelSystem(size: 14))
                                .foregroundColor(Color(hex: "#6BCB77"))
                            Text(item)
                                .font(.pixelSystem(size: 13))
                                .foregroundColor(Color(hex: "#2D2B26"))
                        }
                        .opacity(showCelebration ? 1 : 0)
                        .offset(y: showCelebration ? 0 : 10)
                        .animation(.easeOut(duration: 0.4).delay(0.3 + Double(i) * 0.1), value: showCelebration)
                    }
                }
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(hex: "#F0FFF4"))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color(hex: "#6BCB77").opacity(0.3), lineWidth: 1)
                        )
                )
            }
            .frame(maxWidth: 480)
        }
        .onAppear {
            SoundManager.shared.playSuccess()
            withAnimation(.spring(response: 0.5, dampingFraction: 0.6)) {
                xpScale = 1.0
            }
            withAnimation(.easeOut(duration: 0.3).delay(0.2)) {
                showCelebration = true
            }
        }
    }
}

#Preview {
    LessonModalView(
        lesson: LessonLibrary.all["prompt-clarity"]!,
        onComplete: { _ in },
        onClose: {}
    )
}

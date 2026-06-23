import SwiftUI

// MARK: - Prompt Playground View

struct PromptPlaygroundView: View {
    let scenario: PlaygroundScenario
    let onComplete: (Int) -> Void  // XP earned
    let onClose: () -> Void
    @EnvironmentObject var appState: AppState

    @State private var promptText = ""
    @State private var analysis: PromptAnalysis? = nil
    @State private var showHints = false
    @State private var currentHint = 0
    @State private var showResult = false
    @State private var submitted = false

    private var teacher: PetCharacter? {
        PetCharacter.all[scenario.teacher]
    }

    private var wordCount: Int {
        promptText.split(separator: " ").count
    }

    var body: some View {
        VStack(spacing: 0) {
            // Top bar
            PlaygroundTopBar(
                scenario: scenario,
                teacher: teacher,
                onClose: onClose
            )

            if showResult, let result = analysis {
                // Result screen
                PlaygroundResultView(
                    analysis: result,
                    scenario: scenario,
                    teacher: teacher,
                    userPrompt: promptText,
                    onRetry: {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            showResult = false
                            submitted = false
                            analysis = nil
                        }
                    },
                    onComplete: {
                        let xp = Int(Double(scenario.xpReward) * scenario.difficulty.xpMultiplier)
                        let scaled = max(10, xp * result.overallScore / 100)
                        onComplete(scaled)
                    }
                )
            } else {
                // Editor + live feedback
                HStack(spacing: 0) {
                    // Left: prompt editor
                    promptEditor

                    // Divider
                    Rectangle()
                        .fill(Color(hex: "#EBE8DF"))
                        .frame(width: 1)

                    // Right: live analysis panel
                    analysisPanel
                        .frame(width: 240)
                }
            }
        }
        .background(Color(hex: "#FFFDF8"))
    }

    // MARK: - Prompt Editor

    private var promptEditor: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Mission briefing
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Text("MISSION")
                        .font(.pixelSystem(size: 8, weight: .bold, design: .monospaced))
                        .foregroundColor(scenario.difficulty.color)
                    Text(scenario.difficulty.rawValue.uppercased())
                        .font(.pixelSystem(size: 7, weight: .bold, design: .monospaced))
                        .foregroundColor(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(scenario.difficulty.color)
                        .cornerRadius(3)
                }
                Text(scenario.mission)
                    .font(.pixelSystem(size: 12))
                    .foregroundColor(Color(hex: "#2D2B26").opacity(0.7))
                    .lineSpacing(3)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(scenario.difficulty.color.opacity(0.06))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(scenario.difficulty.color.opacity(0.15), lineWidth: 1)
                    )
            )

            // Context card
            HStack(alignment: .top, spacing: 0) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(teacher?.color ?? .gray)
                    .frame(width: 3)
                    .padding(.trailing, 10)
                VStack(alignment: .leading, spacing: 2) {
                    Text("CONTEXT")
                        .font(.pixelSystem(size: 7, weight: .bold, design: .monospaced))
                        .foregroundColor(Color(hex: "#2D2B26").opacity(0.3))
                    Text(scenario.context)
                        .font(.pixelSystem(size: 11))
                        .foregroundColor(Color(hex: "#2D2B26").opacity(0.6))
                        .lineSpacing(2)
                }
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(hex: "#FFF8F0"))
            )

            // Text editor
            VStack(alignment: .leading, spacing: 4) {
                Text("YOUR PROMPT")
                    .font(.pixelSystem(size: 8, weight: .bold, design: .monospaced))
                    .foregroundColor(Color(hex: "#2D2B26").opacity(0.3))

                TextEditor(text: $promptText)
                    .font(.pixelSystem(size: 12, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .padding(10)
                    .frame(minHeight: 140)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.white)
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(Color(hex: "#E8E6E0"), lineWidth: 1)
                            )
                    )
                    .onChange(of: promptText) { _ in
                        if wordCount >= 10 {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                analysis = PromptAnalyzer.analyze(prompt: promptText, scenario: scenario)
                            }
                        }
                    }

                HStack {
                    Text("\(wordCount) words")
                        .font(.pixelSystem(size: 9, design: .monospaced))
                        .foregroundColor(wordCount < 15 ? Color(hex: "#E06050") : Color(hex: "#6BCB77"))

                    Spacer()

                    // Hints button
                    Button(action: { withAnimation { showHints.toggle() } }) {
                        HStack(spacing: 3) {
                            Image(systemName: "lightbulb")
                                .font(.pixelSystem(size: 9))
                            Text("Hint")
                                .font(.pixelSystem(size: 9, weight: .semibold))
                        }
                        .foregroundColor(Color(hex: "#D4960A"))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color(hex: "#FFF8F0"))
                        .cornerRadius(6)
                    }
                    .buttonStyle(.plain)

                    // Submit
                    Button(action: submitPrompt) {
                        Text("Evaluate")
                            .font(.pixelSystem(size: 11, weight: .bold))
                            .foregroundColor(wordCount >= 15 ? .white : Color(hex: "#B0A898"))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 6)
                            .background(wordCount >= 15 ? Color(hex: "#2D2B26") : Color(hex: "#E0DDD6"))
                            .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                    .disabled(wordCount < 15)
                }
            }

            // Hints
            if showHints {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(0...min(currentHint, scenario.hints.count - 1), id: \.self) { i in
                        HStack(alignment: .top, spacing: 6) {
                            Text("💡")
                                .font(.pixelSystem(size: 10))
                            Text(scenario.hints[i])
                                .font(.pixelSystem(size: 11))
                                .foregroundColor(Color(hex: "#D4960A"))
                        }
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                    if currentHint < scenario.hints.count - 1 {
                        Button("Show next hint") {
                            withAnimation { currentHint += 1 }
                        }
                        .font(.pixelSystem(size: 10, weight: .semibold))
                        .foregroundColor(Color(hex: "#D4960A").opacity(0.6))
                        .buttonStyle(.plain)
                    }
                }
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(hex: "#FFFAF0"))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color(hex: "#D4960A").opacity(0.15), lineWidth: 1)
                        )
                )
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }

            Spacer(minLength: 0)
        }
        .padding(16)
    }

    // MARK: - Live Analysis Panel

    private var analysisPanel: some View {
        VStack(spacing: 16) {
            // Teacher
            if let t = teacher {
                VStack(spacing: 4) {
                    CharacterImage(t.id, size: 40)
                        .charIdle(t.id)
                        .petBreathing()
                    Text(t.name)
                        .font(.pixelSystem(size: 10, weight: .semibold))
                        .foregroundColor(t.color)
                    Text("is watching...")
                        .font(.pixelSystem(size: 8))
                        .foregroundColor(Color(hex: "#2D2B26").opacity(0.3))
                }
            }

            Divider()

            // Required elements checklist
            VStack(alignment: .leading, spacing: 8) {
                Text("ELEMENTS")
                    .font(.pixelSystem(size: 8, weight: .bold, design: .monospaced))
                    .foregroundColor(Color(hex: "#2D2B26").opacity(0.3))

                ForEach(scenario.requiredElements) { element in
                    let score = analysis?.scores[element.id] ?? 0
                    HStack(spacing: 6) {
                        Image(systemName: score >= 0.6 ? "checkmark.circle.fill" : "circle")
                            .font(.pixelSystem(size: 11))
                            .foregroundColor(score >= 0.6 ? Color(hex: "#6BCB77") : Color(hex: "#E8E6E0"))

                        VStack(alignment: .leading, spacing: 1) {
                            Text(element.name)
                                .font(.pixelSystem(size: 10, weight: .semibold))
                                .foregroundColor(Color(hex: "#2D2B26"))
                            // Score bar
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    RoundedRectangle(cornerRadius: 2)
                                        .fill(Color(hex: "#EBE8DF"))
                                    RoundedRectangle(cornerRadius: 2)
                                        .fill(score >= 0.6 ? Color(hex: "#6BCB77") : Color(hex: "#D4960A"))
                                        .frame(width: geo.size.width * score)
                                        .animation(.easeOut(duration: 0.3), value: score)
                                }
                            }
                            .frame(height: 3)
                        }
                    }
                }
            }

            // Bonus elements
            if !scenario.bonusElements.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("BONUS")
                        .font(.pixelSystem(size: 8, weight: .bold, design: .monospaced))
                        .foregroundColor(Color(hex: "#D4960A").opacity(0.5))

                    ForEach(scenario.bonusElements) { element in
                        let score = analysis?.scores[element.id] ?? 0
                        HStack(spacing: 6) {
                            Image(systemName: score >= 0.6 ? "star.fill" : "star")
                                .font(.pixelSystem(size: 9))
                                .foregroundColor(score >= 0.6 ? Color(hex: "#D4960A") : Color(hex: "#E8E6E0"))
                            Text(element.name)
                                .font(.pixelSystem(size: 9))
                                .foregroundColor(Color(hex: "#2D2B26").opacity(0.6))
                        }
                    }
                }
            }

            Divider()

            // Live score
            if let result = analysis {
                VStack(spacing: 4) {
                    Text(result.grade.rawValue)
                        .font(.pixelSystem(size: 28, weight: .black, design: .monospaced))
                        .foregroundColor(result.grade.color)
                    Text("\(result.overallScore)%")
                        .font(.pixelSystem(size: 11, weight: .bold, design: .monospaced))
                        .foregroundColor(Color(hex: "#2D2B26").opacity(0.5))
                    Text("Live Score")
                        .font(.pixelSystem(size: 8, design: .monospaced))
                        .foregroundColor(Color(hex: "#2D2B26").opacity(0.3))
                }
            } else {
                Text("Start typing...")
                    .font(.pixelSystem(size: 10))
                    .foregroundColor(Color(hex: "#2D2B26").opacity(0.3))
            }

            Spacer()
        }
        .padding(16)
        .background(Color(hex: "#FAFAF6"))
    }

    // MARK: - Actions

    private func submitPrompt() {
        guard wordCount >= 15 else { return }
        let result = PromptAnalyzer.analyze(prompt: promptText, scenario: scenario)
        withAnimation(.easeInOut(duration: 0.3)) {
            analysis = result
            submitted = true
            showResult = true
        }
        if result.overallScore >= 70 {
            SoundManager.shared.playSuccess()
        } else {
            SoundManager.shared.playError()
        }
    }
}

// MARK: - Top Bar

struct PlaygroundTopBar: View {
    let scenario: PlaygroundScenario
    let teacher: PetCharacter?
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 6) {
            HStack {
                HStack(spacing: 6) {
                    Text("PROMPT PLAYGROUND")
                        .font(.pixelSystem(size: 9, weight: .bold, design: .monospaced))
                        .foregroundColor(scenario.difficulty.color)
                    Text("•")
                        .foregroundColor(Color(hex: "#E8E6E0"))
                    Text(scenario.title)
                        .font(.pixelSystem(size: 11, weight: .semibold))
                        .foregroundColor(Color(hex: "#2D2B26"))
                }

                Spacer()

                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.pixelSystem(size: 11, weight: .bold))
                        .foregroundColor(Color(hex: "#2D2B26").opacity(0.4))
                        .frame(width: 24, height: 24)
                        .background(Color(hex: "#F0F0EC"))
                        .cornerRadius(12)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.white)
    }
}

// MARK: - Result View

struct PlaygroundResultView: View {
    let analysis: PromptAnalysis
    let scenario: PlaygroundScenario
    let teacher: PetCharacter?
    let userPrompt: String
    let onRetry: () -> Void
    let onComplete: () -> Void

    @State private var showContent = false

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Grade
                ZStack {
                    if showContent {
                        ConfettiBurstView(
                            count: analysis.overallScore >= 70 ? 30 : 0,
                            colors: [analysis.grade.color, .yellow, .orange]
                        )
                    }
                    VStack(spacing: 6) {
                        Text(analysis.grade.rawValue)
                            .font(.pixelSystem(size: 48, weight: .black, design: .monospaced))
                            .foregroundColor(analysis.grade.color)
                        Text(analysis.grade.label)
                            .font(.pixelSystem(size: 14, weight: .bold))
                            .foregroundColor(Color(hex: "#2D2B26"))
                        Text("\(analysis.overallScore)% score")
                            .font(.pixelSystem(size: 11, design: .monospaced))
                            .foregroundColor(Color(hex: "#2D2B26").opacity(0.4))
                    }
                }
                .scaleEffect(showContent ? 1 : 0.5)
                .opacity(showContent ? 1 : 0)

                // Teacher feedback
                if let t = teacher {
                    HStack(alignment: .top, spacing: 10) {
                        CharacterImage(t.id, size: 36)
                            .charIdle(t.id)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(t.name)
                                .font(.pixelSystem(size: 10, weight: .bold))
                                .foregroundColor(t.color)
                            Text(teacherFeedback)
                                .font(.pixelSystem(size: 12))
                                .foregroundColor(Color(hex: "#2D2B26").opacity(0.7))
                                .italic()
                                .lineSpacing(3)
                        }
                    }
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(t.color.opacity(0.05))
                    )
                }

                // Element breakdown
                VStack(alignment: .leading, spacing: 8) {
                    Text("BREAKDOWN")
                        .font(.pixelSystem(size: 8, weight: .bold, design: .monospaced))
                        .foregroundColor(Color(hex: "#2D2B26").opacity(0.3))

                    ForEach(analysis.feedback) { item in
                        HStack(spacing: 8) {
                            Image(systemName: item.passed ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .font(.pixelSystem(size: 13))
                                .foregroundColor(item.passed ? Color(hex: "#6BCB77") : Color(hex: "#E06050"))
                            VStack(alignment: .leading, spacing: 1) {
                                Text(item.element)
                                    .font(.pixelSystem(size: 11, weight: .semibold))
                                    .foregroundColor(Color(hex: "#2D2B26"))
                                if !item.passed {
                                    Text(item.message)
                                        .font(.pixelSystem(size: 9))
                                        .foregroundColor(Color(hex: "#E06050").opacity(0.7))
                                }
                            }
                            Spacer()
                        }
                    }
                }
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.white)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color(hex: "#E8E6E0"), lineWidth: 1)
                        )
                )

                // Strengths & improvements
                HStack(alignment: .top, spacing: 12) {
                    if !analysis.strengths.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("STRENGTHS")
                                .font(.pixelSystem(size: 8, weight: .bold, design: .monospaced))
                                .foregroundColor(Color(hex: "#6BCB77"))
                            ForEach(analysis.strengths, id: \.self) { s in
                                HStack(spacing: 4) {
                                    Text("✓")
                                        .font(.pixelSystem(size: 9, weight: .bold))
                                        .foregroundColor(Color(hex: "#6BCB77"))
                                    Text(s)
                                        .font(.pixelSystem(size: 10))
                                        .foregroundColor(Color(hex: "#2D2B26"))
                                }
                            }
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 10).fill(Color(hex: "#F0FFF4")))
                    }

                    if !analysis.improvements.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("IMPROVE")
                                .font(.pixelSystem(size: 8, weight: .bold, design: .monospaced))
                                .foregroundColor(Color(hex: "#E06050"))
                            ForEach(analysis.improvements, id: \.self) { s in
                                HStack(spacing: 4) {
                                    Text("→")
                                        .font(.pixelSystem(size: 9, weight: .bold))
                                        .foregroundColor(Color(hex: "#E06050"))
                                    Text(s)
                                        .font(.pixelSystem(size: 10))
                                        .foregroundColor(Color(hex: "#2D2B26"))
                                }
                            }
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 10).fill(Color(hex: "#FFF5F5")))
                    }
                }

                // Run for real — execute the graded prompt in-app
                if analysis.overallScore >= 40 {
                    RunForRealSection(prompt: userPrompt, scenario: scenario, teacher: teacher)
                }

                // Action buttons
                HStack(spacing: 12) {
                    Button(action: onRetry) {
                        Text("Try Again")
                            .font(.pixelSystem(size: 12, weight: .semibold))
                            .foregroundColor(Color(hex: "#2D2B26"))
                            .padding(.horizontal, 20)
                            .padding(.vertical, 10)
                            .background(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(Color(hex: "#E8E6E0"), lineWidth: 1.5)
                            )
                    }
                    .buttonStyle(.plain)

                    if analysis.overallScore >= 40 {
                        Button(action: onComplete) {
                            HStack(spacing: 4) {
                                Text("Claim \(earnedXP) XP")
                                    .font(.pixelSystem(size: 12, weight: .bold))
                                Image(systemName: "arrow.right")
                                    .font(.pixelSystem(size: 10))
                            }
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
            .padding(24)
        }
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                showContent = true
            }
        }
    }

    private var earnedXP: Int {
        let base = Int(Double(scenario.xpReward) * scenario.difficulty.xpMultiplier)
        return max(10, base * analysis.overallScore / 100)
    }

    private var teacherFeedback: String {
        switch analysis.grade {
        case .s: return "Incredible. That prompt is production-ready. I have nothing to add."
        case .a: return "Really solid work. You clearly understand what AI needs to do great work."
        case .b: return "Good foundation! A few more details and this would be excellent."
        case .c: return "You're on the right track, but AI would need more context to do this well."
        case .d: return "The idea is there, but the prompt needs more structure and specificity."
        case .f: return "Let's start over. Think about what AI needs to know to help you."
        }
    }
}

#Preview {
    PromptPlaygroundView(
        scenario: PlaygroundLibrary.scenarios[0],
        onComplete: { _ in },
        onClose: {}
    )
    .environmentObject(AppState())
    .frame(width: 700, height: 550)
}

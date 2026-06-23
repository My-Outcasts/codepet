import SwiftUI

/// In-app practice space for a skill-card exercise (SkillChallenge).
///
/// PRACTICE MODEL: the user does the directing. They read the goal, **write the
/// prompt themselves** (graded live), then run it against a private practice
/// SANDBOX — never their real project (see PracticeSandbox). Afterwards they
/// review the diff and confirm it met the goal. Claude does the mechanical edit;
/// the skill being practiced is writing the instruction and judging the result.
///
/// Reuses `CodeExecutionView` (defined in RunForRealSection.swift).
struct ExerciseWorkspaceView: View {
    let challenge: SkillChallenge
    let character: PetCharacter
    var onClose: () -> Void = {}

    @EnvironmentObject private var hookInstaller: HookInstaller
    @EnvironmentObject private var challengeProgress: ChallengeProgress
    @EnvironmentObject private var appState: AppState

    @StateObject private var runner = ClaudeCodeRunner()
    @State private var promptText = ""
    @State private var sandboxPath = ""
    @State private var sandboxError: String? = nil
    @State private var showFile = false
    @State private var showExample = false

    private var primaryFile: String { PracticeSandbox.primaryFile(forSkill: challenge.skillId) }

    private var grade: PracticePromptGrader.Grade? {
        let words = promptText.split { $0 == " " || $0 == "\n" }.count
        guard words >= 6 else { return nil }
        return PracticePromptGrader.grade(prompt: promptText, goal: challenge.acceptanceCriteria)
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    topBar
                    exerciseHeader
                    sandboxRow
                    hooksNotice
                    filePreview
                    promptCard
                    if let g = grade { gradeBanner(g) }
                    runControls

                    if !runner.events.isEmpty {
                        CodeExecutionView(events: runner.events, accent: character.color)
                    }
                    if !runner.fileDiffs.isEmpty {
                        FileDiffView(diffs: runner.fileDiffs, accent: character.color)
                    }
                    if let err = sandboxError {
                        banner(err, bg: Color(hex: "#F7E3DE"), fg: Color(hex: "#8A3324"))
                    }
                    if case .failed(let reason) = runner.state {
                        banner(reason, bg: Color(hex: "#F7E3DE"), fg: Color(hex: "#8A3324"))
                    }
                    if case .finished = runner.state {
                        reviewStep
                    }

                    Color.clear.frame(height: 1).id("ex_bottom")
                }
                .padding(16)
            }
            .onChange(of: runner.events.count) { _ in
                withAnimation { proxy.scrollTo("ex_bottom", anchor: .bottom) }
            }
        }
        .background(character.color.opacity(0.05))
        .onAppear { prepareSandbox(); hookInstaller.checkInstallation() }
        .onDisappear { runner.cancel() }
    }

    // MARK: - Top bar (close)

    private var topBar: some View {
        HStack(alignment: .top, spacing: 10) {
            CharacterImage(character.id, size: 28)
            Text(coachLine ?? "Run complete — judge the result below.")
                .font(.pixelSystem(size: 13))
                .foregroundColor(Color(hex: "#2D2B26"))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Color(hex: "#2D2B26").opacity(0.6))
                    .frame(width: 28, height: 28)
                    .background(Color(hex: "#F0F0EC"))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Header

    private var exerciseHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(challenge.title)
                    // Match the "Practice" heading's typeface (Inter), not the
                    // blocky Minecraft pixel font that pixelSystem uses at ≥18pt.
                    .font(CodepetTheme.inter(20, weight: .bold))
                    .foregroundColor(Color(hex: "#2D2B26"))
                Spacer()
                difficultyBadge
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("GOAL")
                    .font(.pixelSystem(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(Color(hex: "#2D2B26").opacity(0.45))
                Text(challenge.acceptanceCriteria)
                    .font(.pixelSystem(size: 15))
                    .foregroundColor(Color(hex: "#2D2B26").opacity(0.75))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 10).fill(character.color.opacity(0.10)))
        }
    }

    private var difficultyBadge: some View {
        let (label, color): (String, Color) = {
            switch challenge.difficulty {
            case .starter:  return ("STARTER", Color(hex: "#3FA66A"))
            case .practice: return ("PRACTICE", Color(hex: "#7B6BD8"))
            case .stretch:  return ("STRETCH", Color(hex: "#E08A3C"))
            case .expert:   return ("EXPERT", Color(hex: "#7B3FE4"))
            }
        }()
        return Text(label)
            .font(.pixelSystem(size: 10, weight: .bold, design: .monospaced))
            .foregroundColor(.white)
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(RoundedRectangle(cornerRadius: 5).fill(color))
    }

    // MARK: - Sandbox notice + reset

    private var sandboxRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "shield.lefthalf.filled")
                .font(.system(size: 11))
                .foregroundColor(Color(hex: "#3FA66A"))
            Text("Practice copy — your real projects are never touched")
                .font(.pixelSystem(size: 11))
                .foregroundColor(Color(hex: "#2D2B26").opacity(0.6))
            Spacer()
            Button("Reset") { resetSandbox() }
                .font(.pixelSystem(size: 11, weight: .semibold))
                .foregroundColor(Color(hex: "#2D2B26"))
                .padding(.horizontal, 9).padding(.vertical, 4)
                .background(Color(hex: "#F0F0EC")).cornerRadius(6)
                .buttonStyle(.plain)
                .disabled(runner.isRunning)
        }
    }

    // MARK: - Reflection hooks notice (auto-completion from real sessions)

    /// Practice runs here never need hooks — they drive `claude` directly and the
    /// user marks the result complete. But to ALSO auto-complete skills from the
    /// user's real Claude Code sessions, the reflection hooks must be installed
    /// (NarrativeEnricher reads the captured events). Surface that one-time setup
    /// here while it's missing; the card disappears once `status == .installed`.
    @ViewBuilder
    private var hooksNotice: some View {
        switch hookInstaller.status {
        case .installed:
            EmptyView()

        case .notInstalled:
            hooksCard(icon: "link.badge.plus", title: "Auto-complete from real coding") {
                Text("Practice here works as-is. To also have your real Claude Code sessions complete skills automatically, install CodePet's reflection hooks — a one-time setup.")
                    .font(.pixelSystem(size: 12))
                    .foregroundColor(Color(hex: "#2D2B26").opacity(0.6))
                    .fixedSize(horizontal: false, vertical: true)
                hooksButton(icon: "doc.on.clipboard", title: "Copy setup command",
                            fill: character.color) { hookInstaller.install() }
            }

        case .installing:
            hooksCard(icon: "checkmark.circle.fill", title: "Command copied") {
                Text("Open Terminal → paste (⌘V) → press Enter. Then tap “I've done it”.")
                    .font(.pixelSystem(size: 12))
                    .foregroundColor(Color(hex: "#2D2B26").opacity(0.6))
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 10) {
                    hooksButton(icon: "checkmark", title: "I've done it",
                                fill: Color(hex: "#3FA66A")) { hookInstaller.verifyInstallation() }
                    Button("Copy again") { hookInstaller.install() }
                        .font(.pixelSystem(size: 11, weight: .semibold))
                        .foregroundColor(character.color)
                        .buttonStyle(.plain)
                }
            }

        case .failed(let error):
            hooksCard(icon: "exclamationmark.triangle.fill", title: "Setup failed") {
                Text(error)
                    .font(.pixelSystem(size: 11, design: .monospaced))
                    .foregroundColor(Color(hex: "#8A3324"))
                    .fixedSize(horizontal: false, vertical: true)
                hooksButton(icon: "arrow.clockwise", title: "Try again",
                            fill: character.color) { hookInstaller.install() }
            }
        }
    }

    @ViewBuilder
    private func hooksCard<Content: View>(icon: String, title: String,
                                          @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundColor(character.color)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 7) {
                Text(title)
                    .font(.pixelSystem(size: 13, weight: .bold))
                    .foregroundColor(Color(hex: "#2D2B26"))
                content()
            }
            Spacer(minLength: 0)
        }
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(character.color.opacity(0.08)))
    }

    private func hooksButton(icon: String, title: String, fill: Color,
                             action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon).font(.system(size: 11))
                Text(title).font(.pixelSystem(size: 12, weight: .bold))
            }
            .foregroundColor(.white)
            .padding(.horizontal, 13).padding(.vertical, 6)
            .background(fill).cornerRadius(8)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Sandbox file preview

    private var filePreview: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button(action: { withAnimation { showFile.toggle() } }) {
                HStack(spacing: 5) {
                    Image(systemName: showFile ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9))
                    Image(systemName: "doc.text")
                        .font(.system(size: 10))
                    Text(primaryFile)
                        .font(.pixelSystem(size: 12, design: .monospaced))
                }
                .foregroundColor(Color(hex: "#2D2B26").opacity(0.7))
            }
            .buttonStyle(.plain)

            if showFile {
                ScrollView {
                    Text(PracticeSandbox.currentContents(of: primaryFile) ?? "—")
                        .font(.pixelSystem(size: 13, design: .monospaced))
                        .foregroundColor(Color(hex: "#2D2B26").opacity(0.8))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .padding(8)
                }
                .frame(maxHeight: 300)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color(hex: "#2D2B26").opacity(0.05)))
            }
        }
    }

    // MARK: - Prompt (the user writes this)

    private var promptCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text("YOUR PROMPT")
                    .font(.pixelSystem(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(Color(hex: "#2D2B26").opacity(0.45))
                Text("— you write this, then run it")
                    .font(.pixelSystem(size: 10))
                    .foregroundColor(Color(hex: "#2D2B26").opacity(0.35))
            }
            ZStack(alignment: .topLeading) {
                if promptText.isEmpty {
                    Text("Tell Claude Code exactly what to change in \(primaryFile)…")
                        .font(.pixelSystem(size: 15))
                        .foregroundColor(Color(hex: "#2D2B26").opacity(0.3))
                        .padding(.horizontal, 11).padding(.vertical, 12)
                }
                TextEditor(text: $promptText)
                    .font(.pixelSystem(size: 15))
                    .frame(minHeight: 150, maxHeight: 320)
                    .padding(6)
                    .scrollContentBackground(.hidden)
                    .disabled(runner.isRunning)
            }
            .background(RoundedRectangle(cornerRadius: 10).fill(character.color.opacity(0.08)))

            exampleDisclosure
        }
    }

    // MARK: - Example prompt (beginner reference)

    /// A read-only worked example for the current skill. We deliberately DON'T
    /// offer a "use this" button — the practice is writing the prompt yourself
    /// (see HANDOFF-practice-space.md: "The USER writes the prompt from scratch").
    /// This just shows a beginner what a complete, well-formed prompt looks like.
    private var exampleDisclosure: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button(action: { withAnimation { showExample.toggle() } }) {
                HStack(spacing: 5) {
                    Image(systemName: "lightbulb")
                        .font(.system(size: 10))
                    Text(showExample ? "Hide example" : "New to this? See an example prompt")
                        .font(.pixelSystem(size: 13, weight: .semibold))
                    Image(systemName: showExample ? "chevron.up" : "chevron.down")
                        .font(.system(size: 8))
                }
                .foregroundColor(character.color)
            }
            .buttonStyle(.plain)

            if showExample {
                VStack(alignment: .leading, spacing: 5) {
                    Text(examplePrompt)
                        .font(.pixelSystem(size: 14))
                        .foregroundColor(Color(hex: "#2D2B26").opacity(0.85))
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                    Text("Notice it has all four: a clear action, where it goes, enough detail, and what 'done' looks like. Now write your own version.")
                        .font(.pixelSystem(size: 12))
                        .foregroundColor(Color(hex: "#2D2B26").opacity(0.5))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color(hex: "#2D2B26").opacity(0.04)))
            }
        }
    }

    /// A concrete model prompt per skill, referencing the sandbox file.
    private var examplePrompt: String {
        switch challenge.skillId {
        case "component_composition":
            return "Move the hero section at the top of \(primaryFile) into a new file app/components/Hero.tsx, then import it back into \(primaryFile) so the page still looks exactly the same. Keep all its text and styles."
        case "loading_error_states":
            return "In \(primaryFile), find where the class data is loaded and wrap it in a try/catch. Show a short, friendly message if it fails, so the page doesn't break when the data can't load."
        case "form_validation_ux":
            return "In the sign-up form in \(primaryFile), check the email field isn't empty and contains an '@' before submitting. If it's invalid, show an inline message next to the field so the user knows what to fix."
        case "accessibility_basics":
            return "Add descriptive alt text to every image in \(primaryFile) that's missing it, so screen readers can describe each one. Don't change anything else."
        case "responsive_layout":
            return "In \(primaryFile), make the layout responsive: replace the fixed pixel widths with fluid sizing and add a mobile breakpoint so the hero and class cards stack instead of overflowing on a narrow screen. Keep the desktop look the same."
        case "performance":
            return "In \(primaryFile), the filtered/sorted list is recomputed on every render. Wrap that derived list in useMemo so it only recalculates when the classes or the filter query actually change. Keep the behavior identical."
        default:
            return "In \(primaryFile), make the change described in the goal, and say what should be true when it's done so that the result matches: \(challenge.acceptanceCriteria.lowercased())."
        }
    }

    private func gradeBanner(_ g: PracticePromptGrader.Grade) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .center, spacing: 10) {
                Text(g.letter)
                    .font(.pixelSystem(size: 26, weight: .black, design: .monospaced))
                    .foregroundColor(gradeColor(g.score))
                VStack(alignment: .leading, spacing: 1) {
                    Text("Prompt score: \(g.score)%")
                        .font(.pixelSystem(size: 12, weight: .bold))
                        .foregroundColor(Color(hex: "#2D2B26"))
                    Text(g.score >= 75
                         ? "Strong prompt — ready to run."
                         : "A clear prompt has all four. Add the unchecked ones:")
                        .font(.pixelSystem(size: 12))
                        .foregroundColor(Color(hex: "#2D2B26").opacity(0.55))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
            }
            VStack(alignment: .leading, spacing: 5) {
                ForEach(Array(g.checklist.enumerated()), id: \.offset) { _, c in
                    HStack(alignment: .top, spacing: 7) {
                        Image(systemName: c.met ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 13))
                            .foregroundColor(c.met ? Color(hex: "#3FA66A") : Color(hex: "#2D2B26").opacity(0.28))
                            .padding(.top, 1)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(c.label)
                                .font(.pixelSystem(size: 13, weight: .semibold))
                                .foregroundColor(c.met ? Color(hex: "#2D2B26").opacity(0.45) : Color(hex: "#2D2B26"))
                                .strikethrough(c.met, color: Color(hex: "#2D2B26").opacity(0.35))
                            if !c.met {
                                Text(c.hint)
                                    .font(.pixelSystem(size: 12))
                                    .foregroundColor(Color(hex: "#2D2B26").opacity(0.6))
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(gradeColor(g.score).opacity(0.10)))
    }

    private func gradeColor(_ score: Int) -> Color {
        switch score {
        case 75...: return Color(hex: "#3FA66A")
        case 50..<75: return Color(hex: "#D4960A")
        default: return Color(hex: "#E06050")
        }
    }

    // MARK: - Run controls

    private var runControls: some View {
        HStack(spacing: 10) {
            if runner.isRunning {
                Button(action: { runner.cancel() }) {
                    Text("Stop")
                        .font(.pixelSystem(size: 14, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 16).padding(.vertical, 7)
                        .background(Color(hex: "#C7563F")).cornerRadius(8)
                }
                .buttonStyle(.plain)
                HStack(spacing: 5) {
                    ProgressView().controlSize(.small)
                    Text("\(character.name) is working…")
                        .font(.pixelSystem(size: 12))
                        .foregroundColor(Color(hex: "#2D2B26").opacity(0.6))
                }
            } else {
                Button(action: startRun) {
                    Text("▶  Run my prompt")
                        .font(.pixelSystem(size: 14, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 16).padding(.vertical, 7)
                        .background(canRun ? character.color : Color(hex: "#D0D0CC"))
                        .cornerRadius(8)
                }
                .buttonStyle(.plain)
                .disabled(!canRun)
                if promptText.trimmingCharacters(in: .whitespaces).isEmpty {
                    Text("Write your prompt first")
                        .font(.pixelSystem(size: 11))
                        .foregroundColor(Color(hex: "#2D2B26").opacity(0.45))
                }
            }
        }
    }

    private var canRun: Bool {
        !sandboxPath.isEmpty && !promptText.trimmingCharacters(in: .whitespaces).isEmpty
    }

    // MARK: - Actions

    private func prepareSandbox() {
        do { sandboxPath = try PracticeSandbox.prepare() }
        catch { sandboxError = "Couldn't set up the practice sandbox: \(error.localizedDescription)" }
    }

    private func resetSandbox() {
        do { sandboxPath = try PracticeSandbox.reset(); SoundManager.shared.playTap() }
        catch { sandboxError = "Couldn't reset the sandbox: \(error.localizedDescription)" }
    }

    private func startRun() {
        SoundManager.shared.playTap()
        runner.run(prompt: promptText, projectDir: sandboxPath)
    }

    // MARK: - Coaching (rule-based — no model calls)

    private var coachLine: String? {
        switch runner.state {
        case .idle:
            return "Read the goal, peek at \(primaryFile) if you like, then write the prompt YOU think will get it done. I'll run it on the practice copy."
        case .running:
            if let last = runner.events.last(where: { $0.kind == .toolUse }) {
                switch last.toolName {
                case "Write":     return "It made a new file — that's the structure your prompt asked for."
                case "Edit", "MultiEdit": return "Editing in place to wire things together without breaking them."
                case "Bash":      return "Running a command to check its work."
                case "Read", "Glob", "Grep": return "Exploring the code before changing it — measure twice, cut once."
                default:          return "Watch each step — was this what your prompt intended?"
                }
            }
            return "Reading the project to find where your change belongs."
        case .finished:
            return nil // review step takes over
        case .failed:
            return nil
        }
    }

    // MARK: - Review (the second half of the practice)

    private var reviewStep: some View {
        judgePrompt
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color(hex: "#3FA66A").opacity(0.12)))
    }

    /// Before completion: judge the result, then mark it complete.
    private var judgePrompt: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                CharacterImage(character.id, size: 24)
                Text("Your turn to judge it")
                    .font(.pixelSystem(size: 15, weight: .bold))
                    .foregroundColor(Color(hex: "#2D2B26"))
            }
            Text("Did it meet the goal — \(challenge.acceptanceCriteria)? Open \(primaryFile) above to see the result, and ask yourself *why* this change helps.")
                .font(.pixelSystem(size: 13))
                .foregroundColor(Color(hex: "#2D2B26").opacity(0.7))
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                Button(action: markComplete) {
                    Text("✓  Mark complete")
                        .font(.pixelSystem(size: 14, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 14).padding(.vertical, 6)
                        .background(Color(hex: "#3FA66A")).cornerRadius(8)
                }
                .buttonStyle(.plain)
                Button("Reset & try again") { resetSandbox(); runner.cancel() }
                    .font(.pixelSystem(size: 14, weight: .semibold))
                    .foregroundColor(Color(hex: "#2D2B26"))
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(Color(hex: "#F0F0EC")).cornerRadius(8)
                    .buttonStyle(.plain)
            }
        }
    }

    private func markComplete() {
        // Award the exercise's bonus XP (once), mark it complete, then fire the
        // full-screen completion celebration (presented at the app root).
        let xp = challenge.difficulty.xpReward
        // Single source of truth for "newly completed" — awards XP exactly once,
        // matching the auto-detected path in CodePetApp.
        let newlyCompleted = challengeProgress.markCompleted(challenge.id)
        if newlyCompleted {
            appState.addXP(xp)
        }
        SoundManager.shared.playTap()
        let next = challengeProgress.nextChallenge(after: challenge)
        appState.exerciseCelebration = ExerciseCelebration(
            earnedXP: newlyCompleted ? xp : 0, nextChallengeId: next?.id)
    }

    private func banner(_ text: String, bg: Color, fg: Color) -> some View {
        Text(text)
            .font(.pixelSystem(size: 12))
            .foregroundColor(fg)
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 10).fill(bg))
    }
}

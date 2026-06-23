import SwiftUI

/// The "Run for real" step for the Prompt Playground.
///
/// After the user's prompt is graded, this executes that prompt against a private
/// practice SANDBOX (see PracticeSandbox) — never the user's real project — and
/// streams the results back in-app. It closes the loop: write the prompt → grade
/// it → run it on a safe copy → see what it actually did.
///
/// PLAN-USAGE: the run drives the user's own `claude` (their existing
/// subscription + auth), so there's no separate API key or billing. Coaching is
/// rule-based and costs zero extra tokens.
struct RunForRealSection: View {
    let prompt: String
    let scenario: PlaygroundScenario
    let teacher: PetCharacter?

    @StateObject private var runner = ClaudeCodeRunner()
    @State private var expanded = false
    @State private var sandboxPath = ""
    @State private var sandboxError: String? = nil

    private var accent: Color { teacher?.color ?? Color(hex: "#7B6BD8") }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            if expanded {
                sandboxRow
                runControls

                if !runner.events.isEmpty {
                    CodeExecutionView(events: runner.events, accent: accent)
                }
                if !runner.fileDiffs.isEmpty {
                    FileDiffView(diffs: runner.fileDiffs, accent: accent)
                }
                if let coach = coachLine {
                    coachBubble(coach)
                }
                if let err = sandboxError {
                    banner(err, bg: Color(hex: "#FFF5F5"), fg: Color(hex: "#8A3324"))
                }
                if case .failed(let reason) = runner.state {
                    banner(reason, bg: Color(hex: "#FFF5F5"), fg: Color(hex: "#8A3324"))
                }
                if case .finished = runner.state {
                    banner("Run finished on the practice copy. Open the changed files to see what your prompt produced — and ask why.",
                           bg: Color(hex: "#F0FFF4"), fg: Color(hex: "#2D6A3E"))
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(accent.opacity(0.06))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(accent.opacity(0.18), lineWidth: 1))
        )
        .onDisappear { runner.cancel() }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "play.circle.fill")
                .font(.system(size: 16))
                .foregroundColor(accent)
            VStack(alignment: .leading, spacing: 1) {
                Text("RUN FOR REAL")
                    .font(.pixelSystem(size: 8, weight: .bold, design: .monospaced))
                    .foregroundColor(accent)
                Text("Execute your prompt on a safe practice copy")
                    .font(.pixelSystem(size: 10))
                    .foregroundColor(Color(hex: "#2D2B26").opacity(0.5))
            }
            Spacer()
            if !expanded {
                Button(action: { withAnimation { expanded = true }; prepareSandbox() }) {
                    Text("Start")
                        .font(.pixelSystem(size: 11, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 16).padding(.vertical, 6)
                        .background(accent).cornerRadius(8)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Sandbox notice + reset

    private var sandboxRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "shield.lefthalf.filled")
                .font(.system(size: 11))
                .foregroundColor(Color(hex: "#3FA66A"))
            Text("Practice copy — your real projects are never touched")
                .font(.pixelSystem(size: 9))
                .foregroundColor(Color(hex: "#2D2B26").opacity(0.6))
            Spacer()
            Button("Reset") { resetSandbox() }
                .font(.pixelSystem(size: 9, weight: .semibold))
                .foregroundColor(Color(hex: "#2D2B26"))
                .padding(.horizontal, 9).padding(.vertical, 4)
                .background(Color(hex: "#F0F0EC")).cornerRadius(6)
                .buttonStyle(.plain)
                .disabled(runner.isRunning)
        }
    }

    // MARK: - Run controls

    private var runControls: some View {
        HStack(spacing: 10) {
            if runner.isRunning {
                Button(action: { runner.cancel() }) {
                    Text("Stop")
                        .font(.pixelSystem(size: 12, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 16).padding(.vertical, 7)
                        .background(Color(hex: "#C7563F")).cornerRadius(8)
                }
                .buttonStyle(.plain)
                HStack(spacing: 5) {
                    ProgressView().controlSize(.small)
                    Text("\(teacher?.name ?? "Claude") is working…")
                        .font(.pixelSystem(size: 10))
                        .foregroundColor(Color(hex: "#2D2B26").opacity(0.6))
                }
            } else {
                Button(action: startRun) {
                    Text("▶  Run in Codepet")
                        .font(.pixelSystem(size: 12, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 16).padding(.vertical, 7)
                        .background(sandboxPath.isEmpty ? Color(hex: "#D0D0CC") : accent)
                        .cornerRadius(8)
                }
                .buttonStyle(.plain)
                .disabled(sandboxPath.isEmpty || prompt.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
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
        if sandboxPath.isEmpty { prepareSandbox() }
        guard !sandboxPath.isEmpty else { return }
        SoundManager.shared.playTap()
        runner.run(prompt: prompt, projectDir: sandboxPath)
    }

    // MARK: - Coaching (rule-based — no model calls)

    private var coachLine: String? {
        switch runner.state {
        case .idle:
            return "When you're ready, hit Run. I'll run your prompt on the practice copy and explain the why."
        case .running:
            if let last = runner.events.last(where: { $0.kind == .toolUse }) {
                switch last.toolName {
                case "Write":
                    return "See how it created a new file? That's the structure your prompt asked for."
                case "Edit", "MultiEdit":
                    return "Editing in place — wiring the new code in so nothing breaks."
                case "Bash":
                    return "Running a command to check its own work. Worth copying that habit."
                case "Read", "Glob", "Grep":
                    return "Exploring the code before changing anything — measure twice, cut once."
                default:
                    return "Follow each step — was this what your prompt intended?"
                }
            }
            return "Reading the project first to find where the change belongs."
        case .finished:
            return "Done! Compare what it did against your goal: \(scenario.mission)"
        case .failed:
            return nil
        }
    }

    private func coachBubble(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            if let t = teacher { CharacterImage(t.id, size: 26) }
            Text(text)
                .font(.pixelSystem(size: 11))
                .foregroundColor(Color(hex: "#2D2B26"))
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 10).fill(accent.opacity(0.12)))
        }
    }

    private func banner(_ text: String, bg: Color, fg: Color) -> some View {
        Text(text)
            .font(.pixelSystem(size: 10))
            .foregroundColor(fg)
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 10).fill(bg))
    }
}

// =============================================================================
// MARK: - CodeExecutionView — live feed of what Claude Code did
// =============================================================================

struct CodeExecutionView: View {
    let events: [ClaudeCodeRunner.StreamEvent]
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("WHAT CLAUDE CODE DID")
                .font(.pixelSystem(size: 12, weight: .bold, design: .monospaced))
                .foregroundColor(Color(hex: "#2D2B26").opacity(0.45))
            VStack(alignment: .leading, spacing: 5) {
                ForEach(events) { event in
                    row(for: event)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color(hex: "#2D2B26").opacity(0.05)))
        }
    }

    @ViewBuilder
    private func row(for event: ClaudeCodeRunner.StreamEvent) -> some View {
        switch event.kind {
        case .assistantText:
            Text(event.text)
                .font(.pixelSystem(size: 14))
                .foregroundColor(Color(hex: "#2D2B26").opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)
        case .toolUse:
            HStack(spacing: 6) {
                Image(systemName: icon(for: event.toolName))
                    .font(.system(size: 10))
                    .foregroundColor(accent)
                Text(event.text)
                    .font(.pixelSystem(size: 13, design: .monospaced))
                    .foregroundColor(Color(hex: "#2D2B26").opacity(0.8))
                    .lineLimit(2)
            }
        case .toolResult:
            Text(event.text)
                .font(.pixelSystem(size: 12, design: .monospaced))
                .foregroundColor(Color(hex: "#2D2B26").opacity(0.5))
                .lineLimit(3)
                .padding(.leading, 16)
        case .result:
            Text(event.text)
                .font(.pixelSystem(size: 13, weight: .medium))
                .foregroundColor(Color(hex: "#2D2B26").opacity(0.7))
        case .system:
            EmptyView()
        }
    }

    private func icon(for tool: String?) -> String {
        switch tool {
        case "Write": return "doc.badge.plus"
        case "Edit", "MultiEdit": return "pencil"
        case "Bash": return "terminal"
        case "Read": return "doc.text"
        case "Glob", "Grep": return "magnifyingglass"
        default: return "wrench.and.screwdriver"
        }
    }
}

// =============================================================================
// MARK: - FileDiffView — real before/after for each changed file
// =============================================================================

/// Shows the actual line-level changes Claude made to each file this run, built
/// from a pre-run snapshot diffed against what's now on disk (see
/// ClaudeCodeRunner.computeDiffs). One collapsible block per file.
struct FileDiffView: View {
    let diffs: [ClaudeCodeRunner.FileDiff]
    let accent: Color

    /// Files start expanded so the change is visible without an extra tap.
    @State private var collapsed: Set<UUID> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("BEFORE → AFTER")
                .font(.pixelSystem(size: 12, weight: .bold, design: .monospaced))
                .foregroundColor(Color(hex: "#2D2B26").opacity(0.45))
            ForEach(diffs) { diff in
                diffBlock(diff)
            }
        }
    }

    @ViewBuilder
    private func diffBlock(_ diff: ClaudeCodeRunner.FileDiff) -> some View {
        let isOpen = !collapsed.contains(diff.id)
        VStack(alignment: .leading, spacing: 0) {
            Button(action: {
                withAnimation {
                    if isOpen { collapsed.insert(diff.id) } else { collapsed.remove(diff.id) }
                }
            }) {
                HStack(spacing: 6) {
                    Image(systemName: isOpen ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9))
                    Image(systemName: diff.isNewFile ? "doc.badge.plus" : "pencil")
                        .font(.system(size: 10))
                        .foregroundColor(accent)
                    Text(diff.fileName)
                        .font(.pixelSystem(size: 12, design: .monospaced))
                    if diff.isNewFile {
                        Text("NEW")
                            .font(.pixelSystem(size: 8, weight: .bold, design: .monospaced))
                            .foregroundColor(.white)
                            .padding(.horizontal, 4).padding(.vertical, 1)
                            .background(RoundedRectangle(cornerRadius: 3).fill(Color(hex: "#3FA66A")))
                    }
                    Spacer()
                    Text(changeSummary(diff))
                        .font(.pixelSystem(size: 9, design: .monospaced))
                        .foregroundColor(Color(hex: "#2D2B26").opacity(0.4))
                }
                .foregroundColor(Color(hex: "#2D2B26").opacity(0.75))
                .padding(.vertical, 7).padding(.horizontal, 9)
            }
            .buttonStyle(.plain)

            if isOpen {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(diff.lines) { line in
                            diffLine(line)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
                }
                .frame(maxHeight: 320)
            }
        }
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(hex: "#2D2B26").opacity(0.05)))
    }

    @ViewBuilder
    private func diffLine(_ line: ClaudeCodeRunner.FileDiff.Line) -> some View {
        let (bg, fg, gutter): (Color, Color, String) = {
            switch line.kind {
            case .added:   return (Color(hex: "#3FA66A").opacity(0.16), Color(hex: "#1E6B40"), "+")
            case .removed: return (Color(hex: "#E06050").opacity(0.16), Color(hex: "#8A3324"), "−")
            case .context: return (.clear, Color(hex: "#2D2B26").opacity(0.55), " ")
            }
        }()
        HStack(alignment: .top, spacing: 6) {
            Text(gutter)
                .font(.pixelSystem(size: 12, design: .monospaced))
                .foregroundColor(fg.opacity(0.7))
                .frame(width: 10, alignment: .center)
            Text(line.text.isEmpty ? " " : line.text)
                .font(.pixelSystem(size: 12, design: .monospaced))
                .foregroundColor(fg)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
        .padding(.horizontal, 9).padding(.vertical, 1)
        .background(bg)
    }

    private func changeSummary(_ diff: ClaudeCodeRunner.FileDiff) -> String {
        let added = diff.lines.filter { $0.kind == .added }.count
        let removed = diff.lines.filter { $0.kind == .removed }.count
        return "+\(added) −\(removed)"
    }
}

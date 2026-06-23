import SwiftUI

/// Markdown-aware typewriter: reveals a tinted `AttributedString` one
/// character at a time, with a blinking cursor `▌` at the tail. After typing
/// completes the cursor blinks for ~2.4s and then fades out.
///
/// Differs from `DemoTypewriterText` (plain-text only) by keeping the full
/// markdown style runs — bold/italic/code/link tinting all survive the
/// reveal because we slice a fully-tinted AttributedString rather than
/// re-parsing a string prefix.
///
/// Typing starts iff `isActive` is true. Pass `isActive: whatHappenedVisible`
/// (or similar) so the typewriter waits for its parent's reveal cue.
struct MarkdownTypewriterText: View {
    let markdown: String
    var charactersPerSecond: Double = 80
    var font: Font = .system(size: 14)
    var foregroundColor: Color = Color(hex: "#2D2B26")
    var cursorColor: Color = Color(hex: "#7C3AED")
    /// Gate from the parent. When this flips to true, typing starts.
    var isActive: Bool
    /// Highlight + link dictionary terms in the revealed text (see
    /// `Text(markdown:linkTerms:)`). Taps only open a term AFTER typing finishes
    /// — while typing, a tap skips to the end instead.
    var linkTerms: Bool = false

    @State private var fullAttr: AttributedString = AttributedString()
    @State private var revealedCount: Int = 0
    @State private var typingStarted: Bool = false
    @State private var typingDone: Bool = false
    @State private var cursorOn: Bool = true
    @State private var cursorFaded: Bool = false
    @State private var typingTask: Task<Void, Never>? = nil
    @State private var cursorBlinkTask: Task<Void, Never>? = nil

    var body: some View {
        let totalChars = fullAttr.characters.count
        let safeCount = min(revealedCount, totalChars)
        let endIndex = fullAttr.index(fullAttr.startIndex, offsetByCharacters: safeCount)
        let visibleAttr = AttributedString(fullAttr[fullAttr.startIndex..<endIndex])

        // Cursor visibility is driven by `cursorOn` via foreground color
        // (vs opacity) so the character keeps its space — no layout shift on
        // each blink. When cursor has fully faded after typing completes,
        // `cursorFaded` becomes true and we omit the cursor character entirely.
        let cursorAttr: AttributedString = {
            var c = AttributedString("▌")
            c.foregroundColor = cursorOn ? cursorColor : Color.clear
            return c
        }()

        let textView = Text(visibleAttr + (cursorFaded ? AttributedString("") : cursorAttr))
            .font(font)
            .foregroundColor(foregroundColor)
            .multilineTextAlignment(.leading)
            .lineSpacing(3)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .onAppear {
                fullAttr = CodepetMarkdown.attributedString(from: markdown, linkTerms: linkTerms)
                if isActive { beginTyping() }
            }
            .onChange(of: isActive) { _, nowActive in
                if nowActive && !typingStarted { beginTyping() }
            }
            .onDisappear {
                typingTask?.cancel()
                cursorBlinkTask?.cancel()
            }

        // While typing, the whole bubble is a tap target that skips to the end.
        // Once typing finishes we drop that gesture so taps fall through to the
        // term links instead.
        return Group {
            if typingDone {
                textView
            } else {
                textView
                    .contentShape(Rectangle())
                    .onTapGesture { skipToEnd() }
            }
        }
    }

    private func beginTyping() {
        guard !typingStarted else { return }
        typingStarted = true
        let total = fullAttr.characters.count
        let interval = max(0.005, 1.0 / charactersPerSecond)
        startCursorBlink()
        typingTask?.cancel()
        typingTask = Task { @MainActor in
            for _ in 0..<total {
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                if Task.isCancelled { return }
                if revealedCount < total { revealedCount += 1 }
            }
            typingDone = true
            // After ~2.4s of post-type blinking, fade out the cursor.
            try? await Task.sleep(nanoseconds: 2_400_000_000)
            if Task.isCancelled { return }
            cursorBlinkTask?.cancel()
            withAnimation(.easeOut(duration: 0.4)) {
                cursorFaded = true
            }
        }
    }

    private func startCursorBlink() {
        cursorBlinkTask?.cancel()
        cursorBlinkTask = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 500_000_000)
                if Task.isCancelled { return }
                cursorOn.toggle()
            }
        }
    }

    private func skipToEnd() {
        typingTask?.cancel()
        revealedCount = fullAttr.characters.count
        typingDone = true
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            if Task.isCancelled { return }
            cursorBlinkTask?.cancel()
            withAnimation(.easeOut(duration: 0.3)) {
                cursorFaded = true
            }
        }
    }
}

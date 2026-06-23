import SwiftUI

/// Session-level summary spoken in the pet's single voice.
/// Same shape as a turn bubble: pet avatar + bubble — so the page reads as
/// one continuous narration from the pet, not a separate report card.
struct SessionSummaryView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.uiLanguage) private var uiLanguage
    let summary: SessionSummary?
    var onTriggerSummary: () -> Void = {}
    /// When true, renders `summary.summary` via DemoTypewriterText (character
    /// reveal) and hides the manual "Summarize now" button in loading state.
    /// Used by Demo Mode for a one-shot dramatic reveal.
    var useTypewriter: Bool = false
    /// When false, the session has no tool events (no file edits, no bash
    /// commands) — just text-only turns. We show a quiet "no work yet"
    /// state instead of the "Summarize now" button.
    var hasMeaningfulWork: Bool = true

    @State private var petFloat = false
    @State private var petGlow: CGFloat = 0
    @State private var isRefreshing = false

    private var pet: PetCharacter? {
        PetCharacter.all[appState.activeChar]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            dividerLine

            HStack(alignment: .top, spacing: 10) {
                petAvatar(size: 36)
                Group {
                    if let summary = summary {
                        readyBubble(summary: summary)
                    } else {
                        loadingBubble
                    }
                }
            }
            .onAppear { startAnimations() }
            .onChange(of: summary?.generatedAt) { _ in
                isRefreshing = false
            }

            dividerLine
        }
    }

    private func startAnimations() {
        withAnimation(.easeInOut(duration: 3.2).repeatForever(autoreverses: true)) {
            petFloat = true
        }
        withAnimation(.easeInOut(duration: 2.8).repeatForever(autoreverses: true)) {
            petGlow = 1.0
        }
    }

    // MARK: - Ready state

    private func readyBubble(summary: SessionSummary) -> some View {
        PixelCard(
            fill: ReflectionTheme.bubbleAccentWash,
            borderColor: ReflectionTheme.accent,
            shadowOffset: 2,
            blockSize: 2,
            steps: 2,
            borderWidth: 2
        ) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 6) {
                    if let pet = pet {
                        Text(pet.name.uppercased())
                            .font(.pixelSystem(size: 10))
                            .tracking(1.0)
                            .foregroundColor(pet.color.opacity(0.85))
                        Text("·")
                            .foregroundColor(Color(hex: "#777065"))
                    }
                    Text(uiLanguage == .vi ? "TÓM TẮT PHIÊN" : "SESSION RECAP")
                        .font(.pixelSystem(size: 10))
                        .tracking(1.4)
                        .foregroundColor(ReflectionTheme.accent)

                    Spacer()

                    if !useTypewriter {
                        Button {
                            isRefreshing = true
                            onTriggerSummary()
                        } label: {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(ReflectionTheme.brandPurple.opacity(0.6))
                                .rotationEffect(.degrees(isRefreshing ? 360 : 0))
                                .animation(
                                    isRefreshing
                                        ? .linear(duration: 1).repeatForever(autoreverses: false)
                                        : .default,
                                    value: isRefreshing
                                )
                        }
                        .buttonStyle(.plain)
                        .help(uiLanguage == .vi ? "Cập nhật tóm tắt" : "Update summary")
                    }
                }

                if useTypewriter {
                    DemoTypewriterText(
                        text: summary.summary,
                        charactersPerSecond: 70,
                        font: CodepetTheme.body(18),
                        foregroundColor: Color(hex: "#2D2B26")
                    )
                } else {
                    Text(markdown: summary.summary)
                        .font(CodepetTheme.body(18))
                        .foregroundColor(Color(hex: "#2D2B26"))
                        .multilineTextAlignment(.leading)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if !summary.lesson.isEmpty {
                    lessonRow(summary.lesson)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func lessonRow(_ text: String) -> some View {
        PixelCard(
            fill: ReflectionTheme.lessonFill,
            borderColor: ReflectionTheme.lessonIconColor.opacity(0.30),
            shadowOffset: 2,
            blockSize: 3,
            steps: 2,
            borderWidth: 2
        ) {
            Text(text)
                .font(CodepetTheme.body(16, weight: .medium))
                .foregroundColor(ReflectionTheme.lessonTextColor)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Loading state

    private var loadingBubble: some View {
        PixelCard(
            fill: ReflectionTheme.bubbleAccentWash,
            borderColor: ReflectionTheme.accent,
            shadowOffset: 2,
            blockSize: 2,
            steps: 2,
            borderWidth: 2
        ) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    if let pet = pet {
                        Text(pet.name.uppercased())
                            .font(.pixelSystem(size: 10))
                            .tracking(1.0)
                            .foregroundColor(pet.color.opacity(0.85))
                        Text("·")
                            .foregroundColor(Color(hex: "#777065"))
                    }
                    Text(uiLanguage == .vi ? "TÓM TẮT PHIÊN" : "SESSION RECAP")
                        .font(.pixelSystem(size: 10))
                        .tracking(1.4)
                        .foregroundColor(ReflectionTheme.accent)
                }

                if hasMeaningfulWork {
                    Text(loadingHint)
                        .font(CodepetTheme.body(13))
                        .foregroundColor(Color(hex: "#777065"))

                    if !useTypewriter {
                        Button(action: onTriggerSummary) {
                            HStack(spacing: 6) {
                                Image(systemName: "sparkle")
                                Text(uiLanguage == .vi ? "Tóm tắt ngay" : "Summarize now")
                            }
                        }
                        .buttonStyle(PixelButtonStyle(
                            fill: ReflectionTheme.accent,
                            blockSize: 2,
                            borderWidth: 2,
                            shadowOffset: 2,
                            font: .pixelSystem(size: 12, weight: .semibold)
                        ))
                    }
                } else {
                    Text(uiLanguage == .vi
                         ? "Chưa có thay đổi code nào trong phiên này."
                         : "No code changes in this session yet.")
                        .font(CodepetTheme.body(12))
                        .foregroundColor(Color(hex: "#9E9689"))
                        .italic()
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Pet avatar (matches turn view)

    private func petAvatar(size: CGFloat) -> some View {
        ZStack {
            if let pet = pet {
                Circle()
                    .fill(pet.color.opacity(0.14))
                    .frame(width: size, height: size)
                    .overlay(
                        Circle()
                            .stroke(pet.color.opacity(0.35), lineWidth: 1.5)
                    )
                    .overlay(
                        Image(pet.imageName)
                            .resizable()
                            .interpolation(.none)
                            .scaledToFit()
                            .frame(width: size * 0.75, height: size * 0.75)
                            .scaleEffect(petFloat ? 1.02 : 0.98)
                            .offset(y: petFloat ? -1 : 1)
                            .frame(width: size, height: size)
                            .compositingGroup()
                            .clipShape(Circle())
                    )
            } else {
                Circle()
                    .fill(ReflectionTheme.accent.opacity(0.14))
                    .frame(width: size, height: size)
            }
        }
        .frame(width: size, height: size)
    }

    // MARK: - Helpers

    private var dividerLine: some View {
        Rectangle()
            .fill(ReflectionTheme.borderLight)
            .frame(maxWidth: .infinity)
            .frame(height: 1)
            .padding(.vertical, 16)
    }

    private var loadingHint: String {
        switch (useTypewriter, uiLanguage) {
        case (true,  .vi): return "Bấm ⌥5 để hiện reflection…"
        case (true,  .en): return "Press ⌥5 to reveal the reflection…"
        case (false, .vi): return "Đang ghép câu chuyện của bạn…"
        case (false, .en): return "Putting your story together…"
        }
    }
}

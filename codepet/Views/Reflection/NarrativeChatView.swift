import SwiftUI

/// Single-voice render for ONE Turn's Narrative.
/// The pet is the sole narrator — there is no AI/assistant counterpart.
/// One pet avatar on the left, one bubble on the right that contains the
/// pet's narration of what the user wanted, what happened, and (optionally)
/// the lesson it surfaces for them.
struct NarrativeChatTurnView: View {
    @EnvironmentObject var appState: AppState
    let narrative: Narrative
    /// When true, render the pet avatar to the left of the bubble. When
    /// false, the bubble takes full width with only a thin pet-color thread
    /// on its left edge — used for older turns so the avatar doesn't repeat.
    var showAvatar: Bool = true

    // Bubble entry animation
    @State private var didAppear = false
    // Staggered section reveals (header → whatYouWanted → whatHappened → lesson).
    // Each block fades in + slides up slightly.
    @State private var headerVisible = false
    @State private var whatYouWantedVisible = false
    @State private var whatHappenedVisible = false
    @State private var lessonVisible = false
    @State private var nextStepsVisible = false

    private var pet: PetCharacter? {
        PetCharacter.all[appState.activeChar]
    }

    private var petColor: Color {
        pet?.color ?? ReflectionTheme.accent
    }

    private var moodEnum: NarrativeMood {
        NarrativeMood(raw: narrative.mood)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            // Thread line (or avatar for the last turn)
            if showAvatar {
                PetMoodSprite(
                    characterId: appState.activeChar,
                    mood: moodEnum,
                    size: 40
                )
                .frame(width: 56, height: 56)
                .padding(.trailing, 8)
            } else {
                // Thread line connecting turns — tinted to mood color
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(
                        LinearGradient(
                            colors: [moodAccent.opacity(0.30), moodAccent.opacity(0.06)],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
                    .frame(width: 3)
                    .frame(maxHeight: .infinity)
                    .padding(.leading, 26)
                    .padding(.trailing, 35)
            }
            petBubble
                .scaleEffect(didAppear ? 1.0 : 0.6, anchor: .topLeading)
                .opacity(didAppear ? 1.0 : 0.0)
        }
        .onAppear { startAnimations() }
        // Intercept taps on highlighted glossary terms (codepetterm://<id>) and
        // deep-link into the Dictionary tab instead of opening a URL.
        .environment(\.openURL, OpenURLAction(handler: handleTermURL))
    }

    private func handleTermURL(_ url: URL) -> OpenURLAction.Result {
        guard url.scheme == "codepetterm" else { return .systemAction }
        let id = url.host ?? url.lastPathComponent
        guard !id.isEmpty else { return .systemAction }
        appState.pendingDictionaryTerm = id
        appState.selectedTab = .dictionary
        return .handled
    }

    private func startAnimations() {
        // Bubble container scales in (slower spring for premium feel).
        withAnimation(.spring(response: 0.7, dampingFraction: 0.7).delay(0.05)) {
            didAppear = true
        }
        // Stagger the content sections — slower, more breathing room. Each
        // section uses a longer fade + slide to feel deliberate, not rushed.
        withAnimation(.easeOut(duration: 0.5).delay(0.4)) {
            headerVisible = true
        }
        withAnimation(.easeOut(duration: 0.6).delay(0.9)) {
            whatYouWantedVisible = true
        }
        withAnimation(.easeOut(duration: 0.6).delay(1.6)) {
            whatHappenedVisible = true
        }
        // Lesson lands last with a bouncy spring + subtle rotation correction.
        withAnimation(.spring(response: 0.65, dampingFraction: 0.6).delay(2.8)) {
            lessonVisible = true
        }
        // Next steps advice appears after the lesson.
        withAnimation(.spring(response: 0.65, dampingFraction: 0.6).delay(3.4)) {
            nextStepsVisible = true
        }
    }

    // MARK: - Pet bubble (single voice)

    /// Each mood maps to a distinct brand-color wash so turns are visually varied.
    private var bubbleFill: Color {
        ReflectionTheme.bubbleFill(for: moodEnum)
    }

    private var moodAccent: Color {
        ReflectionTheme.moodAccentColor(for: moodEnum)
    }

    /// Whether the mood accent is too light for white text (e.g. yellow).
    private var badgeNeedsDarkText: Bool {
        moodEnum == .cheering
    }

    private var petBubble: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Floating title badge — sits above the card, overlapping its top edge
            if pet != nil && !narrative.title.isEmpty {
                titleBadge
                    .padding(.leading, 12)
                    .padding(.bottom, -8)
                    .zIndex(1)
                    .opacity(headerVisible ? 1 : 0)
                    .scaleEffect(headerVisible ? 1.0 : 0.7, anchor: .bottomLeading)
                    .offset(y: headerVisible ? 0 : 6)
            }

            PixelCard(
                fill: bubbleFill,
                borderColor: moodAccent.opacity(0.25),
                shadowOffset: 3,
                borderWidth: 2
            ) {
                bubbleContent
            }
            .overlay(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(moodAccent.opacity(0.55))
                    .frame(width: 4)
                    .padding(.vertical, 6)
            }
        }
    }

    private var titleBadge: some View {
        PixelCard(
            fill: moodAccent,
            borderColor: Color(hex: "#2D2B26").opacity(0.22),
            shadowOffset: 2,
            blockSize: 2,
            steps: 2,
            borderWidth: 2
        ) {
            HStack(spacing: 8) {
                Text(narrative.title)
                    .font(CodepetTheme.body(20, weight: .bold))
                    .foregroundColor(badgeNeedsDarkText ? Color(hex: "#412402") : .white)

                if moodEnum != .idle {
                    HStack(spacing: 4) {
                        Image(systemName: moodEnum.badgeIcon)
                            .font(.system(size: 11, weight: .semibold))
                        Text(narrative.mood)
                            .font(.pixelSystem(size: 11, weight: .semibold))
                    }
                    .foregroundColor(
                        badgeNeedsDarkText
                            ? Color(hex: "#412402").opacity(0.7)
                            : .white.opacity(0.85)
                    )
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Rectangle()
                            .fill(
                                badgeNeedsDarkText
                                    ? Color(hex: "#412402").opacity(0.12)
                                    : Color.white.opacity(0.2)
                            )
                    )
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }

    private var bubbleContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            whatYouWantedView
            dividerView
            whatHappenedView
            lessonView
            nextStepsView
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var whatYouWantedView: some View {
        Text(markdown: narrative.whatYouWanted, linkTerms: true)
            .font(CodepetTheme.body(18))
            .foregroundColor(Color(hex: "#2D2B26"))
            .multilineTextAlignment(.leading)
            .lineSpacing(3)
            .fixedSize(horizontal: false, vertical: true)
            .opacity(whatYouWantedVisible ? 1 : 0)
            .offset(x: whatYouWantedVisible ? 0 : -12, y: whatYouWantedVisible ? 0 : 8)
    }

    private var dividerView: some View {
        Rectangle()
            .fill(Color(hex: "#2D2B26").opacity(0.25))
            .frame(height: 2)
            .padding(.vertical, 2)
            .opacity(whatHappenedVisible ? 1 : 0)
            .scaleEffect(x: whatHappenedVisible ? 1.0 : 0.3, y: 1.0, anchor: .leading)
    }

    private var whatHappenedView: some View {
        MarkdownTypewriterText(
            markdown: narrative.whatHappened,
            charactersPerSecond: 150,
            font: CodepetTheme.body(18),
            isActive: whatHappenedVisible,
            linkTerms: true
        )
        .opacity(whatHappenedVisible ? 1 : 0)
        .offset(x: whatHappenedVisible ? 0 : -12, y: whatHappenedVisible ? 0 : 8)
    }

    @ViewBuilder
    private var lessonView: some View {
        if !narrative.lesson.isEmpty {
            lessonRow(narrative.lesson)
                .padding(.top, 4)
                .opacity(lessonVisible ? 1 : 0)
                .scaleEffect(lessonVisible ? 1.0 : 0.7, anchor: .topLeading)
                .rotationEffect(.degrees(lessonVisible ? 0 : -4), anchor: .topLeading)
                .offset(y: lessonVisible ? 0 : 12)
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
            Text(markdown: text, linkTerms: true)
                .font(CodepetTheme.body(16, weight: .medium))
                .foregroundColor(ReflectionTheme.lessonTextColor)
                .multilineTextAlignment(.leading)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var nextStepsView: some View {
        if !narrative.nextSteps.isEmpty {
            nextStepsRow(narrative.nextSteps)
                .padding(.top, 4)
                .opacity(nextStepsVisible ? 1 : 0)
                .scaleEffect(nextStepsVisible ? 1.0 : 0.7, anchor: .topLeading)
                .rotationEffect(.degrees(nextStepsVisible ? 0 : -4), anchor: .topLeading)
                .offset(y: nextStepsVisible ? 0 : 12)
        }
    }

    private func nextStepsRow(_ text: String) -> some View {
        PixelCard(
            fill: ReflectionTheme.nextStepsFill,
            borderColor: ReflectionTheme.nextStepsIconColor.opacity(0.30),
            shadowOffset: 2,
            blockSize: 3,
            steps: 2,
            borderWidth: 2
        ) {
            Text(markdown: text, linkTerms: true)
                .font(CodepetTheme.body(16, weight: .medium))
                .foregroundColor(ReflectionTheme.nextStepsTextColor)
                .multilineTextAlignment(.leading)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

}

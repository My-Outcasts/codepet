// codepet/Views/SplashView.swift
import SwiftUI

/// Brand splash — the first screen before sign-in. Faithful port of the web
/// `Splash` (dark cinematic: splash.jpg Ken Burns + scrim + pixel title +
/// purple pill). Click anywhere OR "Let's go" advances. English-only.
struct SplashView: View {
    var onContinue: (() -> Void)? = nil

    @State private var kenBurns = false
    @State private var glow = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// `.splash-sub` is per-word on the web (`.w` spans) so each word can rise on its
    /// own delay; split here so the stagger has something to stagger.
    private static let subtitleWords = "Let's learn how to run your company with AI."
        .split(separator: " ").map(String.init)

    var body: some View {
        ZStack {
            OnboardingContent.Palette.coldBg.ignoresSafeArea()

            // Slow Ken-Burns image layer — scale AND drift (`.splash:before`, 30s).
            GeometryReader { geo in
                let drift = OnboardingMotion.kenBurnsDrift(width: geo.size.width,
                                                           height: geo.size.height)
                Image("splash")
                    .resizable()
                    .interpolation(.high)
                    .scaledToFill()
                    .frame(width: geo.size.width, height: geo.size.height)
                    .scaleEffect(kenBurns ? OnboardingMotion.kenBurnsScale : 1.0)
                    .offset(x: kenBurns ? drift.width : 0, y: kenBurns ? drift.height : 0)
                    .clipped()
            }
            .ignoresSafeArea()

            // Readability scrim: flat darkening + a soft center vignette.
            Color(hex: "#0d0522").opacity(0.52).ignoresSafeArea()
            RadialGradient(colors: [.clear, Color(hex: "#0d0522").opacity(0.5)],
                           center: UnitPoint(x: 0.5, y: 0.46),
                           startRadius: 0, endRadius: 620)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()
                title
                subtitle
                if onContinue != nil {
                    Button { onContinue?() } label: {
                        Text("Let's go")
                            .font(CodepetTheme.body(14))
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                            .padding(.horizontal, 30)
                            .padding(.vertical, 12)
                            .background(Capsule().fill(CodepetTheme.accentPurple))
                            .overlay(Capsule().stroke(Color.white.opacity(0.22), lineWidth: 1))
                            .shadow(color: OnboardingContent.Palette.accentDeep.opacity(0.5), radius: 13, y: 8)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 32)
                    .riseIn(OnboardingMotion.riseSplash, delay: OnboardingMotion.splashButtonDelay)
                } else {
                    // Auth / cloud still resolving — passive loading affordance, NOT the
                    // interactive CTA (there's no onContinue to fire, so a "Let's go"
                    // button would be a silent no-op).
                    ProgressView()
                        .controlSize(.small)
                        .tint(.white)
                        .padding(.top, 34)
                }
                Spacer()
                Text(onContinue != nil ? "click anywhere to continue" : "Loading…")
                    .font(CodepetTheme.body(11))
                    .foregroundColor(.white)
                    .hintPulse()
                    .padding(.bottom, 22)
                    .riseIn(OnboardingMotion.riseSplash, delay: OnboardingMotion.splashHintDelay)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { onContinue?() }
        .onAppear {
            guard !reduceMotion else { return }
            let ken = Animation.easeInOut(duration: OnboardingMotion.kenBurnsSplash)
                .repeatForever(autoreverses: true)
            withAnimation(ken) { kenBurns = true }
            let g = Animation.easeInOut(duration: OnboardingMotion.glowPeriod / 2)
                .repeatForever(autoreverses: true)
                .delay(OnboardingMotion.glowDelay)
            withAnimation(g) { glow = true }
        }
    }

    /// `.splash-title` — riseIn, then an infinite glow pulse, with `titleSweep` over it.
    private var title: some View {
        let glowOpacity = glow ? OnboardingMotion.glowOpacityHigh : OnboardingMotion.glowOpacityLow
        let glowRadius = glow ? OnboardingMotion.glowRadiusHigh : OnboardingMotion.glowRadiusLow
        let text = Text("Codepet")
            .font(CodepetTheme.pixel(80))
            .tracking(2)
            .foregroundColor(.white)
        return text
            .shadow(color: Color(hex: "#a078ff").opacity(glowOpacity), radius: glowRadius)
            .shadow(color: Color(hex: "#220e40").opacity(0.7), radius: 0, x: 0, y: 3)
            .overlay(TitleSweep(mask: text))
            .riseIn(OnboardingMotion.riseSplash, delay: OnboardingMotion.splashTitleDelay)
    }

    /// `.splash-sub` — each word rises on its own delay (`.32s + i × 60ms`).
    private var subtitle: some View {
        HStack(spacing: 6) {
            ForEach(Array(Self.subtitleWords.enumerated()), id: \.offset) { i, word in
                Text(word)
                    .font(CodepetTheme.body(20))
                    .foregroundColor(.white)
                    .fixedSize()
                    .riseIn(OnboardingMotion.riseWord, delay: OnboardingMotion.wordDelay(i))
            }
        }
        .padding(.top, 20)
        .shadow(color: Color(hex: "#0a041e").opacity(0.7), radius: 9)
    }
}

#Preview {
    SplashView(onContinue: {})
}

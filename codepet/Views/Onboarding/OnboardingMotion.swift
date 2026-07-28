// codepet/Views/Onboarding/OnboardingMotion.swift
import SwiftUI

/// The motion layer for the splash + onboarding, ported 1:1 from the web's keyframes.
/// Durations, delays and easings are the CSS values, kept here as named constants so a
/// reviewer can diff them against the stylesheet instead of hunting through views.
///
/// Web reference (app.css):
///   @keyframes riseIn    { 0% { opacity:0; translate:0 16px } to { opacity:1; translate:0 } }
///   @keyframes kenburns  { 0% { scale(1) translate(0) } to { scale(1.08) translate(-1.2%,-1.6%) } }
///   @keyframes titleGlow { 0%,to { …30px glow } 50% { …52px glow } }
///   @keyframes titleSweep{ 0% { translate(-120%) } 55%,to { translate(120%) } }
///   @keyframes hintPulse { 0%,to { opacity:.42 } 50% { opacity:.72 } }
///   @keyframes twinkle   { 0%,to { opacity:.1; translateY(0) } 50% { opacity:.8; translateY(-6px) } }
///
/// Everything here is gated on Reduce Motion, mirroring the web's
/// `@media (prefers-reduced-motion: reduce)` block which disables the whole set.
enum OnboardingMotion {

    /// `cubic-bezier(.2,.7,.2,1)` — the shared entrance curve.
    static func entrance(_ duration: Double) -> Animation {
        .timingCurve(0.2, 0.7, 0.2, 1, duration: duration)
    }

    // riseIn durations
    static let riseSplash: Double = 0.9      // .splash-title / -btn / -hint
    static let riseWord: Double = 0.7        // .splash-sub .w
    static let riseCold: Double = 0.85       // .ob-cold-in > *
    static let riseStep: Double = 0.55       // .ob-body > *

    // riseIn delays
    static let splashTitleDelay: Double = 0.15
    static let splashButtonDelay: Double = 0.48
    static let splashHintDelay: Double = 0.66
    static let coldHeadlineDelay: Double = 0.10
    static let coldParagraphDelay: Double = 0.24
    static let coldChipsDelay: Double = 0.50
    static let stepHeadingDelay: Double = 0.04
    static let stepSubDelay: Double = 0.12
    static let stepRestDelay: Double = 0.20

    /// `.splash-sub .w { animation-delay: calc(.32s + var(--i) * 60ms) }`
    static func wordDelay(_ index: Int) -> Double {
        0.32 + Double(index) * 0.06
    }

    // Ken Burns — `.splash:before` 30s, `.ob-cold:after` 32s, both infinite alternate.
    static let kenBurnsSplash: Double = 30
    static let kenBurnsCold: Double = 32
    static let kenBurnsScale: CGFloat = 1.08
    /// translate(-1.2%, -1.6%) of the layer's own size, at full drift.
    static func kenBurnsDrift(width: CGFloat, height: CGFloat) -> CGSize {
        CGSize(width: -width * 0.012, height: -height * 0.016)
    }

    // titleGlow — 5s ease-in-out, 1.4s delay, infinite. CSS blur px ≈ 2× SwiftUI radius.
    static let glowPeriod: Double = 5
    static let glowDelay: Double = 1.4
    static let glowRadiusLow: CGFloat = 15    // 30px
    static let glowRadiusHigh: CGFloat = 26   // 52px
    static let glowOpacityLow: Double = 0.45
    static let glowOpacityHigh: Double = 0.78

    // titleSweep — 4.6s total: crosses over 55% (2.53s), then holds (2.07s). 1.7s delay.
    static let sweepCross: Double = 2.53
    static let sweepHold: Double = 2.07
    static let sweepDelay: Double = 1.7
    static let sweepFrom: CGFloat = -1.2
    static let sweepTo: CGFloat = 1.2

    // hintPulse — 2.8s ease-in-out, 1.6s delay, infinite.
    static let hintPeriod: Double = 2.8
    static let hintDelay: Double = 1.6
    static let hintOpacityLow: Double = 0.42
    static let hintOpacityHigh: Double = 0.72

    // .ob-art span — `transition: opacity 1.1s, transform 7s`, scale 1.07 → 1.
    // The web also offsets these by the pointer; that parallax is deliberately not
    // ported — mouse-tracking movement on the art was distracting in use.
    static let artCrossfade: Double = 1.1
    static let artSettle: Double = 7
    static let artEnterScale: CGFloat = 1.07
}

// MARK: - riseIn

/// `@keyframes riseIn` — fade up 16pt on the shared entrance curve.
private struct RiseIn: ViewModifier {
    let duration: Double
    let delay: Double
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        let on = shown || reduceMotion
        return content
            .opacity(on ? 1 : 0)
            .offset(y: on ? 0 : 16)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(OnboardingMotion.entrance(duration).delay(delay)) { shown = true }
            }
    }
}

extension View {
    /// Web `riseIn`. Defaults to the step-content timing (`.ob-body > *`).
    func riseIn(_ duration: Double = OnboardingMotion.riseStep, delay: Double = 0) -> some View {
        modifier(RiseIn(duration: duration, delay: delay))
    }
}

// MARK: - looping accents

/// `@keyframes hintPulse` — opacity breathing on the splash hint line.
private struct HintPulse: ViewModifier {
    @State private var up = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(reduceMotion ? OnboardingMotion.hintOpacityHigh
                                  : (up ? OnboardingMotion.hintOpacityHigh : OnboardingMotion.hintOpacityLow))
            .onAppear {
                guard !reduceMotion else { return }
                let a = Animation.easeInOut(duration: OnboardingMotion.hintPeriod / 2)
                    .repeatForever(autoreverses: true)
                    .delay(OnboardingMotion.hintDelay)
                withAnimation(a) { up = true }
            }
    }
}

extension View {
    func hintPulse() -> some View { modifier(HintPulse()) }
}

/// `@keyframes titleSweep` — a specular bar crossing the title, then pausing.
/// Masked to the content so it only lights the glyphs, like the web's `:after` on the
/// title with `background-clip`.
struct TitleSweep<Mask: View>: View {
    let mask: Mask
    @State private var armed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let bar = LinearGradient(
                colors: [.clear, Color.white.opacity(0.55), .clear],
                startPoint: .leading, endPoint: .trailing
            )
            .frame(width: max(40, w * 0.35))
            .blendMode(.plusLighter)

            if armed && !reduceMotion {
                bar.keyframeAnimator(initialValue: OnboardingMotion.sweepFrom, repeating: true) { view, x in
                    view.offset(x: x * w)
                } keyframes: { _ in
                    CubicKeyframe(OnboardingMotion.sweepTo, duration: OnboardingMotion.sweepCross)
                    LinearKeyframe(OnboardingMotion.sweepTo, duration: OnboardingMotion.sweepHold)
                }
            }
        }
        .mask(mask)
        .allowsHitTesting(false)
        .task {
            guard !reduceMotion else { return }
            try? await Task.sleep(nanoseconds: UInt64(OnboardingMotion.sweepDelay * 1_000_000_000))
            armed = true
        }
    }
}

// MARK: - art panel

/// One layer of `.ob-art`. Enters at `scale(1.07)` and settles to 1 over 7s while the
/// ZStack crossfades it in over 1.1s — the web's split
/// `transition: opacity 1.1s, transform 7s`. No pointer parallax by design.
struct OnboardingArtLayer: View {
    let name: String
    let width: CGFloat
    let grade: Color

    @State private var settled = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let scale: CGFloat = (settled || reduceMotion) ? 1.0 : OnboardingMotion.artEnterScale
        return Image(name)
            .resizable()
            .interpolation(.high)
            .scaledToFill()
            .frame(width: width)
            .frame(maxHeight: .infinity)
            .scaleEffect(scale)
            .clipped()
            .overlay(grade.blendMode(.softLight))
            .compositingGroup()
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeOut(duration: OnboardingMotion.artSettle)) { settled = true }
            }
    }
}

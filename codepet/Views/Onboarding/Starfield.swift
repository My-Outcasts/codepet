// codepet/Views/Onboarding/Starfield.swift
import SwiftUI

/// Normalize `value` within [minV, maxV] to [-1, 1], clamped. Port of the web
/// `lib/ui/useParallax` `clampNorm`. Free function so it unit-tests without a view.
func clampNorm(_ value: CGFloat, _ minV: CGFloat, _ maxV: CGFloat) -> CGFloat {
    if maxV <= minV { return 0 }
    let f = ((value - minV) / (maxV - minV)) * 2 - 1
    return max(-1, min(1, f))
}

/// 40 deterministic, gently-twinkling dots over the cold-open — port of the web
/// `components/ui/Starfield.tsx`. Decorative only (no hit-testing); gated on
/// reduce-motion, matching OnboardingColdOpen's existing convention.
struct Starfield: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    fileprivate struct Dot: Identifiable {
        let id: Int
        let x, y, size, dur, delay: Double
    }
    private static let dots: [Dot] = (0..<40).map { i in
        Dot(id: i,
            x: Double((i * 37) % 100), y: Double((i * 61) % 100),
            size: 1 + Double(i % 3), dur: 6 + Double(i % 5) * 2, delay: Double(i % 7) * 0.9)
    }

    var body: some View {
        if reduceMotion {
            Color.clear
        } else {
            GeometryReader { geo in
                ZStack {
                    ForEach(Self.dots) { d in
                        TwinklingDot(dot: d)
                            .position(x: geo.size.width * d.x / 100,
                                      y: geo.size.height * d.y / 100)
                    }
                }
            }
            .allowsHitTesting(false)
        }
    }

    fileprivate struct TwinklingDot: View {
        let dot: Dot
        @State private var bright = false
        var body: some View {
            Circle()
                .fill(Color.white.opacity(bright ? 0.9 : 0.25))
                .frame(width: dot.size, height: dot.size)
                .onAppear {
                    withAnimation(.easeInOut(duration: dot.dur)
                        .repeatForever(autoreverses: true).delay(dot.delay)) {
                        bright = true
                    }
                }
        }
    }
}

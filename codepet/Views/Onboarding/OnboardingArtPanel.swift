// codepet/Views/Onboarding/OnboardingArtPanel.swift
import SwiftUI

/// The onboarding card's left art panel — a port of the web `.ob-art`:
///
/// - every scene is a stacked layer and only the active one is visible, so a step
///   change is a 1.1s opacity crossfade (never a hard cut),
/// - the active layer slow-zooms from 1.07 → 1 over 7s,
/// - a per-step colour grade sits over the bottom 70% in soft-light.
///
/// The web also drifts these layers with the pointer; that is deliberately left
/// out — mouse-tracking movement on the step images read as distracting in use
/// (same call as PR #39). Only the cold-open's starfield/glow follows the pointer.
///
/// Width is owned by the caller (the web panel is `width: 42%` of the card).
struct OnboardingArtPanel: View {
    let step: Int

    @State private var zoomedIn = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var grade: Color {
        OnboardingContent.stepGrade[min(max(0, step), OnboardingContent.stepGrade.count - 1)]
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                OnboardingContent.Palette.coldBg
                ForEach(Array(OnboardingContent.stepArt.enumerated()), id: \.offset) { i, name in
                    let on = i == step
                    Image(name)
                        .resizable().interpolation(.high).scaledToFill()
                        .frame(width: geo.size.width, height: geo.size.height)
                        // Slow zoom: the incoming layer starts at 1.07 and settles to 1.
                        .scaleEffect(on && zoomedIn ? 1.0 : 1.07)
                        .opacity(on ? 1 : 0)
                        // Opacity crossfade — the inner scale keeps its own (slower) animation.
                        .animation(.easeInOut(duration: 1.1), value: step)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .clipped()
            // Per-step colour grade (web `.ob-art::after`), isolated so soft-light
            // can't bleed onto the form column.
            .overlay(
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0.3),
                        .init(color: grade, location: 1.0),
                    ],
                    startPoint: .top, endPoint: .bottom
                )
                .blendMode(.softLight)
                .animation(.easeInOut(duration: 0.8), value: step)
            )
            .compositingGroup()
        }
        .onAppear { startZoom() }
        .onChange(of: step) { _ in startZoom() }
    }

    /// Restart the 7s ease-out zoom for the newly active layer.
    private func startZoom() {
        guard !reduceMotion else { zoomedIn = true; return }
        zoomedIn = false
        withAnimation(.easeOut(duration: 7)) { zoomedIn = true }
    }
}

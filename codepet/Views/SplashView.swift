// codepet/Views/SplashView.swift
import SwiftUI

/// Brand splash — the first screen before sign-in. Faithful port of the web
/// `Splash` (dark cinematic: splash.jpg Ken Burns + scrim + pixel title +
/// purple pill). Click anywhere OR "Let's go" advances. English-only.
struct SplashView: View {
    var onContinue: (() -> Void)? = nil

    @State private var appear = false
    @State private var kenBurns = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            OnboardingContent.Palette.coldBg.ignoresSafeArea()

            // Slow Ken-Burns image layer.
            GeometryReader { geo in
                Image("splash")
                    .resizable()
                    .interpolation(.high)
                    .scaledToFill()
                    .frame(width: geo.size.width, height: geo.size.height)
                    .scaleEffect(kenBurns ? 1.08 : 1.0)
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
                Text("Codepet")
                    .font(CodepetTheme.pixel(80))
                    .tracking(2)
                    .foregroundColor(.white)
                    .shadow(color: Color(hex: "#a078ff").opacity(0.55), radius: 17)
                    .shadow(color: Color(hex: "#220e40").opacity(0.7), radius: 0, x: 0, y: 3)
                Text("Let's learn how to run your company with AI.")
                    .font(CodepetTheme.body(20))
                    .foregroundColor(.white)
                    .padding(.top, 20)
                    .shadow(color: Color(hex: "#0a041e").opacity(0.7), radius: 9)
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
                Spacer()
                Text("click anywhere to continue")
                    .font(CodepetTheme.body(11))
                    .foregroundColor(.white.opacity(0.6))
                    .padding(.bottom, 22)
            }
            .opacity(appear ? 1 : 0)
            .offset(y: appear ? 0 : 12)
        }
        .contentShape(Rectangle())
        .onTapGesture { onContinue?() }
        .onAppear {
            withAnimation(.easeOut(duration: 0.85)) { appear = true }
            if !reduceMotion {
                withAnimation(.easeInOut(duration: 30).repeatForever(autoreverses: true)) { kenBurns = true }
            }
        }
    }
}

#Preview {
    SplashView(onContinue: {})
}

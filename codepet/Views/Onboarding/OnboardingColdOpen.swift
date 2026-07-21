// codepet/Views/Onboarding/OnboardingColdOpen.swift
import SwiftUI

/// Step 0 — the cinematic cold-open (full-bleed hero), distinct from the question
/// screens. Faithful port of the web `.ob-cold` block. English-only.
struct OnboardingColdOpen: View {
    let onStart: () -> Void
    let onSkip: () -> Void
    @State private var kenBurns = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack(alignment: .topTrailing) {
            OnboardingContent.Palette.coldBg.ignoresSafeArea()
            GeometryReader { geo in
                Image("ob-team")
                    .resizable().interpolation(.high).scaledToFill()
                    .frame(width: geo.size.width, height: geo.size.height)
                    .scaleEffect(kenBurns ? 1.08 : 1.0)
                    .clipped()
            }
            .ignoresSafeArea()
            // left-weighted readability scrim
            LinearGradient(
                stops: [
                    .init(color: Color(hex: "#0d0522").opacity(0.96), location: 0.0),
                    .init(color: Color(hex: "#0d0522").opacity(0.9), location: 0.34),
                    .init(color: Color(hex: "#0d0522").opacity(0.62), location: 0.56),
                    .init(color: Color(hex: "#0d0522").opacity(0.12), location: 0.86),
                ],
                startPoint: .leading, endPoint: .trailing
            ).ignoresSafeArea()

            HStack {
                VStack(alignment: .leading, spacing: 0) {
                    Spacer()
                    (Text("Let's build your company — ")
                        .foregroundColor(.white)
                     + Text("not just your code.")
                        .foregroundColor(Color(hex: "#a78bfa")))
                        .font(.system(size: 46, weight: .bold))
                        .lineSpacing(3)
                        .shadow(color: Color(hex: "#0c0424").opacity(0.55), radius: 30)
                    Text("Codepet runs the whole company around your product, department by department — and does the work with you, so you always understand what's happening.")
                        .font(CodepetTheme.body(16))
                        .foregroundColor(Color(hex: "#f0eefc").opacity(0.95))
                        .lineSpacing(4)
                        .frame(maxWidth: 500, alignment: .leading)
                        .padding(.top, 20)

                    Text("CODEPET RUNS ALL \(OnboardingContent.departments.count) DEPARTMENTS")
                        .font(CodepetTheme.body(11)).fontWeight(.semibold)
                        .tracking(1.2)
                        .foregroundColor(.white.opacity(0.5))
                        .padding(.top, 26).padding(.bottom, 11)
                    deptChips.frame(maxWidth: 540, alignment: .leading)

                    Button(action: onStart) {
                        Text("Set up my company")
                            .font(CodepetTheme.body(14)).fontWeight(.semibold)
                            .foregroundColor(.white)
                            .padding(.horizontal, 30).padding(.vertical, 12)
                            .background(Capsule().fill(CodepetTheme.accentPurple))
                            .overlay(Capsule().stroke(Color.white.opacity(0.22), lineWidth: 1))
                            .shadow(color: OnboardingContent.Palette.accentDeep.opacity(0.5), radius: 13, y: 8)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 30)
                    Spacer()
                }
                .frame(maxWidth: 580, alignment: .leading)
                .padding(.leading, 90)
                .padding(.trailing, 40)
                Spacer()
            }

            Button(action: onSkip) {
                Text("Skip onboarding →")
                    .font(CodepetTheme.body(12))
                    .foregroundColor(.white)
                    .padding(.horizontal, 14).padding(.vertical, 7)
                    .background(Capsule().fill(Color.white.opacity(0.14)))
                    .overlay(Capsule().stroke(Color.white.opacity(0.28), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .padding(20)
        }
        .onAppear {
            if !reduceMotion {
                withAnimation(.easeInOut(duration: 32).repeatForever(autoreverses: true)) { kenBurns = true }
            }
        }
    }

    private var deptChips: some View {
        // simple wrapping flow via a fixed-column grid keeps it dependency-free
        FlowChips(items: OnboardingContent.departments.map { ($0.name, $0.dot) })
    }
}

/// Minimal wrapping chip row (no external deps) for the cold-open department chips.
private struct FlowChips: View {
    let items: [(String, Color)]
    var body: some View {
        // Fixed adaptive grid; chips wrap and left-align.
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 90, maximum: 200), spacing: 8, alignment: .leading)],
                  alignment: .leading, spacing: 8) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, it in
                HStack(spacing: 7) {
                    Circle().fill(it.1).frame(width: 7, height: 7)
                        .shadow(color: it.1, radius: 4)
                    Text(it.0).font(CodepetTheme.body(12)).foregroundColor(.white.opacity(0.86))
                }
                .padding(.leading, 10).padding(.trailing, 12).padding(.vertical, 6)
                .background(Capsule().fill(Color.white.opacity(0.07)))
                .overlay(Capsule().stroke(Color.white.opacity(0.12), lineWidth: 1))
            }
        }
    }
}

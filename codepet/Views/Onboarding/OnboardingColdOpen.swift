// codepet/Views/Onboarding/OnboardingColdOpen.swift
import SwiftUI

/// Step 0 — the cinematic cold-open (full-bleed hero), distinct from the question
/// screens. Faithful port of the web `.ob-cold` block. English-only.
struct OnboardingColdOpen: View {
    let onStart: () -> Void
    let onSkip: () -> Void
    @State private var kenBurns = false
    @State private var appeared = false
    @State private var px: CGFloat = 0   // pointer parallax, -1...1
    @State private var py: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { root in
        ZStack(alignment: .topTrailing) {
            OnboardingContent.Palette.coldBg.ignoresSafeArea()
            GeometryReader { geo in
                Image("ob-team")
                    .resizable().interpolation(.high).scaledToFill()
                    .frame(width: geo.size.width, height: geo.size.height)
                    .scaleEffect(kenBurns ? 1.08 : 1.0)
                    .offset(x: px * 6, y: py * 6)   // subtle depth parallax
                    .clipped()
            }
            .ignoresSafeArea()
            // left-weighted readability scrim (web `.ob-cold::before`, all three layers)
            ZStack {
                LinearGradient(
                    stops: [
                        .init(color: Color(hex: "#0d0522").opacity(0.96), location: 0.0),
                        .init(color: Color(hex: "#0d0522").opacity(0.9), location: 0.34),
                        .init(color: Color(hex: "#0d0522").opacity(0.62), location: 0.56),
                        .init(color: Color(hex: "#0d0522").opacity(0.12), location: 0.86),
                    ],
                    startPoint: .leading, endPoint: .trailing
                )
                // bottom-up settle so the copy never sits on a hot spot
                LinearGradient(
                    stops: [
                        .init(color: Color(hex: "#0d0522").opacity(0.7), location: 0.0),
                        .init(color: .clear, location: 0.42),
                    ],
                    startPoint: .bottom, endPoint: .top
                )
                // soft violet bloom behind the headline
                RadialGradient(
                    colors: [CodepetTheme.accentPurple.opacity(0.16), .clear],
                    center: UnitPoint(x: 0.18, y: 0.42),
                    startRadius: 0,
                    endRadius: max(root.size.width, root.size.height) * 0.72
                )
            }
            .ignoresSafeArea()

            // pointer-parallax glow (web `.ob-cold-glow`)
            RadialGradient(
                colors: [CodepetTheme.accentPurple.opacity(0.26), .clear],
                center: UnitPoint(x: 0.24, y: 0.46),
                startRadius: 0,
                endRadius: max(root.size.width, root.size.height) * 0.38
            )
            .offset(x: px * 9, y: py * 9)
            .allowsHitTesting(false)
            .ignoresSafeArea()

            Starfield()
                .offset(x: px * 14, y: py * 14)
                .ignoresSafeArea()

            HStack {
                VStack(alignment: .leading, spacing: 0) {
                    Spacer()
                    (Text("Let's build your company — ")
                        .foregroundColor(.white)
                     + Text("not just your code.")
                        // web `.ob-hl` — gradient on the punchline
                        .foregroundStyle(LinearGradient(
                            colors: [Color(hex: "#c9a6ff"), Color(hex: "#8b5cf6")],
                            startPoint: .leading, endPoint: .trailing)))
                        .font(CodepetTheme.body(headlineSize(root.size.width), weight: .bold))
                        .tracking(-0.5)
                        .lineSpacing(headlineSize(root.size.width) * 0.08)
                        .shadow(color: Color(hex: "#0c0424").opacity(0.55), radius: 30)
                        .riseIn(appeared, delay: 0.1)
                    Text("Codepet runs the whole company around your product, department by department — and does the work with you, so you always understand what's happening.")
                        .font(CodepetTheme.body(16.5))
                        .foregroundColor(Color(hex: "#f0eefc").opacity(0.95))
                        .lineSpacing(4)
                        .frame(maxWidth: 500, alignment: .leading)
                        .padding(.top, 20)
                        .riseIn(appeared, delay: 0.24)

                    Text("CODEPET RUNS ALL \(OnboardingContent.departments.count) DEPARTMENTS")
                        .font(CodepetTheme.body(11, weight: .semibold))
                        .tracking(1.2)
                        .foregroundColor(.white.opacity(0.5))
                        .padding(.top, 26).padding(.bottom, 11)
                        .riseIn(appeared, delay: 0.5)
                    deptChips.frame(maxWidth: 540, alignment: .leading)
                        .riseIn(appeared, delay: 0.5)

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
                    .riseIn(appeared, delay: 0.5)
                    Spacer()
                }
                .frame(maxWidth: 580, alignment: .leading)
                // web `margin-left: clamp(40px, 9vw, 150px)`
                .padding(.leading, min(150, max(40, root.size.width * 0.09)))
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
        .onContinuousHover { phase in
            guard !reduceMotion else { return }
            switch phase {
            case .active(let p):
                withAnimation(.easeOut(duration: 0.25)) {
                    px = clampNorm(p.x, 0, root.size.width)
                    py = clampNorm(p.y, 0, root.size.height)
                }
            case .ended:
                withAnimation(.easeOut(duration: 0.4)) { px = 0; py = 0 }
            }
        }
        }
        .onAppear {
            if reduceMotion {
                appeared = true
                return
            }
            withAnimation(.easeInOut(duration: 32).repeatForever(autoreverses: true)) { kenBurns = true }
            appeared = true
        }
    }

    /// web `font-size: clamp(34px, 4vw, 52px)` on the cold-open headline.
    private func headlineSize(_ width: CGFloat) -> CGFloat {
        min(52, max(34, width * 0.04))
    }

    private var deptChips: some View {
        // Flexbox-style wrap (chips size to content, whole-chip wrapping) — matches
        // the web's flex-wrap; no mid-word breaking.
        ChipFlowLayout(spacing: 8) {
            ForEach(Array(OnboardingContent.departments.enumerated()), id: \.offset) { _, d in
                HStack(spacing: 7) {
                    Circle().fill(d.dot).frame(width: 7, height: 7)
                        .shadow(color: d.dot, radius: 4)
                    Text(d.name).font(CodepetTheme.body(12.5, weight: .medium))
                        .foregroundColor(.white.opacity(0.86))
                        .fixedSize()
                }
                .padding(.leading, 10).padding(.trailing, 12).padding(.vertical, 6)
                .background(Capsule().fill(Color.white.opacity(0.07)))
                .overlay(Capsule().stroke(Color.white.opacity(0.12), lineWidth: 1))
            }
        }
    }
}

extension View {
    /// Web `riseIn` — fade + 14px lift, 0.85s ease-out, staggered by `delay`.
    func riseIn(_ appeared: Bool, delay: Double) -> some View {
        self
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 14)
            .animation(.timingCurve(0.2, 0.7, 0.2, 1, duration: 0.85).delay(delay), value: appeared)
    }
}

/// A flexbox-style wrapping layout: each subview keeps its natural size and wraps
/// as a whole unit onto the next row. Left-aligned. macOS 13+ Layout protocol.
struct ChipFlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxW = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0, widest: CGFloat = 0
        for s in subviews {
            let sz = s.sizeThatFits(.unspecified)
            if x + sz.width > maxW, x > 0 { x = 0; y += rowH + spacing; rowH = 0 }
            x += sz.width + spacing
            rowH = max(rowH, sz.height)
            widest = max(widest, x)
        }
        return CGSize(width: min(maxW, widest), height: y + rowH)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0
        for s in subviews {
            let sz = s.sizeThatFits(.unspecified)
            if x + sz.width > bounds.width, x > 0 { x = 0; y += rowH + spacing; rowH = 0 }
            s.place(at: CGPoint(x: bounds.minX + x, y: bounds.minY + y), proposal: ProposedViewSize(sz))
            x += sz.width + spacing
            rowH = max(rowH, sz.height)
        }
    }
}

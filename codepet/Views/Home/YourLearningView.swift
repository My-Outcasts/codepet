import SwiftUI

// MARK: - YourLearningView
//
// EXPERIMENTAL (debug/coach-redesign): a SwiftUI port of the 2026 "Your learning"
// bento Home from redesign/hybrid-mockup.html. Applies the modernized direction:
//   • one desaturated SAGE accent (the pet stays the most saturated thing)
//   • depth from hairline borders + warm tint — no hard 8-bit drop shadows
//   • pixel font used ONLY for accents (pet name, eyebrows, numerals)
//   • bento cards + inset wells + calm motion; no hearts / coins
//
// Uses demo data so it renders standalone. Wired to the .home tab in MainTabView.
struct YourLearningView: View {
    @State private var breathe = false

    private let petAsset = "char-byte"

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: YL.gap) {

                // Page header
                HStack(alignment: .firstTextBaseline) {
                    Text("Your learning")
                        .font(CodepetTheme.body(22, weight: .semibold))
                        .foregroundColor(CodepetTheme.primaryText)
                    Spacer()
                    Text("Monday, 22 June")
                        .font(CodepetTheme.body(13))
                        .foregroundColor(CodepetTheme.mutedText)
                }
                .padding(.bottom, 2)

                // Row 1 — hero + concepts numeral
                HStack(alignment: .top, spacing: YL.gap) {
                    heroCard
                    conceptsCard
                        .frame(width: 168)
                }

                // Row 2 — concept path
                conceptPathCard

                // Row 3 — dictionary + heatmap
                HStack(alignment: .top, spacing: YL.gap) {
                    dictionaryCard
                    heatmapCard
                        .frame(width: 264)
                }

                // Row 4 — coaching nudge
                coachingCard
            }
            .padding(22)
            .frame(maxWidth: 1080, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .background(CodepetTheme.pageBackground)
        .onAppear {
            withAnimation(.easeInOut(duration: 4.6).repeatForever(autoreverses: true)) {
                breathe = true
            }
        }
    }

    // MARK: Hero

    private var heroCard: some View {
        HStack(spacing: 18) {
            Image(petAsset)
                .interpolation(.none)
                .resizable()
                .scaledToFit()
                .frame(width: 92, height: 92)
                .offset(y: breathe ? -3 : 0)
                .scaleEffect(breathe ? 1.015 : 1.0)

            VStack(alignment: .leading, spacing: 6) {
                YL.eyebrow("Welcome back")
                Text("Nice — 3 days coding this week.")
                    .font(CodepetTheme.body(17, weight: .semibold))
                    .foregroundColor(CodepetTheme.primaryText)
                Text("While you were away I tidied up what we learned. You’re close to **owning** async, and today’s login work opened up two new ideas.")
                    .font(CodepetTheme.body(13.5))
                    .foregroundColor(CodepetTheme.bodyText)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 12) {
                    HStack(spacing: 7) {
                        Text("3").font(CodepetTheme.pixel(13)).foregroundColor(YL.gold)
                        Text("day streak · kept warm")
                            .font(CodepetTheme.body(12))
                            .foregroundColor(CodepetTheme.mutedText)
                    }
                    .padding(.horizontal, 11).padding(.vertical, 5)
                    .background(Capsule().fill(CodepetTheme.surface))
                    .overlay(Capsule().stroke(YL.hairline, lineWidth: 1))

                    YL.eyebrow("no penalty for days off", color: YL.sageDeep)
                }
                .padding(.top, 5)
            }
            Spacer(minLength: 0)
        }
        .ylCard()
    }

    private var conceptsCard: some View {
        VStack(spacing: 8) {
            Text("18")
                .font(CodepetTheme.pixel(40))
                .foregroundColor(YL.sageDeep)
            Text("concepts seen\n· 11 owned")
                .multilineTextAlignment(.center)
                .font(CodepetTheme.body(12))
                .foregroundColor(CodepetTheme.mutedText)
        }
        .frame(maxWidth: .infinity, minHeight: 120)
        .ylCard(tint: true)
    }

    // MARK: Concept path

    private var conceptPathCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            YL.eyebrow("Your concept path · next lights up")
            HStack(spacing: 0) {
                node("✓", "variables", .done)
                edge(true)
                node("✓", "async / await", .done)
                edge(true)
                node("✓", "env vars", .done)
                edge(false)
                node("●", "OAuth", .next)
                edge(false)
                node("○", "webhooks", .locked)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .ylCard()
    }

    private enum NodeState { case done, next, locked }

    private func node(_ glyph: String, _ caption: String, _ state: NodeState) -> some View {
        let bg: Color, border: Color, fg: Color
        switch state {
        case .done:   bg = YL.sageTint; border = YL.sageLine; fg = YL.sageDeep
        case .next:   bg = YL.sage;     border = YL.sage;     fg = .white
        case .locked: bg = Color(hex: "#F8F7F2"); border = YL.hairline; fg = CodepetTheme.mutedText
        }
        return VStack(spacing: 7) {
            Text(glyph)
                .font(CodepetTheme.body(13, weight: .semibold))
                .foregroundColor(fg)
                .frame(width: 34, height: 34)
                .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(bg))
                .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).stroke(border, lineWidth: 1))
                .shadow(color: state == .next ? YL.sage.opacity(0.25) : .clear, radius: 6)
                .opacity(state == .locked ? 0.5 : 1)
            Text(caption)
                .font(.system(size: 10.5, design: .monospaced))
                .foregroundColor(state == .next ? YL.sageDeep : CodepetTheme.mutedText)
                .fixedSize()
        }
        .frame(maxWidth: .infinity)
    }

    private func edge(_ done: Bool) -> some View {
        Rectangle()
            .fill(done ? YL.sageLine : YL.hairline)
            .frame(height: 2)
            .frame(maxWidth: .infinity)
            .offset(y: -11)
    }

    // MARK: Dictionary

    private var dictionaryCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            YL.eyebrow("Terms from your code this week")
                .padding(.bottom, 10)
            term("OAuth", "A way to let people log in with another account (like Google) without sharing a password.", "seen in LoginView.swift · today")
            divider
            term("environment var", "A secret value kept outside your code — like an API key — so it never ships in the app.", "seen in .env · today")
            divider
            term("async / await", "Lets your app wait for slow things (like a network call) without freezing.", "seen 2× · last in AuthManager.swift", last: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .ylCard()
    }

    private var divider: some View {
        Rectangle().fill(YL.hairline).frame(height: 1)
    }

    private func term(_ name: String, _ def: String, _ whereLine: String, last: Bool = false) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(name)
                .font(.system(size: 12.5, weight: .medium, design: .monospaced))
                .foregroundColor(YL.sageDeep)
                .frame(width: 124, alignment: .leading)
            VStack(alignment: .leading, spacing: 3) {
                Text(def)
                    .font(CodepetTheme.body(12.5))
                    .foregroundColor(CodepetTheme.bodyText)
                    .fixedSize(horizontal: false, vertical: true)
                Text(whereLine)
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundColor(Color(hex: "#A89F90"))
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 10)
    }

    // MARK: Heatmap (inset well)

    private var heatmapCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            YL.eyebrow("Your coding · 12 weeks")
            VStack(spacing: 10) {
                let cols = 12, rows = 7
                VStack(spacing: 4) {
                    ForEach(0..<rows, id: \.self) { r in
                        HStack(spacing: 4) {
                            ForEach(0..<cols, id: \.self) { c in
                                let i = r * cols + c
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(YL.heatColor(level: YL.heatLevel(i)))
                                    .aspectRatio(1, contentMode: .fit)
                            }
                        }
                    }
                }
                HStack(spacing: 5) {
                    Spacer()
                    Text("less").font(CodepetTheme.body(10)).foregroundColor(Color(hex: "#A89F90"))
                    ForEach(0..<5, id: \.self) { l in
                        RoundedRectangle(cornerRadius: 2).fill(YL.heatColor(level: l)).frame(width: 9, height: 9)
                    }
                    Text("more").font(CodepetTheme.body(10)).foregroundColor(Color(hex: "#A89F90"))
                }
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(YL.well))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(YL.hairline, lineWidth: 1))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .ylCard()
    }

    // MARK: Coaching nudge

    private var coachingCard: some View {
        HStack(spacing: 14) {
            Image(petAsset)
                .interpolation(.none).resizable().scaledToFit()
                .frame(width: 40, height: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text("Heads up — your context hit 80% twice today.")
                    .font(CodepetTheme.body(13.5, weight: .semibold))
                    .foregroundColor(CodepetTheme.primaryText)
                Text("That’s why Claude started forgetting earlier decisions. Want the 30-second version of when to /compact vs. start fresh?")
                    .font(CodepetTheme.body(13))
                    .foregroundColor(CodepetTheme.bodyText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Text("Show me")
                .font(CodepetTheme.body(12, weight: .semibold))
                .foregroundColor(YL.sageDeep)
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 9).stroke(YL.sageLine, lineWidth: 1))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .ylCard(tint: true)
    }
}

// MARK: - Tokens + helpers (file-local, prefixed to avoid collisions)

private enum YL {
    static let gap: CGFloat = 16

    static let sage      = Color(hex: "#6E8E68")
    static let sageDeep  = Color(hex: "#4F6B4A")
    static let sageTint  = Color(hex: "#E8EEE4")
    static let sageLine  = Color(hex: "#CBD8C4")
    static let hairline  = Color(hex: "#E5E1D8")
    static let well      = Color(hex: "#EFEDE6")
    static let gold      = Color(hex: "#C99A4E")

    static func eyebrow(_ text: String, color: Color = Color(hex: "#7A7264")) -> some View {
        Text(text.uppercased())
            .font(CodepetTheme.pixel(9))
            .tracking(0.5)
            .foregroundColor(color)
    }

    // deterministic, recent-weighted intensities (no randomness)
    static func heatLevel(_ i: Int) -> Int {
        let base = (i * 13 + 5) % 7          // 0..6
        var lvl = max(0, min(4, base - 1))   // bias toward lower
        if i > 70 { lvl = min(4, lvl + 2) }  // recent weeks warmer
        if (i * 7) % 9 == 0 { lvl = 0 }      // some rest days (shame-free)
        return lvl
    }

    static func heatColor(level: Int) -> Color {
        switch level {
        case 1: return Color(hex: "#D8E2D2")
        case 2: return Color(hex: "#B4C9AC")
        case 3: return Color(hex: "#8FB186")
        case 4: return sage
        default: return Color(hex: "#E5E1D8")
        }
    }
}

private extension View {
    /// Bento card: warm surface (or sage tint) + hairline border + faint soft lift.
    func ylCard(tint: Bool = false) -> some View {
        self
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(tint ? YL.sageTint : CodepetTheme.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(tint ? YL.sageLine : YL.hairline, lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.04), radius: 10, x: 0, y: 4)
    }
}

#if DEBUG
#Preview {
    YourLearningView().frame(width: 940, height: 720)
}
#endif

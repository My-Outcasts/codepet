import SwiftUI

/// Reusable animation modifiers and effects for CodePet.
/// Matches the web prototype's CSS keyframe animations and per-character play animations.

// MARK: - Per-Character Play Animations

/// Describes a character's unique play reaction: animation style, text, and particles
struct CharPlayAnimation {
    let animationType: PetAnimationType
    let text: String
    let particles: [(color: String, symbol: String)]
}

enum PetAnimationType {
    case glitch      // byte — rapid jitter/static
    case backflip    // nova — flip rotation
    case bigBounce   // crash — heavy bounce
    case dance       // luna — side-to-side sway
    case zenSpin     // sage — slow rotation
    case shrink      // glitch(char) — shrink/grow
    case float       // zero — gentle float
    case wiggle      // null — chaotic wiggle
}

/// All per-character play animations matching the web's PLAY_ANIMS
let charPlayAnimations: [String: CharPlayAnimation] = [
    "byte": CharPlayAnimation(
        animationType: .glitch,
        text: "G̸l̸i̸t̸c̸h̸!",
        particles: [("#8B7BE8","◆"),("#B8AFFF","◇"),("#6C5CE7","▪"),("#A29BFE","◆"),("#DDD6FE","✦")]
    ),
    "nova": CharPlayAnimation(
        animationType: .backflip,
        text: "Backflip!",
        particles: [("#FF8C00","🔥"),("#FFD700","✦"),("#FF6B00","✧"),("#FFA500","★"),("#FFEC80","✦")]
    ),
    "crash": CharPlayAnimation(
        animationType: .bigBounce,
        text: "SMASH!",
        particles: [("#E04040","💥"),("#FF6B6B","✦"),("#C02020","◆"),("#FF4444","★"),("#FFA0A0","✧")]
    ),
    "luna": CharPlayAnimation(
        animationType: .dance,
        text: "~Dance~",
        particles: [("#5B8DEF","✿"),("#8FB4F5","♪"),("#3A6FD0","✦"),("#B0CCFA","❀"),("#7AA8F2","♫")]
    ),
    "sage": CharPlayAnimation(
        animationType: .zenSpin,
        text: "Wisdom spin!",
        particles: [("#20B090","✦"),("#60D8B8","◈"),("#0A8868","✧"),("#A0F0D8","❖"),("#40C8A0","✦")]
    ),
    "glitch": CharPlayAnimation(
        animationType: .shrink,
        text: "Hack mode!",
        particles: [("#E0508C","<"),("#FF80B0","/>"),("#C03070","{"),("#FF60A0","}"),("#FFB0D0","✦")]
    ),
    "null": CharPlayAnimation(
        animationType: .wiggle,
        text: "¿¡Chaos!?",
        particles: [("#80C830","?"),("#A0E848","!"),("#60A018","¿"),("#C0F868","¡"),("#B8F050","✦")]
    ),
]

// MARK: - Pet Animation Modifier (Plays character-specific animation)

struct PetPlayAnimationModifier: ViewModifier {
    let animationType: PetAnimationType
    @Binding var isAnimating: Bool

    func body(content: Content) -> some View {
        content
            .modifier(AnimationEffect(type: animationType, active: isAnimating))
    }
}

private struct AnimationEffect: ViewModifier {
    let type: PetAnimationType
    let active: Bool

    func body(content: Content) -> some View {
        switch type {
        case .glitch:
            content
                .offset(x: active ? CGFloat.random(in: -4...4) : 0,
                        y: active ? CGFloat.random(in: -2...2) : 0)
                .scaleEffect(active ? CGFloat.random(in: 0.95...1.05) : 1.0)
                .animation(.easeInOut(duration: 0.05).repeatCount(active ? 16 : 0), value: active)

        case .backflip:
            content
                .rotation3DEffect(.degrees(active ? 360 : 0), axis: (x: 1, y: 0, z: 0))
                .animation(.spring(response: 0.8, dampingFraction: 0.6), value: active)

        case .bigBounce:
            content
                .offset(y: active ? -20 : 0)
                .scaleEffect(x: active ? 0.9 : 1.0, y: active ? 1.15 : 1.0)
                .animation(.spring(response: 0.7, dampingFraction: 0.4), value: active)

        case .dance:
            content
                .offset(x: active ? 8 : 0)
                .rotationEffect(.degrees(active ? 5 : 0))
                .animation(.easeInOut(duration: 0.22).repeatCount(active ? 8 : 0, autoreverses: true), value: active)

        case .zenSpin:
            content
                .rotationEffect(.degrees(active ? 360 : 0))
                .animation(.easeInOut(duration: 1.0), value: active)

        case .shrink:
            content
                .scaleEffect(active ? 0.6 : 1.0)
                .opacity(active ? 0.7 : 1.0)
                .animation(.spring(response: 0.45, dampingFraction: 0.5).repeatCount(active ? 2 : 0, autoreverses: true), value: active)

        case .float:
            content
                .offset(y: active ? -15 : 0)
                .animation(.easeInOut(duration: 1.0), value: active)

        case .wiggle:
            content
                .rotationEffect(.degrees(active ? 12 : 0))
                .offset(x: active ? 6 : 0)
                .animation(.easeInOut(duration: 0.15).repeatCount(active ? 10 : 0, autoreverses: true), value: active)
        }
    }
}

// MARK: - Particle Burst for Play Action

struct PlayParticleBurstView: View {
    let particles: [(color: String, symbol: String)]
    @State private var animating = false

    var body: some View {
        ZStack {
            ForEach(0..<particles.count, id: \.self) { i in
                let angle = Double(i) * (.pi * 2 / Double(particles.count))
                let dist: CGFloat = CGFloat.random(in: 25...55)
                Text(particles[i].symbol)
                    .font(.pixelSystem(size: 14, weight: .bold))
                    .foregroundColor(Color(hex: particles[i].color))
                    .opacity(animating ? 0 : 1)
                    .offset(
                        x: animating ? cos(angle) * dist : 0,
                        y: animating ? sin(angle) * dist : 0
                    )
                    .scaleEffect(animating ? 1.5 : 0.3)
            }
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.8)) {
                animating = true
            }
        }
    }
}

// MARK: - Pet Reaction Overlay (text bubble + particles)

struct PetReactionView: View {
    let characterId: String
    let reactionType: String  // "heart", "feed", "play"
    let text: String
    @State private var visible = true
    @State private var offset: CGFloat = 0

    private var playAnim: CharPlayAnimation? {
        charPlayAnimations[characterId]
    }

    var body: some View {
        if visible {
            VStack(spacing: 8) {
                // Floating text bubble
                Text(text)
                    .font(.pixelSystem(size: 12, weight: .bold, design: .monospaced))
                    .foregroundColor(Color(hex: PetCharacter.all[characterId]?.hexColor ?? "#666"))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.white)
                            .shadow(color: .black.opacity(0.1), radius: 6, y: 2)
                    )
                    .offset(y: offset)

                // Particles for play action
                if reactionType == "play", let anim = playAnim {
                    PlayParticleBurstView(particles: anim.particles)
                }
            }
            .transition(.opacity.combined(with: .move(edge: .bottom)))
            .onAppear {
                withAnimation(.easeOut(duration: 0.5)) {
                    offset = -20
                }
                // Auto-dismiss after 2.5s
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                    withAnimation(.easeOut(duration: 0.3)) {
                        visible = false
                    }
                }
            }
        }
    }
}

// MARK: - Pet Idle Breathing Animation

struct PetBreathingModifier: ViewModifier {
    @State private var scale: CGFloat = 1.0

    func body(content: Content) -> some View {
        content
            .scaleEffect(scale)
            .onAppear {
                withAnimation(
                    Animation.easeInOut(duration: 2.0)
                        .repeatForever(autoreverses: true)
                ) {
                    scale = 1.04
                }
            }
    }
}

// MARK: - Character-Specific Idle Animations

struct CharIdleModifier: ViewModifier {
    let characterId: String
    @State private var phase: Bool = false

    func body(content: Content) -> some View {
        content
            .modifier(IdleEffect(characterId: characterId, phase: phase))
            .onAppear {
                withAnimation(
                    Animation.easeInOut(duration: idleDuration)
                        .repeatForever(autoreverses: true)
                ) {
                    phase = true
                }
            }
    }

    private var idleDuration: Double {
        switch characterId {
        case "byte": return 1.5    // slow glitch cycle
        case "nova": return 1.8    // float + tail wag
        case "crash": return 1.2   // bounce squish
        case "luna": return 2.0    // gentle bop
        case "sage": return 3.0    // slow head scan
        case "null": return 1.6    // jittery idle
        case "glitch": return 1.4  // punk twitch
        default: return 2.0
        }
    }
}

private struct IdleEffect: ViewModifier {
    let characterId: String
    let phase: Bool

    func body(content: Content) -> some View {
        switch characterId {
        case "byte":
            // Glitch twitch — occasional jitter
            content
                .offset(x: phase ? CGFloat.random(in: -2...2) : 0)
                .scaleEffect(phase ? 1.02 : 0.98)

        case "nova":
            // Float with gentle bob
            content
                .offset(y: phase ? -6 : 0)
                .rotationEffect(.degrees(phase ? 2 : -1))

        case "crash":
            // Bounce squish
            content
                .offset(y: phase ? -5 : 0)
                .scaleEffect(x: phase ? 0.96 : 1.02, y: phase ? 1.06 : 0.98)

        case "luna":
            // Gentle side bop
            content
                .offset(y: phase ? -4 : 0)
                .rotationEffect(.degrees(phase ? -2 : 1.5))

        case "sage":
            // Slow head scan (look left/right)
            content
                .offset(x: phase ? -3 : 3)
                .rotationEffect(.degrees(phase ? -1 : 1))

        case "glitch":
            // Punk twitch
            content
                .offset(x: phase ? 3 : -2, y: phase ? -2 : 1)
                .rotationEffect(.degrees(phase ? 3 : -2))

        case "null":
            // Chaotic idle bounce
            content
                .offset(y: phase ? -7 : 0)
                .rotationEffect(.degrees(phase ? 4 : -3))

        default:
            content
                .offset(y: phase ? -3 : 0)
        }
    }
}

// MARK: - Pulse Glow (for level-up, XP gain)

struct PulseGlowModifier: ViewModifier {
    let color: Color
    @State private var glowRadius: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .shadow(color: color.opacity(0.5), radius: glowRadius)
            .onAppear {
                withAnimation(
                    Animation.easeInOut(duration: 1.5)
                        .repeatForever(autoreverses: true)
                ) {
                    glowRadius = 12
                }
            }
    }
}

// MARK: - XP Particle Burst

struct XPParticle: Identifiable {
    let id = UUID()
    var x: CGFloat
    var y: CGFloat
    var opacity: Double
    var text: String
}

struct XPBurstView: View {
    let xpAmount: Int
    let color: Color
    @State private var particles: [XPParticle] = []
    @State private var animating = false

    var body: some View {
        ZStack {
            ForEach(particles) { particle in
                Text(particle.text)
                    .font(.pixelSystem(size: 12, weight: .bold, design: .monospaced))
                    .foregroundColor(color)
                    .opacity(animating ? 0 : particle.opacity)
                    .offset(
                        x: animating ? particle.x * 2.5 : 0,
                        y: animating ? particle.y * 2.5 : 0
                    )
            }
        }
        .onAppear {
            generateParticles()
            withAnimation(.easeOut(duration: 1.2)) {
                animating = true
            }
        }
    }

    private func generateParticles() {
        let texts = ["+\(xpAmount)", "XP", "★", "✦", "⚡"]
        particles = (0..<8).map { i in
            let angle = Double(i) * (.pi * 2 / 8)
            return XPParticle(
                x: CGFloat(cos(angle)) * CGFloat.random(in: 20...50),
                y: CGFloat(sin(angle)) * CGFloat.random(in: 20...50),
                opacity: Double.random(in: 0.6...1.0),
                text: texts[i % texts.count]
            )
        }
    }
}

// MARK: - Streak Fire Animation

struct StreakFireView: View {
    let streak: Int
    @State private var flicker = false

    var body: some View {
        HStack(spacing: 2) {
            Image(systemName: "flame.fill")
                .font(.pixelSystem(size: 16))
                .foregroundColor(fireColor)
                .scaleEffect(flicker ? 1.15 : 0.95)
                .animation(
                    Animation.easeInOut(duration: 0.6)
                        .repeatForever(autoreverses: true),
                    value: flicker
                )

            Text("\(streak)")
                .font(.pixelSystem(size: 14, weight: .heavy, design: .monospaced))
                .foregroundColor(fireColor)
        }
        .onAppear { flicker = true }
    }

    private var fireColor: Color {
        if streak >= 30 { return Color(hex: "#FF4500") }  // Legendary
        if streak >= 14 { return Color(hex: "#FF6B00") }  // Epic
        if streak >= 7  { return Color(hex: "#FF8C00") }  // Hot
        return Color(hex: "#D4960A")                       // Warm
    }
}

// MARK: - UI Transition Animations (matching web CSS keyframes)

/// fadeUp: content fades in while sliding up from 10px below
struct FadeUpModifier: ViewModifier {
    @State private var appeared = false

    func body(content: Content) -> some View {
        content
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 10)
            .onAppear {
                withAnimation(.easeOut(duration: 0.4)) {
                    appeared = true
                }
            }
    }
}

/// slideIn: content slides in from the right
struct SlideInModifier: ViewModifier {
    @State private var appeared = false

    func body(content: Content) -> some View {
        content
            .opacity(appeared ? 1 : 0)
            .offset(x: appeared ? 0 : 16)
            .onAppear {
                withAnimation(.easeOut(duration: 0.35)) {
                    appeared = true
                }
            }
    }
}

/// popIn: scale + fade entrance for modals/overlays
struct PopInModifier: ViewModifier {
    @State private var appeared = false

    func body(content: Content) -> some View {
        content
            .opacity(appeared ? 1 : 0)
            .scaleEffect(appeared ? 1 : 0.9)
            .onAppear {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                    appeared = true
                }
            }
    }
}

/// shimmer: animated gradient shine effect
struct ShimmerModifier: ViewModifier {
    @State private var phase: CGFloat = -1

    func body(content: Content) -> some View {
        content
            .overlay(
                LinearGradient(
                    colors: [.clear, .white.opacity(0.15), .clear],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .offset(x: phase * 200)
                .mask(content)
            )
            .onAppear {
                withAnimation(.linear(duration: 3).repeatForever(autoreverses: false)) {
                    phase = 1
                }
            }
    }
}

/// livePulse: subtle box-shadow pulse for active indicators
struct LivePulseModifier: ViewModifier {
    let color: Color
    @State private var pulsing = false

    func body(content: Content) -> some View {
        content
            .shadow(color: color.opacity(pulsing ? 0.25 : 0), radius: pulsing ? 10 : 0)
            .onAppear {
                withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                    pulsing = true
                }
            }
    }
}

/// catFloat: gentle floating idle for pet display
struct CatFloatModifier: ViewModifier {
    @State private var floating = false

    func body(content: Content) -> some View {
        content
            .offset(y: floating ? -3 : 0)
            .onAppear {
                withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true)) {
                    floating = true
                }
            }
    }
}

/// Confetti burst for celebrations
struct ConfettiBurstView: View {
    let count: Int
    let colors: [Color]
    @State private var particles: [(x: CGFloat, y: CGFloat, rotation: Double, color: Color, symbol: String)] = []
    @State private var animating = false

    init(count: Int = 30, colors: [Color] = [.red, .orange, .yellow, .green, .blue, .purple, .pink]) {
        self.count = count
        self.colors = colors
    }

    var body: some View {
        ZStack {
            ForEach(0..<particles.count, id: \.self) { i in
                Text(particles[i].symbol)
                    .font(.pixelSystem(size: CGFloat.random(in: 8...16)))
                    .foregroundColor(particles[i].color)
                    .rotationEffect(.degrees(animating ? particles[i].rotation * 3 : 0))
                    .offset(
                        x: animating ? particles[i].x : 0,
                        y: animating ? particles[i].y : -20
                    )
                    .opacity(animating ? 0 : 1)
            }
        }
        .onAppear {
            generateParticles()
            withAnimation(.easeOut(duration: 1.5)) {
                animating = true
            }
        }
    }

    private func generateParticles() {
        let symbols = ["✦", "★", "◆", "✧", "❖", "♦", "●", "▪", "✿", "♪"]
        particles = (0..<count).map { _ in
            (
                x: CGFloat.random(in: -120...120),
                y: CGFloat.random(in: 60...200),
                rotation: Double.random(in: -180...180),
                color: colors.randomElement() ?? .white,
                symbol: symbols.randomElement() ?? "✦"
            )
        }
    }
}

// MARK: - Level Up Celebration Overlay

struct LevelUpOverlay: View {
    let level: Int
    let characterColor: Color
    @State private var showBanner = false
    @State private var showStars = false
    var onDismiss: () -> Void = {}

    var body: some View {
        ZStack {
            // Dim background
            Color.black.opacity(showBanner ? 0.5 : 0)
                .ignoresSafeArea()
                .onTapGesture { dismiss() }

            // Confetti burst
            if showStars {
                ConfettiBurstView(count: 40, colors: [characterColor, .yellow, .orange, .green, .purple])
            }

            VStack(spacing: 16) {
                // Stars
                if showStars {
                    HStack(spacing: 8) {
                        ForEach(0..<5, id: \.self) { i in
                            Text("⭐")
                                .font(.pixelSystem(size: 20))
                                .rotationEffect(.degrees(Double.random(in: -15...15)))
                                .transition(.scale.combined(with: .opacity))
                        }
                    }
                    .transition(.scale)
                }

                // Badge
                Circle()
                    .fill(characterColor)
                    .frame(width: 80, height: 80)
                    .overlay(
                        Text("\(level)")
                            .font(.pixelSystem(size: 32, weight: .black, design: .monospaced))
                            .foregroundColor(.white)
                    )
                    .shadow(color: characterColor.opacity(0.5), radius: 20)
                    .modifier(PulseGlowModifier(color: characterColor))

                Text("LEVEL UP!")
                    .font(.pixelSystem(size: 24, weight: .black, design: .monospaced))
                    .foregroundColor(.white)

                Text("You've reached Level \(level)")
                    .font(.pixelSystem(size: 14))
                    .foregroundColor(.white.opacity(0.8))

                Button("Continue") { dismiss() }
                    .font(.pixelSystem(size: 14, weight: .bold))
                    .foregroundColor(characterColor)
                    .padding(.horizontal, 28)
                    .padding(.vertical, 10)
                    .background(Color.white)
                    .cornerRadius(12)
                    .buttonStyle(.plain)
            }
            .scaleEffect(showBanner ? 1 : 0.5)
            .opacity(showBanner ? 1 : 0)
        }
        .onAppear {
            SoundManager.shared.playLevelUp()
            withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                showBanner = true
            }
            withAnimation(.spring(response: 0.6).delay(0.3)) {
                showStars = true
            }
        }
    }

    private func dismiss() {
        withAnimation(.easeOut(duration: 0.25)) {
            showBanner = false
            showStars = false
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            onDismiss()
        }
    }
}

// MARK: - Skill "Leveled Up" Celebration (Duolingo-style)

/// Payload describing which skill just reached 100% completion.
struct SkillCelebration: Identifiable, Equatable {
    let id = UUID()
    let skillTitle: String
    let colorHex: String
    let exerciseCount: Int
}

/// Full-screen celebration shown when every exercise in a skill is complete.
/// Mirrors Duolingo's "Perfect lesson!" screen: character + confetti, a bold
/// headline, stat cards that pop in one-by-one, then a claim button.
struct SkillLeveledUpOverlay: View {
    let celebration: SkillCelebration
    let characterId: String
    var onDismiss: () -> Void = {}

    @Environment(\.uiLanguage) private var uiLanguage

    @State private var appeared = false
    @State private var showHeadline = false
    @State private var visibleCards = 0
    @State private var showButton = false
    @State private var bounce = false

    private let ink = Color(hex: "#2D2B26")
    private var color: Color { Color(hex: celebration.colorHex) }

    private struct Stat { let icon: String; let value: String; let label: String; let tint: Color }

    private var stats: [Stat] {
        [
            Stat(icon: "checkmark.seal.fill",
                 value: "\(celebration.exerciseCount)",
                 label: uiLanguage == .vi ? "BÀI TẬP" : "EXERCISES",
                 tint: color),
            Stat(icon: "target",
                 value: "100%",
                 label: uiLanguage == .vi ? "HOÀN TẤT" : "COMPLETE",
                 tint: Color(hex: "#029902")),
            Stat(icon: "trophy.fill",
                 value: "+1",
                 label: uiLanguage == .vi ? "CẤP" : "LEVEL",
                 tint: Color(hex: "#D49700")),
        ]
    }

    var body: some View {
        ZStack {
            Color.black.opacity(appeared ? 0.45 : 0)
                .ignoresSafeArea()
                .onTapGesture { dismiss() }

            VStack(spacing: 18) {
                // Character + confetti burst
                ZStack {
                    if showHeadline {
                        ConfettiBurstView(count: 38,
                                          colors: [color, .yellow, .orange,
                                                   Color(hex: "#7CE0A3"), .pink])
                    }
                    CharacterImage(characterId, size: 116)
                        .scaleEffect(bounce ? 1.04 : 1.0)
                }
                .frame(height: 124)

                // Headline + subtitle
                VStack(spacing: 6) {
                    Text(uiLanguage == .vi ? "Lên cấp!" : "Leveled Up!")
                        .font(CodepetTheme.pixel(30))
                        .foregroundColor(Color(hex: "#FFCC33"))
                    Text(uiLanguage == .vi
                         ? "Hoàn thành \(celebration.skillTitle)!"
                         : "\(celebration.skillTitle) complete!")
                        .font(.pixelSystem(size: 13))
                        .foregroundColor(ink.opacity(0.55))
                        .multilineTextAlignment(.center)
                }
                .opacity(showHeadline ? 1 : 0)
                .offset(y: showHeadline ? 0 : 8)

                // Stat cards (pop in one-by-one)
                HStack(spacing: 10) {
                    ForEach(Array(stats.enumerated()), id: \.offset) { idx, stat in
                        statCard(stat)
                            .scaleEffect(idx < visibleCards ? 1 : 0.6)
                            .opacity(idx < visibleCards ? 1 : 0)
                    }
                }

                // Claim button
                Button(action: { dismiss() }) {
                    Text(uiLanguage == .vi ? "Tuyệt vời!" : "Awesome!")
                }
                .buttonStyle(PixelButtonStyle(
                    fill: color, foreground: .white,
                    paddingH: 28, paddingV: 12,
                    font: .pixelSystem(size: 15, weight: .bold)))
                .opacity(showButton ? 1 : 0)
                .padding(.top, 2)
            }
            .padding(28)
            .frame(width: 380)
            // App-standard pixel box (thin accent staircase) instead of the chunky
            // black border, matching the rest of the app's cards.
            .pixelBox(fill: Color(hex: "#FDFCFF"), borderColor: color,
                      shadowOffset: 2, blockSize: 2, steps: 2, borderWidth: 2)
            .scaleEffect(appeared ? 1 : 0.8)
            .opacity(appeared ? 1 : 0)
        }
        .onAppear(perform: runSequence)
    }

    private func statCard(_ stat: Stat) -> some View {
        VStack(spacing: 4) {
            Image(systemName: stat.icon)
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(stat.tint)
            Text(stat.value)
                .font(.pixelSystem(size: 16, weight: .bold))
                .foregroundColor(ink)
            Text(stat.label)
                .font(.pixelSystem(size: 8, weight: .bold))
                .tracking(0.5)
                .foregroundColor(ink.opacity(0.4))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(PixelStaircaseRectangle(blockSize: 2, steps: 2).fill(stat.tint.opacity(0.10)))
        .overlay(PixelStaircaseRectangle(blockSize: 2, steps: 2).stroke(stat.tint.opacity(0.35), lineWidth: 1.5))
    }

    private func runSequence() {
        SoundManager.shared.playLevelUp()
        withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) { appeared = true }
        withAnimation(.spring(response: 0.6).delay(0.25)) { showHeadline = true }
        // Pop the stat cards in one-by-one.
        for i in 1...stats.count {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.6)
                .delay(0.35 + Double(i) * 0.12)) {
                visibleCards = i
            }
        }
        withAnimation(.easeOut(duration: 0.3)
            .delay(0.35 + Double(stats.count) * 0.12 + 0.1)) {
            showButton = true
        }
        // Gentle idle bounce on the character.
        withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true).delay(0.5)) {
            bounce = true
        }
    }

    private func dismiss() {
        withAnimation(.easeOut(duration: 0.25)) { appeared = false }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.28) { onDismiss() }
    }
}

// MARK: - Per-Exercise "Exercise complete!" Celebration

/// Payload for the full-screen reward shown after completing one exercise.
struct ExerciseCelebration: Identifiable, Equatable {
    let id = UUID()
    let earnedXP: Int
    let nextChallengeId: String?   // nil = this was the last exercise
}

/// Full-screen reward shown after each exercise: dimmed backdrop + a centered
/// pixel card (pet + confetti + "Exercise complete!" + XP), with the Next /
/// Finish button fading in a beat later. `onAdvance` moves to the next exercise
/// (or finishes the skill).
struct ExerciseCompleteOverlay: View {
    let characterId: String
    let earnedXP: Int
    let isLast: Bool
    var onAdvance: () -> Void = {}

    @State private var appeared = false
    @State private var showNext = false
    @State private var bounce = false

    private let ink = Color(hex: "#2D2B26")

    var body: some View {
        ZStack {
            Color.black.opacity(appeared ? 0.5 : 0)
                .ignoresSafeArea()

            ZStack {
                if appeared {
                    ConfettiBurstView(count: 28, colors: [
                        Color(hex: "#3FA66A"), Color(hex: "#FFCC33"),
                        Color(hex: "#7C3AED"), Color(hex: "#E0508C")
                    ])
                }

                VStack(spacing: 14) {
                    CharacterImage(characterId, size: 96)
                        .scaleEffect(bounce ? 1.05 : 1.0)

                    Text("Exercise complete!")
                        .font(CodepetTheme.pixel(24))
                        .foregroundColor(ink)

                    HStack(spacing: 6) {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(Color(hex: "#E0A800"))
                        Text("+\(earnedXP) XP")
                            .font(.pixelSystem(size: 15, weight: .bold))
                            .foregroundColor(ink)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(PixelStaircaseRectangle(blockSize: 2, steps: 1).fill(Color(hex: "#FFF6D9")))
                    .overlay(PixelStaircaseRectangle(blockSize: 2, steps: 1).stroke(Color(hex: "#E0A800"), lineWidth: 1.5))

                    if showNext {
                        Button(isLast ? "Finish" : "Next") { onAdvance() }
                            .buttonStyle(PixelButtonStyle(
                                fill: Color(hex: "#3FA66A"), foreground: .white,
                                paddingH: 26, paddingV: 12,
                                font: .pixelSystem(size: 16, weight: .bold)))
                            .transition(.opacity.combined(with: .scale(scale: 0.9)))
                    }
                }
                .padding(32)
            }
            .frame(width: 360)
            // App-standard pixel box (thin accent staircase) instead of the chunky
            // black border, matching the rest of the app's cards.
            .pixelBox(fill: Color(hex: "#FDFCFF"), borderColor: Color(hex: "#3FA66A"),
                      shadowOffset: 2, blockSize: 2, steps: 2, borderWidth: 2)
            .scaleEffect(appeared ? 1 : 0.85)
            .opacity(appeared ? 1 : 0)
        }
        .onAppear {
            SoundManager.shared.playTap()
            withAnimation(.spring(response: 0.45, dampingFraction: 0.7)) { appeared = true }
            withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true).delay(0.3)) { bounce = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                withAnimation(.spring(response: 0.45, dampingFraction: 0.7)) { showNext = true }
            }
        }
    }
}

// MARK: - Streak Milestone Overlay

/// Full-screen recognition when the user reaches a streak milestone (3/7/14/…).
/// Shows the day count, the pet, and the rewards earned (coins, freezes, an
/// unlocked cosmetic).
struct StreakMilestoneOverlay: View {
    let characterId: String
    let milestone: StreakMilestoneCelebration
    var onDismiss: () -> Void = {}

    @State private var appeared = false
    @State private var showButton = false
    @State private var bounce = false

    private let ink = Color(hex: "#2D2B26")
    private let accent = CodepetTheme.accentOrange

    var body: some View {
        ZStack {
            Color.black.opacity(appeared ? 0.5 : 0)
                .ignoresSafeArea()

            ZStack {
                if appeared {
                    ConfettiBurstView(count: 30, colors: [
                        Color(hex: "#F0883E"), Color(hex: "#FFCC33"),
                        Color(hex: "#E0508C"), Color(hex: "#7C3AED")
                    ])
                }

                VStack(spacing: 14) {
                    Image(systemName: "flame.fill")
                        .font(.system(size: 64))
                        .foregroundColor(accent)
                        .scaleEffect(bounce ? 1.08 : 1.0)
                        .shadow(color: accent.opacity(0.35), radius: 10, y: 4)

                    Text("\(milestone.day)-day streak!")
                        .font(CodepetTheme.pixel(24))
                        .foregroundColor(ink)

                    Text("\(milestone.day) days of showing up to build. 🔥")
                        .font(.pixelSystem(size: 13))
                        .foregroundColor(ink.opacity(0.6))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)

                    // Reward chips
                    HStack(spacing: 8) {
                        rewardChip(icon: "bitcoinsign.circle.fill", tint: Color(hex: "#E0A800"),
                                   text: "+\(milestone.bonusCoins)")
                        if milestone.freezeReward > 0 {
                            rewardChip(icon: "snowflake", tint: Color(hex: "#4FB0E5"),
                                       text: "+\(milestone.freezeReward) freeze\(milestone.freezeReward == 1 ? "" : "s")")
                        }
                    }
                    if let cosmetic = milestone.unlockedCosmetic {
                        rewardChip(icon: "sparkles", tint: accent, text: "Unlocked: \(cosmetic)")
                    }

                    if showButton {
                        Button("Keep it going") { onDismiss() }
                            .buttonStyle(PixelButtonStyle(
                                fill: accent, foreground: .white,
                                paddingH: 26, paddingV: 12,
                                font: .pixelSystem(size: 16, weight: .bold)))
                            .transition(.opacity.combined(with: .scale(scale: 0.9)))
                    }
                }
                .padding(32)
            }
            .frame(width: 380)
            // App-standard pixel box (thin accent staircase) instead of the chunky
            // black border, matching the rest of the app's cards.
            .pixelBox(fill: Color(hex: "#FDFCFF"), borderColor: accent,
                      shadowOffset: 2, blockSize: 2, steps: 2, borderWidth: 2)
            .scaleEffect(appeared ? 1 : 0.85)
            .opacity(appeared ? 1 : 0)
        }
        .onAppear {
            SoundManager.shared.playTap()
            withAnimation(.spring(response: 0.45, dampingFraction: 0.7)) { appeared = true }
            withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true).delay(0.3)) { bounce = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                withAnimation(.spring(response: 0.45, dampingFraction: 0.7)) { showButton = true }
            }
        }
    }

    private func rewardChip(icon: String, tint: Color, text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon).font(.system(size: 13, weight: .bold)).foregroundColor(tint)
            Text(text).font(.pixelSystem(size: 13, weight: .bold)).foregroundColor(ink)
        }
        .padding(.horizontal, 12).padding(.vertical, 7)
        .background(PixelStaircaseRectangle(blockSize: 2, steps: 1).fill(tint.opacity(0.14)))
        .overlay(PixelStaircaseRectangle(blockSize: 2, steps: 1).stroke(tint.opacity(0.6), lineWidth: 1.5))
    }
}

// MARK: - Tier Unlock Overlay

struct TierUnlockOverlay: View {
    let tierNumber: Int
    let characterId: String
    var onDismiss: () -> Void = {}

    @State private var showContent = false
    @State private var showEvo = false

    private var tierName: String {
        switch tierNumber {
        case 2: return "The Frozen Spire"
        case 3: return "The Eternal Garden"
        case 4: return "The Mystic Grove"
        default: return "New Tier"
        }
    }

    private var charData: PetCharacter? {
        PetCharacter.all[characterId]
    }

    private var outfit: CharOutfit? {
        characterOutfits[tierNumber]
    }

    var body: some View {
        ZStack {
            Color.black.opacity(showContent ? 0.6 : 0)
                .ignoresSafeArea()
                .onTapGesture { dismiss() }

            // Confetti burst
            if showEvo {
                ConfettiBurstView(count: 50, colors: [
                    charData?.color ?? .blue, .yellow, .orange, .green, .purple, .pink
                ])
            }

            VStack(spacing: 20) {
                Text("🎊")
                    .font(.pixelSystem(size: 28))

                Text("Tier \(tierNumber) Unlocked!")
                    .font(.pixelSystem(size: 22, weight: .bold))

                Text("You completed all Tier \(tierNumber - 1) skills!")
                    .font(.pixelSystem(size: 12))
                    .foregroundColor(Color(hex: "#888888"))

                // Character evolution
                if showEvo, let char = charData, let _ = outfit {
                    VStack(spacing: 12) {
                        Text("\(char.name) EVOLVED!")
                            .font(.pixelSystem(size: 9, weight: .bold, design: .monospaced))
                            .foregroundColor(char.color)
                            .tracking(1)

                        // Evolution stages
                        HStack(spacing: 12) {
                            ForEach(1...4, id: \.self) { tier in
                                let unlocked = tier <= tierNumber
                                VStack(spacing: 4) {
                                    ZStack {
                                        RoundedRectangle(cornerRadius: 10)
                                            .fill(unlocked ? char.color.opacity(0.1) : Color(hex: "#F5F4F0"))
                                            .frame(width: 44, height: 44)
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 10)
                                                    .stroke(tier == tierNumber ? char.color : Color(hex: "#E0DDD6"), lineWidth: tier == tierNumber ? 2 : 1)
                                            )
                                        Text(characterOutfits[tier]?.badge ?? "?")
                                            .font(.pixelSystem(size: 18))
                                    }
                                    Text(characterOutfits[tier]?.name ?? "")
                                        .font(.pixelSystem(size: 9, weight: .semibold))
                                        .foregroundColor(unlocked ? Color(hex: "#2D2B26") : Color(hex: "#C8C0B4"))
                                }
                                .opacity(unlocked ? 1 : 0.3)
                            }
                        }
                    }
                    .padding(20)
                    .background(
                        RoundedRectangle(cornerRadius: 20)
                            .fill((charData?.color ?? .gray).opacity(0.05))
                            .overlay(
                                RoundedRectangle(cornerRadius: 20)
                                    .stroke((charData?.color ?? .gray).opacity(0.2), lineWidth: 1.5)
                            )
                    )
                    .transition(.scale.combined(with: .opacity))
                }

                Button("Continue") { dismiss() }
                    .font(.pixelSystem(size: 14, weight: .bold))
                    .foregroundColor(charData?.color ?? .blue)
                    .padding(.horizontal, 28)
                    .padding(.vertical, 10)
                    .background(Color.white)
                    .cornerRadius(12)
                    .buttonStyle(.plain)
            }
            .padding(36)
            .background(
                RoundedRectangle(cornerRadius: 24)
                    .fill(Color(hex: "#FBF9F1"))
                    .shadow(color: .black.opacity(0.3), radius: 30, y: 10)
            )
            .scaleEffect(showContent ? 1 : 0.5)
            .opacity(showContent ? 1 : 0)
        }
        .onAppear {
            SoundManager.shared.playLevelUp()
            withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                showContent = true
            }
            withAnimation(.spring(response: 0.6).delay(0.4)) {
                showEvo = true
            }
        }
    }

    private func dismiss() {
        withAnimation(.easeOut(duration: 0.25)) {
            showContent = false
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            onDismiss()
        }
    }
}

// MARK: - Card Hover Effect (macOS)

struct CardHoverModifier: ViewModifier {
    @State private var isHovered = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(isHovered ? 1.015 : 1.0)
            .shadow(
                color: .black.opacity(isHovered ? 0.08 : 0.04),
                radius: isHovered ? 12 : 6,
                y: isHovered ? 4 : 2
            )
            .animation(.easeOut(duration: 0.2), value: isHovered)
            .onHover { hovering in
                isHovered = hovering
            }
    }
}

// MARK: - View Extensions

extension View {
    func petBreathing() -> some View {
        modifier(PetBreathingModifier())
    }

    func charIdle(_ characterId: String) -> some View {
        modifier(CharIdleModifier(characterId: characterId))
    }

    func pulseGlow(color: Color) -> some View {
        modifier(PulseGlowModifier(color: color))
    }

    func cardHover() -> some View {
        modifier(CardHoverModifier())
    }

    func fadeUp() -> some View {
        modifier(FadeUpModifier())
    }

    func slideIn() -> some View {
        modifier(SlideInModifier())
    }

    func popIn() -> some View {
        modifier(PopInModifier())
    }

    func shimmer() -> some View {
        modifier(ShimmerModifier())
    }

    func livePulse(color: Color = Color(hex: "#6BCB77")) -> some View {
        modifier(LivePulseModifier(color: color))
    }

    func catFloat() -> some View {
        modifier(CatFloatModifier())
    }
}

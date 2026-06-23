import SwiftUI

struct TurnLoadingStates: View {
    let state: TurnState
    var actionCount: Int = 0
    var isGenerating: Bool = false
    var onRetry: () -> Void = {}
    var onSignIn: () -> Void = {}

    var body: some View {
        switch state {
        case .pending:
            pendingCard
        case .summarizing:
            summarizingCard
        case .ready:
            EmptyView()
        case .pendingOrphan:
            orphanCard
        case .failed(let reason):
            failedView(reason: reason)
        }
    }

    // MARK: - Pending (Working)

    private var pendingCard: some View {
        AnimatedStateCard(
            bgColor: Color(hex: "#1C40CF"),
            icon: "hammer.fill",
            iconAnimation: .bounce,
            showParticles: true,
            showShimmer: true
        ) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text("Working")
                        .font(.pixelSystem(size: 14, weight: .bold))
                        .foregroundColor(.white)
                    PulsingDots(color: .white)
                }
                Text(pendingDetail)
                    .font(CodepetTheme.body(12))
                    .foregroundColor(Color.white.opacity(0.75))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var pendingDetail: String {
        switch actionCount {
        case 0:
            return "Watching… Claude may still be thinking. The story arrives when this turn closes."
        case 1:
            return "1 action so far. The story will appear once Claude is done."
        default:
            return "\(actionCount) actions so far. The story will appear once Claude is done."
        }
    }

    // MARK: - Summarizing

    private var summarizingCard: some View {
        AnimatedStateCard(
            bgColor: Color(hex: "#9538CF"),
            icon: "sparkles",
            iconAnimation: .spin,
            showParticles: true,
            showShimmer: true
        ) {
            VStack(alignment: .leading, spacing: 4) {
                if isGenerating {
                    HStack(spacing: 8) {
                        Text("Writing the story")
                            .font(.pixelSystem(size: 14, weight: .bold))
                            .foregroundColor(.white)
                        PulsingDots(color: Color.white.opacity(0.8))
                    }
                    Text("Your pet is crafting the narrative now.")
                        .font(CodepetTheme.body(12))
                        .foregroundColor(Color.white.opacity(0.75))
                } else {
                    HStack(spacing: 8) {
                        Text("Summarizing")
                            .font(.pixelSystem(size: 14, weight: .bold))
                            .foregroundColor(.white)
                        PulsingDots(color: Color.white.opacity(0.8))
                    }
                    VStack(alignment: .leading, spacing: 5) {
                        ShimmerSkeletonLine(width: 0.85)
                        ShimmerSkeletonLine(width: 0.6)
                    }
                    .padding(.top, 2)
                }
            }
        }
    }

    // MARK: - Orphan (Session left unfinished)

    private var orphanCard: some View {
        AnimatedStateCard(
            bgColor: Color(hex: "#F58345"),
            icon: "moon.zzz.fill",
            iconAnimation: .float,
            showParticles: false,
            showShimmer: false
        ) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Session left unfinished")
                    .font(.pixelSystem(size: 14, weight: .bold))
                    .foregroundColor(.white)
                Text("This turn didn't close normally — Claude Code may have been closed mid-way.")
                    .font(CodepetTheme.body(12))
                    .foregroundColor(Color.white.opacity(0.75))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Failed

    @ViewBuilder
    private func failedView(reason: FailureReason) -> some View {
        let (title, detail, icon, action): (String, String, String, () -> Void) = {
            switch reason {
            case .network:
                return ("Couldn't reach the server",
                        "Network seems to be acting up. You can try again.",
                        "wifi.slash", onRetry)
            case .quota:
                return ("Daily limit reached",
                        "You've hit 50 summaries today. Resets at 00:00 UTC.",
                        "gauge.with.dots.needle.33percent", onRetry)
            case .auth:
                return ("Sign in again",
                        "Your sign-in has expired.",
                        "person.badge.key.fill", onSignIn)
            case .badResponse:
                return ("Summary error",
                        "AI returned unexpected data. You can try again.",
                        "exclamationmark.bubble.fill", onRetry)
            case .unknown:
                return ("Couldn't summarize",
                        "Something went wrong. You can try again.",
                        "questionmark.diamond.fill", onRetry)
            }
        }()

        AnimatedStateCard(
            bgColor: Color(hex: "#E24B4A"),
            icon: icon,
            iconAnimation: .shake,
            showParticles: false,
            showShimmer: false
        ) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.pixelSystem(size: 14, weight: .bold))
                    .foregroundColor(.white)
                Text(detail)
                    .font(CodepetTheme.body(12))
                    .foregroundColor(Color.white.opacity(0.75))
                    .fixedSize(horizontal: false, vertical: true)

                Button(action: action) {
                    Text(reason == .auth ? "Sign in" : "Try again")
                }
                .buttonStyle(PixelButtonStyle(
                    fill: .white,
                    foreground: Color(hex: "#E24B4A"),
                    paddingH: 12,
                    paddingV: 6,
                    blockSize: 2,
                    steps: 1,
                    borderWidth: 2,
                    shadowOffset: 2,
                    font: .pixelSystem(size: 11, weight: .bold)
                ))
                .padding(.top, 2)
            }
        }
    }
}

// MARK: - Animated State Card (shared layout + effects)

private enum IconAnimation {
    case bounce, spin, float, shake
}

private struct AnimatedStateCard<Content: View>: View {
    let bgColor: Color
    let icon: String
    let iconAnimation: IconAnimation
    let showParticles: Bool
    let showShimmer: Bool
    @ViewBuilder let content: () -> Content

    @State private var glowPhase: CGFloat = 0
    @State private var shimmerOffset: CGFloat = -1.2

    var body: some View {
        PixelCard(fill: bgColor, shadowOffset: 2, blockSize: 2, steps: 2, borderWidth: 2) {
            ZStack {
                // Shimmer sweep across the whole card
                if showShimmer {
                    GeometryReader { geo in
                        LinearGradient(
                            stops: [
                                .init(color: .clear, location: 0),
                                .init(color: Color.white.opacity(0.12), location: 0.45),
                                .init(color: Color.white.opacity(0.18), location: 0.5),
                                .init(color: Color.white.opacity(0.12), location: 0.55),
                                .init(color: .clear, location: 1),
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        .frame(width: geo.size.width * 0.6)
                        .offset(x: shimmerOffset * geo.size.width)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                    }
                    .clipped()
                }

                // Floating particles
                if showParticles {
                    FloatingParticles(color: .white)
                }

                // Main content row
                HStack(spacing: 14) {
                    // Animated icon area with breathing glow
                    ZStack {
                        // Glow ring behind icon
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.white.opacity(0.05 + glowPhase * 0.12))
                            .frame(width: 58, height: 58)

                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.white.opacity(0.15 + glowPhase * 0.08))
                            .frame(width: 52, height: 52)

                        AnimatedIcon(name: icon, animation: iconAnimation)
                    }
                    .frame(width: 58, height: 58)

                    content()
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 14)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 2).repeatForever(autoreverses: true)) {
                glowPhase = 1
            }
            if showShimmer {
                withAnimation(.linear(duration: 3).repeatForever(autoreverses: false)) {
                    shimmerOffset = 1.6
                }
            }
        }
    }
}

// MARK: - Animated Icon

private struct AnimatedIcon: View {
    let name: String
    let animation: IconAnimation
    @State private var animating = false

    var body: some View {
        icon
            .onAppear {
                // Delay slightly so initial state is captured before animating
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    animating = true
                }
            }
    }

    @ViewBuilder
    private var icon: some View {
        let base = Image(systemName: name)
            .font(.system(size: 22, weight: .bold))
            .foregroundColor(.white)

        switch animation {
        case .bounce:
            base
                .rotationEffect(.degrees(animating ? -15 : 15))
                .animation(
                    .easeInOut(duration: 0.6).repeatForever(autoreverses: true),
                    value: animating
                )
        case .spin:
            base
                .rotationEffect(.degrees(animating ? 360 : 0))
                .animation(
                    .linear(duration: 4).repeatForever(autoreverses: false),
                    value: animating
                )
        case .float:
            base
                .offset(y: animating ? -4 : 4)
                .animation(
                    .easeInOut(duration: 2).repeatForever(autoreverses: true),
                    value: animating
                )
        case .shake:
            base
                .offset(x: animating ? -2 : 2)
                .animation(
                    .easeInOut(duration: 0.15).repeatForever(autoreverses: true),
                    value: animating
                )
        }
    }
}

// MARK: - Floating Particles

private struct FloatingParticles: View {
    let color: Color

    private struct Particle: Identifiable {
        let id: Int
        let x: CGFloat      // 0...1 horizontal position
        let size: CGFloat
        let duration: Double
        let delay: Double
        let opacity: Double
    }

    private let particles: [Particle] = (0..<8).map { i in
        Particle(
            id: i,
            x: CGFloat.random(in: 0.05...0.95),
            size: CGFloat.random(in: 3...6),
            duration: Double.random(in: 2.5...4.5),
            delay: Double.random(in: 0...2),
            opacity: Double.random(in: 0.15...0.4)
        )
    }

    var body: some View {
        GeometryReader { geo in
            ForEach(particles) { p in
                SingleParticle(
                    color: color,
                    size: p.size,
                    opacity: p.opacity,
                    duration: p.duration,
                    delay: p.delay
                )
                .position(x: p.x * geo.size.width, y: geo.size.height * 0.5)
            }
        }
        .allowsHitTesting(false)
    }
}

private struct SingleParticle: View {
    let color: Color
    let size: CGFloat
    let opacity: Double
    let duration: Double
    let delay: Double

    @State private var yOffset: CGFloat = 20
    @State private var particleOpacity: Double = 0

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
            .opacity(particleOpacity)
            .offset(y: yOffset)
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                    withAnimation(
                        .easeOut(duration: duration)
                        .repeatForever(autoreverses: false)
                    ) {
                        yOffset = -40
                    }
                    withAnimation(
                        .easeInOut(duration: duration * 0.5)
                        .repeatForever(autoreverses: true)
                    ) {
                        particleOpacity = opacity
                    }
                }
            }
    }
}

// MARK: - Shimmer Skeleton Line

private struct ShimmerSkeletonLine: View {
    let width: CGFloat
    @State private var shimmerPhase: CGFloat = -1

    var body: some View {
        Rectangle()
            .fill(Color.white.opacity(0.2))
            .frame(maxWidth: .infinity)
            .frame(height: 10)
            .clipShape(RoundedRectangle(cornerRadius: 3))
            .scaleEffect(x: width, y: 1, anchor: .leading)
            .overlay(
                GeometryReader { geo in
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0),
                            .init(color: Color.white.opacity(0.3), location: 0.5),
                            .init(color: .clear, location: 1),
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: geo.size.width * 0.4)
                    .offset(x: shimmerPhase * geo.size.width)
                }
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 3))
            )
            .onAppear {
                withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                    shimmerPhase = 1.2
                }
            }
    }
}

// MARK: - Pulsing Dots

private struct PulsingDots: View {
    var color: Color = Color(hex: "#2D2B26")
    @State private var phase: Int = 0

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(color)
                    .frame(width: 6, height: 6)
                    .scaleEffect(phase == i ? 1.3 : 0.8)
                    .opacity(phase == i ? 1.0 : 0.3)
            }
        }
        .onAppear { startAnimation() }
    }

    private func startAnimation() {
        Timer.scheduledTimer(withTimeInterval: 0.35, repeats: true) { _ in
            withAnimation(.easeInOut(duration: 0.25)) {
                phase = (phase + 1) % 3
            }
        }
    }
}

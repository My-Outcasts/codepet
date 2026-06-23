import SwiftUI

// MARK: - Kingdom Data for Platformer

struct KingdomData {
    let id: Int
    let name: String
    let subtitle: String
    let gradientColors: [Color]
    let accentColor: Color
    let groundColor: Color
    let groundHighlight: Color
    let nodeGlowColor: Color
    let tierIndex: Int  // index into GameData.skillTiers

    static let all: [KingdomData] = [
        KingdomData(
            id: 0, name: "THE MOLTEN FORGE", subtitle: "TIER 1 · FOUNDATIONS",
            gradientColors: [Color(hex: "#0D0518"), Color(hex: "#1a0a2e"), Color(hex: "#3A1530"), Color(hex: "#6A2020"), Color(hex: "#FF4500")],
            accentColor: Color(hex: "#FF8040"), groundColor: Color(hex: "#4A1A10"), groundHighlight: Color(hex: "#FF6030"),
            nodeGlowColor: Color(hex: "#FF6030"), tierIndex: 0
        ),
        KingdomData(
            id: 1, name: "THE FROZEN SPIRE", subtitle: "TIER 2 · CONTEXT & STRUCTURE",
            gradientColors: [Color(hex: "#0A1628"), Color(hex: "#0E2040"), Color(hex: "#183060"), Color(hex: "#306090"), Color(hex: "#88D0F0")],
            accentColor: Color(hex: "#88D0F0"), groundColor: Color(hex: "#1A3050"), groundHighlight: Color(hex: "#60B0E0"),
            nodeGlowColor: Color(hex: "#60B0E0"), tierIndex: 1
        ),
        KingdomData(
            id: 2, name: "THE ETERNAL GARDEN", subtitle: "TIER 3 · ADVANCED",
            gradientColors: [Color(hex: "#1A0828"), Color(hex: "#2A1040"), Color(hex: "#4A2068"), Color(hex: "#8040A0"), Color(hex: "#F0A8D0")],
            accentColor: Color(hex: "#F0A8D0"), groundColor: Color(hex: "#3A1848"), groundHighlight: Color(hex: "#D080B0"),
            nodeGlowColor: Color(hex: "#D080B0"), tierIndex: 2
        ),
        KingdomData(
            id: 3, name: "THE MYSTIC GROVE", subtitle: "TIER 4 · EXPERT",
            gradientColors: [Color(hex: "#0A1810"), Color(hex: "#102818"), Color(hex: "#184020"), Color(hex: "#306830"), Color(hex: "#90D870")],
            accentColor: Color(hex: "#90D870"), groundColor: Color(hex: "#1A3018"), groundHighlight: Color(hex: "#60C040"),
            nodeGlowColor: Color(hex: "#60C040"), tierIndex: 3
        ),
    ]
}

// MARK: - Sessions View (Vertical Schematic Platformer)

struct SessionsView: View {
    @EnvironmentObject var appState: AppState
    @State private var currentKingdom: Int = 0
    @State private var selectedChallenge: Challenge? = nil
    @State private var showNodePopup: Bool = false
    @State private var popupSkill: Skill? = nil
    @State private var popupTierIndex: Int = 0
    @State private var showConfetti = false
    @State private var bobPhase: Bool = false
    @State private var pulsePhase: Bool = false
    @State private var sparklePhase: Bool = false
    @State private var floatPhase: CGFloat = 0
    @State private var particlePhase: CGFloat = 0

    private let kingdoms = KingdomData.all

    var body: some View {
        ZStack {
            // Full-screen kingdom background
            kingdomPage(kingdoms[currentKingdom])
                .ignoresSafeArea()
                .id(currentKingdom)
                .transition(.opacity)

            // Left arrow
            if currentKingdom > 0 {
                VStack {
                    Spacer()
                    Button(action: { navigateKingdom(-1) }) {
                        arrowButton(systemName: "chevron.left")
                    }
                    .buttonStyle(.plain)
                    Spacer()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 14)
            }

            // Right arrow
            if currentKingdom < kingdoms.count - 1 {
                VStack {
                    Spacer()
                    Button(action: { navigateKingdom(1) }) {
                        arrowButton(systemName: "chevron.right")
                    }
                    .buttonStyle(.plain)
                    Spacer()
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.trailing, 14)
            }

            // Bottom progress dots
            VStack {
                Spacer()
                progressDots
                    .padding(.bottom, 14)
            }

            // Node popup overlay
            if showNodePopup, let skill = popupSkill {
                nodePopupOverlay(skill: skill, tierIndex: popupTierIndex)
            }

            // Full challenge overlay (6-stage flow)
            if let challenge = selectedChallenge {
                Color.black.opacity(0.5)
                    .ignoresSafeArea()
                    .onTapGesture { }

                ChallengeOverlayView(
                    challenge: challenge,
                    difficultyLevel: appState.difficultyLevel,
                    onComplete: { xpEarned, attempt in
                        withAnimation(.easeOut(duration: 0.2)) {
                            if !appState.completedChallenges.contains(challenge.id) {
                                appState.completedChallenges.append(challenge.id)
                                appState.weeklyStats.challengesDone += 1
                            }
                            appState.addXP(xpEarned)
                            appState.performanceHistory.append(
                                PerformanceEntry(score: 100, date: Date(), skillId: challenge.id)
                            )
                            selectedChallenge = nil
                            showConfetti = true
                            SoundManager.shared.playSuccess()
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                                showConfetti = false
                            }
                        }
                    },
                    onClose: {
                        withAnimation(.easeOut(duration: 0.2)) {
                            selectedChallenge = nil
                        }
                    }
                )
                .frame(width: 520, height: 620)
                .clipShape(RoundedRectangle(cornerRadius: 20))
                .shadow(color: .black.opacity(0.25), radius: 30, y: 10)
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }

            // Confetti
            if showConfetti {
                ConfettiView()
                    .allowsHitTesting(false)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: selectedChallenge != nil)
        .onAppear {
            withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true)) {
                bobPhase = true
            }
            withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                pulsePhase = true
            }
            withAnimation(.linear(duration: 3.0).repeatForever(autoreverses: false)) {
                sparklePhase = true
            }
            withAnimation(.easeInOut(duration: 4.0).repeatForever(autoreverses: true)) {
                floatPhase = 1.0
            }
            withAnimation(.linear(duration: 8.0).repeatForever(autoreverses: false)) {
                particlePhase = 1.0
            }
        }
    }

    // MARK: - Kingdom Page

    private func kingdomPage(_ kingdom: KingdomData) -> some View {
        let tier = GameData.skillTiers[kingdom.tierIndex]
        let skills = tier.skills

        return GeometryReader { geo in
            ZStack {
                // Background gradient + details
                kingdomBackground(kingdom: kingdom, size: geo.size)

                // Animated floating particles layer
                floatingParticles(kingdom: kingdom, size: geo.size)

                // Ground strip at bottom
                VStack {
                    Spacer()
                    ZStack(alignment: .top) {
                        Rectangle()
                            .fill(
                                LinearGradient(
                                    colors: [kingdom.groundHighlight.opacity(0.5), kingdom.groundColor, kingdom.groundColor.opacity(0.9)],
                                    startPoint: .top, endPoint: .bottom
                                )
                            )
                            .frame(height: geo.size.height * 0.22)

                        Rectangle()
                            .fill(kingdom.groundHighlight.opacity(0.6))
                            .frame(height: 3)

                        LinearGradient(
                            colors: [kingdom.nodeGlowColor.opacity(0.15), .clear],
                            startPoint: .top, endPoint: .bottom
                        )
                        .frame(height: 40)
                    }
                }
                .ignoresSafeArea(edges: .bottom)

                // Kingdom title at top
                VStack(spacing: 6) {
                    Text(kingdom.name)
                        .font(.pixelSystem(size: 18, weight: .black, design: .monospaced))
                        .foregroundColor(.white)
                        .shadow(color: kingdom.accentColor.opacity(0.8), radius: 24)
                        .shadow(color: kingdom.accentColor.opacity(0.4), radius: 48)
                        .tracking(4)

                    Text(kingdom.subtitle)
                        .font(.pixelSystem(size: 9, weight: .semibold, design: .monospaced))
                        .foregroundColor(kingdom.accentColor.opacity(0.9))
                        .tracking(2)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .padding(.top, 20)

                // Horizontal node path — nodes go left to right, each one higher than the last
                horizontalStaircasePath(skills: skills, kingdom: kingdom, size: geo.size)
            }
        }
    }

    // MARK: - Horizontal Staircase Path

    private func horizontalStaircasePath(skills: [Skill], kingdom: KingdomData, size: CGSize) -> some View {
        let activeNodeIndex = findActiveNodeIndex(skills: skills)
        let nodeCount = skills.count
        // Nodes spaced evenly across the width
        let nodeSpacing = size.width / CGFloat(nodeCount + 1)
        // Zigzag: odd nodes high, even nodes low
        let highY = size.height * 0.28   // high position
        let lowY = size.height * 0.58    // low position

        return ZStack {
            // Connection lines between nodes (zigzag curves)
            ForEach(0..<nodeCount - 1, id: \.self) { i in
                let x1 = nodeSpacing * CGFloat(i + 1)
                let y1 = i % 2 == 0 ? lowY : highY
                let x2 = nodeSpacing * CGFloat(i + 2)
                let y2 = (i + 1) % 2 == 0 ? lowY : highY
                let completed = nodeState(for: skills[i]) == .completed

                // Main path line — S-curve between zigzag positions
                Path { p in
                    p.move(to: CGPoint(x: x1, y: y1))
                    p.addCurve(
                        to: CGPoint(x: x2, y: y2),
                        control1: CGPoint(x: (x1 + x2) / 2, y: y1),
                        control2: CGPoint(x: (x1 + x2) / 2, y: y2)
                    )
                }
                .stroke(
                    completed ? Color(hex: "#6BCB77").opacity(0.6) : kingdom.accentColor.opacity(0.15),
                    style: StrokeStyle(lineWidth: completed ? 4 : 3, lineCap: .round, dash: completed ? [] : [8, 6])
                )

                // Glow on completed
                if completed {
                    Path { p in
                        p.move(to: CGPoint(x: x1, y: y1))
                        p.addCurve(
                            to: CGPoint(x: x2, y: y2),
                            control1: CGPoint(x: (x1 + x2) / 2, y: y1),
                            control2: CGPoint(x: (x1 + x2) / 2, y: y2)
                        )
                    }
                    .stroke(Color(hex: "#6BCB77").opacity(0.15), style: StrokeStyle(lineWidth: 12, lineCap: .round))
                }
            }

            // Nodes — zigzag: index 0 low, index 1 high, index 2 low, index 3 high
            ForEach(Array(skills.enumerated()), id: \.element.id) { index, skill in
                let state = nodeState(for: skill)
                let isActive = index == activeNodeIndex
                let x = nodeSpacing * CGFloat(index + 1)
                let y = index % 2 == 0 ? lowY : highY

                VStack(spacing: 0) {
                    // Character above active node
                    if isActive {
                        characterSprite(kingdom: kingdom)
                            .offset(y: bobPhase ? -8 : 4)
                    }

                    // The node
                    nodeView(skill: skill, state: state, kingdom: kingdom, index: index)
                        .id("node-\(index)")
                        .onTapGesture {
                            guard state != .locked else { return }
                            SoundManager.shared.playTap()
                            popupSkill = skill
                            popupTierIndex = kingdom.tierIndex
                            withAnimation(.spring(response: 0.25)) {
                                showNodePopup = true
                            }
                        }
                }
                .position(x: x, y: isActive ? y - 60 : y)
            }
        }
    }

    // MARK: - Kingdom Background (Canvas)

    private func kingdomBackground(kingdom: KingdomData, size: CGSize) -> some View {
        ZStack {
            // Main gradient
            LinearGradient(
                colors: kingdom.gradientColors,
                startPoint: .top, endPoint: .bottom
            )

            // Atmospheric effects per kingdom
            Canvas { context, canvasSize in
                drawKingdomDetails(context: context, size: canvasSize, kingdomId: kingdom.id)
            }

            // Radial glow from bottom
            RadialGradient(
                colors: [kingdom.nodeGlowColor.opacity(0.3), .clear],
                center: .bottom, startRadius: 0, endRadius: size.height * 0.7
            )

            // Secondary ambient glow
            RadialGradient(
                colors: [kingdom.accentColor.opacity(0.08), .clear],
                center: UnitPoint(x: 0.3, y: 0.4), startRadius: 50, endRadius: size.width * 0.6
            )
        }
    }

    // MARK: - Floating Particles (Animated)

    private func floatingParticles(kingdom: KingdomData, size: CGSize) -> some View {
        let particleColor: Color = {
            switch kingdom.id {
            case 0: return Color(hex: "#FF8040")
            case 1: return Color(hex: "#B0E8FF")
            case 2: return Color(hex: "#F0A8D0")
            case 3: return Color(hex: "#C0FF60")
            default: return .white
            }
        }()

        return ZStack {
            // Rising particles
            ForEach(0..<12, id: \.self) { i in
                let baseX = CGFloat(i) / 12.0 * size.width
                let baseY = size.height * CGFloat(0.3 + Double(i % 4) * 0.15)
                Circle()
                    .fill(particleColor.opacity(Double(0.1 + Double(i % 3) * 0.1)))
                    .frame(width: CGFloat(3 + i % 4), height: CGFloat(3 + i % 4))
                    .offset(
                        x: baseX + sin(floatPhase * .pi * 2 + CGFloat(i)) * 15 - size.width / 2,
                        y: baseY - floatPhase * 40 + CGFloat(i % 3) * 20 - size.height / 2
                    )
                    .blur(radius: CGFloat(i % 3))
            }
        }
        .allowsHitTesting(false)
    }

    private func drawKingdomDetails(context: GraphicsContext, size: CGSize, kingdomId: Int) {
        let w = size.width
        let h = size.height

        // Stars (all kingdoms)
        let starPositions: [(CGFloat, CGFloat, CGFloat)] = [
            (0.06, 0.05, 1.8), (0.15, 0.12, 1.2), (0.28, 0.03, 1.5),
            (0.38, 0.08, 1.0), (0.50, 0.06, 1.8), (0.62, 0.11, 1.0),
            (0.72, 0.04, 1.5), (0.82, 0.09, 1.2), (0.92, 0.06, 1.5),
            (0.10, 0.18, 0.8), (0.33, 0.15, 1.0), (0.55, 0.14, 0.8),
            (0.77, 0.17, 1.0), (0.45, 0.20, 0.7), (0.88, 0.13, 0.8),
            (0.20, 0.22, 0.6), (0.65, 0.19, 0.9), (0.42, 0.25, 0.7),
        ]
        for (fx, fy, r) in starPositions {
            let path = Path(ellipseIn: CGRect(x: w * fx - r, y: h * fy - r, width: r * 2, height: r * 2))
            context.fill(path, with: .color(.white.opacity(Double.random(in: 0.3...0.9))))
        }

        switch kingdomId {
        case 0: // Molten Forge — volcanoes with lava
            // Far volcano left
            var v1 = Path()
            v1.move(to: CGPoint(x: w * -0.05, y: h))
            v1.addLine(to: CGPoint(x: w * 0.08, y: h * 0.15))
            v1.addLine(to: CGPoint(x: w * 0.12, y: h * 0.15))
            v1.addLine(to: CGPoint(x: w * 0.28, y: h))
            v1.closeSubpath()
            context.fill(v1, with: .color(Color(hex: "#1A0A10").opacity(0.9)))

            // Lava glow at left peak
            let lg1 = Path(ellipseIn: CGRect(x: w * 0.06, y: h * 0.12, width: w * 0.08, height: h * 0.06))
            context.fill(lg1, with: .color(Color(hex: "#FF4500").opacity(0.5)))
            let lg1b = Path(ellipseIn: CGRect(x: w * 0.07, y: h * 0.13, width: w * 0.06, height: h * 0.04))
            context.fill(lg1b, with: .color(Color(hex: "#FF6030").opacity(0.7)))

            // Far volcano right (taller)
            var v2 = Path()
            v2.move(to: CGPoint(x: w * 0.68, y: h))
            v2.addLine(to: CGPoint(x: w * 0.85, y: h * 0.08))
            v2.addLine(to: CGPoint(x: w * 0.89, y: h * 0.08))
            v2.addLine(to: CGPoint(x: w * 1.05, y: h))
            v2.closeSubpath()
            context.fill(v2, with: .color(Color(hex: "#1A0A10").opacity(0.85)))

            // Lava glow at right peak
            let lg2 = Path(ellipseIn: CGRect(x: w * 0.82, y: h * 0.05, width: w * 0.10, height: h * 0.07))
            context.fill(lg2, with: .color(Color(hex: "#FF4500").opacity(0.5)))
            let lg2b = Path(ellipseIn: CGRect(x: w * 0.84, y: h * 0.06, width: w * 0.06, height: h * 0.04))
            context.fill(lg2b, with: .color(Color(hex: "#FF6030").opacity(0.8)))

            // Lava streams
            var s1 = Path()
            s1.move(to: CGPoint(x: w * 0.87, y: h * 0.10))
            s1.addLine(to: CGPoint(x: w * 0.88, y: h * 0.60))
            s1.addLine(to: CGPoint(x: w * 0.885, y: h * 0.60))
            s1.addLine(to: CGPoint(x: w * 0.875, y: h * 0.10))
            s1.closeSubpath()
            context.fill(s1, with: .color(Color(hex: "#FF4500").opacity(0.35)))

            // Embers
            for i in 0..<16 {
                let fx = CGFloat(i) / 16.0 * w + CGFloat.random(in: -15...15)
                let fy = h * CGFloat.random(in: 0.20...0.85)
                let r: CGFloat = CGFloat.random(in: 1.5...4)
                let ember = Path(ellipseIn: CGRect(x: fx, y: fy, width: r, height: r))
                context.fill(ember, with: .color(Color(hex: "#FF8040").opacity(Double.random(in: 0.2...0.7))))
            }

        case 1: // Frozen Spire — ice mountains
            var m1 = Path()
            m1.move(to: CGPoint(x: w * -0.05, y: h))
            m1.addLine(to: CGPoint(x: w * 0.10, y: h * 0.12))
            m1.addLine(to: CGPoint(x: w * 0.15, y: h * 0.15))
            m1.addLine(to: CGPoint(x: w * 0.30, y: h))
            m1.closeSubpath()
            context.fill(m1, with: .color(Color(hex: "#1A3858").opacity(0.8)))

            // Snow cap
            var cap1 = Path()
            cap1.move(to: CGPoint(x: w * 0.06, y: h * 0.22))
            cap1.addLine(to: CGPoint(x: w * 0.10, y: h * 0.12))
            cap1.addLine(to: CGPoint(x: w * 0.15, y: h * 0.15))
            cap1.addLine(to: CGPoint(x: w * 0.17, y: h * 0.22))
            cap1.closeSubpath()
            context.fill(cap1, with: .color(Color(hex: "#D0F0FF").opacity(0.25)))

            var m2 = Path()
            m2.move(to: CGPoint(x: w * 0.65, y: h))
            m2.addLine(to: CGPoint(x: w * 0.82, y: h * 0.06))
            m2.addLine(to: CGPoint(x: w * 0.87, y: h * 0.10))
            m2.addLine(to: CGPoint(x: w * 1.05, y: h))
            m2.closeSubpath()
            context.fill(m2, with: .color(Color(hex: "#1A3858").opacity(0.7)))

            var cap2 = Path()
            cap2.move(to: CGPoint(x: w * 0.78, y: h * 0.16))
            cap2.addLine(to: CGPoint(x: w * 0.82, y: h * 0.06))
            cap2.addLine(to: CGPoint(x: w * 0.87, y: h * 0.10))
            cap2.addLine(to: CGPoint(x: w * 0.90, y: h * 0.16))
            cap2.closeSubpath()
            context.fill(cap2, with: .color(Color(hex: "#D0F0FF").opacity(0.25)))

            // Aurora
            let aurora = Path(ellipseIn: CGRect(x: w * 0.20, y: h * 0.02, width: w * 0.55, height: h * 0.18))
            context.fill(aurora, with: .color(Color(hex: "#60C0E0").opacity(0.06)))

            // Ice crystals
            for i in 0..<10 {
                let fx = CGFloat(i) / 10.0 * w + CGFloat.random(in: -20...20)
                let fy = h * CGFloat.random(in: 0.20...0.80)
                let sz: CGFloat = CGFloat.random(in: 3...6)
                var d = Path()
                d.move(to: CGPoint(x: fx, y: fy - sz))
                d.addLine(to: CGPoint(x: fx + sz, y: fy))
                d.addLine(to: CGPoint(x: fx, y: fy + sz))
                d.addLine(to: CGPoint(x: fx - sz, y: fy))
                d.closeSubpath()
                context.fill(d, with: .color(Color(hex: "#B0E8FF").opacity(Double.random(in: 0.15...0.45))))
            }

        case 2: // Eternal Garden — vines, flowers, petals
            for i in 0..<18 {
                let fx = CGFloat(i) / 18.0 * w + CGFloat.random(in: -15...15)
                let fy = h * CGFloat.random(in: 0.10...0.85)
                let r: CGFloat = CGFloat.random(in: 3...8)
                let petal = Path(ellipseIn: CGRect(x: fx, y: fy, width: r * 1.5, height: r))
                let cols: [Color] = [Color(hex: "#F0A8D0"), Color(hex: "#D080B0"), Color(hex: "#FFB0E0"), Color(hex: "#E090C0"), Color(hex: "#C070A0")]
                context.fill(petal, with: .color(cols[i % cols.count].opacity(Double.random(in: 0.12...0.40))))
            }

            // Vine silhouettes
            var v1 = Path()
            v1.move(to: CGPoint(x: 0, y: h * 0.1))
            v1.addQuadCurve(to: CGPoint(x: w * 0.06, y: h * 0.4), control: CGPoint(x: w * 0.04, y: h * 0.2))
            v1.addQuadCurve(to: CGPoint(x: 0, y: h * 0.7), control: CGPoint(x: w * 0.02, y: h * 0.55))
            context.stroke(v1, with: .color(Color(hex: "#6A3080").opacity(0.35)), lineWidth: 5)

            var v2 = Path()
            v2.move(to: CGPoint(x: w, y: h * 0.05))
            v2.addQuadCurve(to: CGPoint(x: w * 0.92, y: h * 0.35), control: CGPoint(x: w * 0.96, y: h * 0.15))
            v2.addQuadCurve(to: CGPoint(x: w, y: h * 0.65), control: CGPoint(x: w * 0.98, y: h * 0.50))
            context.stroke(v2, with: .color(Color(hex: "#6A3080").opacity(0.35)), lineWidth: 5)

        case 3: // Mystic Grove — trees and fireflies
            for i in 0..<6 {
                let bx = w * CGFloat([0.02, 0.18, 0.40, 0.58, 0.78, 0.95][i])
                let by = h * 0.95
                let tw: CGFloat = 12
                let th = h * CGFloat([0.22, 0.28, 0.20, 0.30, 0.25, 0.18][i])
                let trunk = Path(CGRect(x: bx - tw / 2, y: by - th, width: tw, height: th))
                context.fill(trunk, with: .color(Color(hex: "#1A3018").opacity(0.5)))

                let cr = CGFloat([28, 36, 24, 40, 32, 22][i])
                let canopy = Path(ellipseIn: CGRect(x: bx - cr, y: by - th - cr * 1.3, width: cr * 2, height: cr * 1.6))
                context.fill(canopy, with: .color(Color(hex: "#1A4018").opacity(0.5)))
            }

            // Glowing mushrooms
            for _ in 0..<7 {
                let mx = w * CGFloat.random(in: 0.05...0.95)
                let my = h * CGFloat.random(in: 0.80...0.95)
                let cap = Path(ellipseIn: CGRect(x: mx - 7, y: my - 5, width: 14, height: 10))
                context.fill(cap, with: .color(Color(hex: "#80FF40").opacity(Double.random(in: 0.12...0.28))))
                let halo = Path(ellipseIn: CGRect(x: mx - 14, y: my - 10, width: 28, height: 20))
                context.fill(halo, with: .color(Color(hex: "#80FF40").opacity(0.04)))
                let stem = Path(CGRect(x: mx - 2, y: my, width: 4, height: 10))
                context.fill(stem, with: .color(Color(hex: "#306030").opacity(0.25)))
            }

            // Fireflies
            for i in 0..<20 {
                let fx = CGFloat(i) / 20.0 * w + CGFloat.random(in: -25...25)
                let fy = h * CGFloat.random(in: 0.10...0.80)
                let r: CGFloat = CGFloat.random(in: 2...4)
                let ff = Path(ellipseIn: CGRect(x: fx, y: fy, width: r, height: r))
                context.fill(ff, with: .color(Color(hex: "#C0FF60").opacity(Double.random(in: 0.2...0.65))))
                let halo = Path(ellipseIn: CGRect(x: fx - 4, y: fy - 4, width: r + 8, height: r + 8))
                context.fill(halo, with: .color(Color(hex: "#C0FF60").opacity(Double.random(in: 0.03...0.08))))
            }

        default: break
        }
    }

    // MARK: - Single Node (Vertical Layout)

    private func nodeView(skill: Skill, state: NodeState, kingdom: KingdomData, index: Int) -> some View {
        let nodeSize: CGFloat = skill.nodeType == .boss ? 96 : 82
        let isActive = state == .active

        return VStack(spacing: 10) {
            // Type badge above node
            Text(typeBadgeText(skill.nodeType))
                .font(.pixelSystem(size: 7, weight: .black, design: .monospaced))
                .foregroundColor(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(typeBadgeColor(skill.nodeType))
                .cornerRadius(6)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(.white.opacity(0.3), lineWidth: 1)
                )
                .shadow(color: typeBadgeColor(skill.nodeType).opacity(0.5), radius: 4)

            ZStack {
                // Pulsing glow ring for active node
                if isActive {
                    RoundedRectangle(cornerRadius: 18)
                        .fill(kingdom.accentColor.opacity(0.15))
                        .frame(width: nodeSize + 20, height: nodeSize + 20)
                        .scaleEffect(pulsePhase ? 1.15 : 1.0)

                    RoundedRectangle(cornerRadius: 16)
                        .stroke(kingdom.accentColor.opacity(pulsePhase ? 0.6 : 0.2), lineWidth: 2)
                        .frame(width: nodeSize + 14, height: nodeSize + 14)
                        .scaleEffect(pulsePhase ? 1.08 : 1.0)
                }

                // Node box
                RoundedRectangle(cornerRadius: 16)
                    .fill(nodeBackground(state: state, kingdom: kingdom))
                    .frame(width: nodeSize, height: nodeSize)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(nodeBorderColor(state: state, kingdom: kingdom), lineWidth: 3)
                    )
                    .overlay(
                        // Inner bottom shadow
                        VStack {
                            Spacer()
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.black.opacity(0.2))
                                .frame(height: nodeSize * 0.14)
                                .padding(.horizontal, 5)
                                .padding(.bottom, 5)
                        }
                        .frame(width: nodeSize, height: nodeSize)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                    )
                    .shadow(color: isActive ? kingdom.accentColor.opacity(0.7) : state == .completed ? Color(hex: "#6BCB77").opacity(0.3) : .clear, radius: isActive ? 20 : 8)

                // Icon
                if state == .completed {
                    Image(systemName: "checkmark")
                        .font(.pixelSystem(size: 34, weight: .bold))
                        .foregroundColor(.white)
                        .shadow(color: .white.opacity(0.5), radius: 4)
                } else if isActive {
                    Image(systemName: "play.fill")
                        .font(.pixelSystem(size: 30))
                        .foregroundColor(.white)
                        .shadow(color: .white.opacity(0.3), radius: 6)
                        .scaleEffect(pulsePhase ? 1.1 : 0.95)
                } else {
                    Image(systemName: "lock.fill")
                        .font(.pixelSystem(size: 24))
                        .foregroundColor(.white.opacity(0.35))
                }
            }

            // Skill name
            Text(PersonaContent.resolve(PersonaContent.skillName, id: skill.id, persona: appState.languagePersona, fallback: skill.name))
                .font(.pixelSystem(size: 11, weight: .bold, design: .monospaced))
                .foregroundColor(state == .locked ? Color(hex: "#E0D0FF").opacity(0.35) : .white)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .frame(maxWidth: 160)
                .shadow(color: .black.opacity(0.8), radius: 6, y: 2)

            // Reward line
            rewardLabel(skill: skill, state: state)
        }
        .opacity(state == .locked ? 0.4 : 1)
        .scaleEffect(isActive ? 1.05 : 1.0)
        .animation(.easeInOut(duration: 0.3), value: isActive)
    }

    // MARK: - Reward Label

    private func rewardLabel(skill: Skill, state: NodeState) -> some View {
        let xp = xpForNode(skill)
        let coins = coinsForNode(skill)

        return Group {
            if state == .completed {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.pixelSystem(size: 8))
                    Text("\(xp) XP earned")
                        .font(.pixelSystem(size: 8, weight: .bold, design: .monospaced))
                }
                .foregroundColor(Color(hex: "#6BCB77"))
            } else if state == .active {
                HStack(spacing: 4) {
                    Text("\(xp) XP")
                        .font(.pixelSystem(size: 8, weight: .bold, design: .monospaced))
                        .foregroundColor(Color(hex: "#FFD700"))
                    Text("+")
                        .font(.pixelSystem(size: 8, weight: .bold))
                        .foregroundColor(Color(hex: "#FFD700").opacity(0.6))
                    Text("\(coins)")
                        .font(.pixelSystem(size: 8, weight: .bold, design: .monospaced))
                        .foregroundColor(Color(hex: "#FFD700"))
                    Text("🪙")
                        .font(.pixelSystem(size: 8))
                }
                .shadow(color: Color(hex: "#FFD700").opacity(0.4), radius: 6)
            } else {
                HStack(spacing: 4) {
                    Image(systemName: "lock.fill")
                        .font(.pixelSystem(size: 7))
                    Text("\(xp) XP + \(coins) 🪙")
                        .font(.pixelSystem(size: 8, weight: .bold, design: .monospaced))
                }
                .foregroundColor(Color(hex: "#FFD700").opacity(0.3))
            }
        }
    }

    // MARK: - Character Sprite (Large + Animated)

    private func characterSprite(kingdom: KingdomData) -> some View {
        Group {
            let charId = appState.activeChar
            if let character = PetCharacter.all[charId] {
                VStack(spacing: 8) {
                    // Speech bubble with bounce
                    Text(speechText(for: character))
                        .font(.pixelSystem(size: 9, weight: .semibold, design: .monospaced))
                        .foregroundColor(Color(hex: "#E0D0FF"))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(Color(hex: "#140C24").opacity(0.95))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10)
                                        .stroke(Color(hex: "#8B7BE8"), lineWidth: 2)
                                )
                        )
                        .shadow(color: Color(hex: "#8B7BE8").opacity(0.3), radius: 10, y: 3)
                        .scaleEffect(pulsePhase ? 1.04 : 0.96)
                        .offset(y: pulsePhase ? -4 : 0)

                    ZStack {
                        // Sparkle ring rotating around character
                        ForEach(0..<6, id: \.self) { i in
                            let angle = (CGFloat(i) / 6.0) * 360.0 + (sparklePhase ? 360 : 0)
                            let rad = angle * .pi / 180
                            let radius: CGFloat = 58
                            Circle()
                                .fill(kingdom.accentColor.opacity(Double(0.3 + Double(i % 3) * 0.15)))
                                .frame(width: CGFloat(4 + i % 3), height: CGFloat(4 + i % 3))
                                .blur(radius: 1)
                                .offset(
                                    x: cos(rad) * radius,
                                    y: sin(rad) * radius * 0.5
                                )
                        }

                        // Outer glow aura
                        Circle()
                            .fill(
                                RadialGradient(
                                    colors: [kingdom.accentColor.opacity(0.15), kingdom.accentColor.opacity(0.05), .clear],
                                    center: .center, startRadius: 20, endRadius: 70
                                )
                            )
                            .frame(width: 140, height: 140)
                            .scaleEffect(pulsePhase ? 1.15 : 0.90)

                        // Platform glow under character
                        Ellipse()
                            .fill(
                                RadialGradient(
                                    colors: [kingdom.accentColor.opacity(0.5), kingdom.accentColor.opacity(0.15), kingdom.accentColor.opacity(0.0)],
                                    center: .center, startRadius: 0, endRadius: 55
                                )
                            )
                            .frame(width: 110, height: 28)
                            .offset(y: 52)
                            .scaleEffect(pulsePhase ? 1.12 : 0.88)

                        // Character image — LARGE with breathing scale
                        Image(character.imageName)
                            .resizable()
                            .interpolation(.none)
                            .scaledToFit()
                            .frame(width: 110, height: 110)
                            .scaleEffect(pulsePhase ? 1.03 : 0.97)
                            .shadow(color: kingdom.accentColor.opacity(0.4), radius: 16)
                            .shadow(color: .black.opacity(0.3), radius: 4, y: 4)
                    }
                }
            }
        }
    }

    private func speechText(for character: PetCharacter) -> String {
        if let first = character.greeting.first, !first.isEmpty {
            return first
        }
        return "Let's go!"
    }

    // MARK: - Node Popup

    private func nodePopupOverlay(skill: Skill, tierIndex: Int) -> some View {
        ZStack {
            Color.black.opacity(0.6)
                .ignoresSafeArea()
                .onTapGesture {
                    withAnimation(.spring(response: 0.25)) {
                        showNodePopup = false
                    }
                }

            VStack(spacing: 0) {
                // Header
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(typeBadgeColor(skill.nodeType).opacity(0.2))
                            .frame(width: 48, height: 48)
                        Text(skill.icon)
                            .font(.pixelSystem(size: 24))
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text(skill.nodeType.rawValue.uppercased())
                            .font(.pixelSystem(size: 7, weight: .bold, design: .monospaced))
                            .foregroundColor(typeBadgeColor(skill.nodeType))
                            .tracking(1.5)
                        Text(PersonaContent.resolve(PersonaContent.skillName, id: skill.id, persona: appState.languagePersona, fallback: skill.name))
                            .font(.pixelSystem(size: 13, weight: .bold, design: .monospaced))
                            .foregroundColor(.white)
                    }

                    Spacer()

                    Button(action: {
                        withAnimation(.spring(response: 0.25)) {
                            showNodePopup = false
                        }
                    }) {
                        Image(systemName: "xmark")
                            .font(.pixelSystem(size: 12, weight: .medium))
                            .foregroundColor(Color(hex: "#A89BF2"))
                            .padding(8)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(.white.opacity(0.1))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(.white.opacity(0.2), lineWidth: 1)
                                    )
                            )
                    }
                    .buttonStyle(.plain)
                }
                .padding(18)
                .background(Rectangle().fill(Color(hex: "#1E1440")))

                // Body
                VStack(spacing: 16) {
                    Text(PersonaContent.resolve(PersonaContent.skillDesc, id: skill.id, persona: appState.languagePersona, fallback: skill.desc))
                        .font(.pixelSystem(size: 10, weight: .medium, design: .monospaced))
                        .foregroundColor(Color(hex: "#C0B0E0"))
                        .lineSpacing(4)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    HStack(spacing: 10) {
                        metaChip(label: "DIFF", value: difficultyStars(skill.nodeType))
                        metaChip(label: "XP", value: "\(xpForNode(skill))")
                        metaChip(label: "COINS", value: "\(coinsForNode(skill))")
                    }

                    Button(action: {
                        withAnimation(.spring(response: 0.25)) {
                            showNodePopup = false
                        }
                        if let challenge = findChallenge(for: skill) {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                withAnimation(.easeInOut(duration: 0.25)) {
                                    selectedChallenge = challenge
                                }
                            }
                        }
                    }) {
                        Text("START \(skill.nodeType.rawValue.uppercased()) →")
                            .font(.pixelSystem(size: 12, weight: .bold, design: .monospaced))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(
                                LinearGradient(
                                    colors: [Color(hex: "#8B7BE8"), Color(hex: "#534AB7")],
                                    startPoint: .top, endPoint: .bottom
                                )
                            )
                            .cornerRadius(12)
                            .shadow(color: Color(hex: "#3A2E8A"), radius: 0, y: 4)
                    }
                    .buttonStyle(.plain)
                }
                .padding(18)
            }
            .frame(width: 400)
            .background(
                RoundedRectangle(cornerRadius: 18)
                    .fill(
                        LinearGradient(
                            colors: [Color(hex: "#1E1440"), Color(hex: "#140C24")],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 18)
                            .stroke(Color(hex: "#534AB7"), lineWidth: 3)
                    )
            )
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .shadow(color: Color(hex: "#534AB7").opacity(0.5), radius: 40)
            .transition(.scale(scale: 0.85).combined(with: .opacity))
        }
    }

    // MARK: - Progress Dots

    private var progressDots: some View {
        HStack(spacing: 12) {
            ForEach(Array(kingdoms.enumerated()), id: \.element.id) { index, kingdom in
                if index > 0 {
                    Rectangle()
                        .fill(Color(hex: "#534AB7").opacity(0.3))
                        .frame(width: 36, height: 3)
                }

                VStack(spacing: 6) {
                    Circle()
                        .fill(index == currentKingdom ? kingdom.accentColor : .clear)
                        .frame(width: 24, height: 24)
                        .overlay(
                            Circle()
                                .stroke(kingdom.accentColor, lineWidth: 2.5)
                        )
                        .shadow(color: index == currentKingdom ? kingdom.accentColor.opacity(0.7) : .clear, radius: index == currentKingdom ? 10 : 0)

                    Text(shortName(kingdom.name))
                        .font(.pixelSystem(size: 9, weight: .bold, design: .monospaced))
                        .foregroundColor(index == currentKingdom ? .white : Color(hex: "#A89BF2"))
                }
                .onTapGesture {
                    navigateToKingdom(index)
                }
            }
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(Color(hex: "#140C24").opacity(0.92))
                .overlay(
                    RoundedRectangle(cornerRadius: 24)
                        .stroke(Color(hex: "#534AB7").opacity(0.35), lineWidth: 2)
                )
        )
        .shadow(color: .black.opacity(0.3), radius: 12, y: 4)
    }

    // MARK: - Arrow Button

    private func arrowButton(systemName: String) -> some View {
        Image(systemName: systemName)
            .font(.pixelSystem(size: 18, weight: .medium))
            .foregroundColor(Color(hex: "#A89BF2"))
            .frame(width: 52, height: 52)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(hex: "#140C24").opacity(0.85))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color(hex: "#534AB7"), lineWidth: 2)
                    )
            )
    }

    // MARK: - Meta Chip

    private func metaChip(label: String, value: String) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.pixelSystem(size: 8, weight: .bold, design: .monospaced))
                .foregroundColor(Color(hex: "#A89BF2"))
            Text(value)
                .font(.pixelSystem(size: 8, weight: .bold, design: .monospaced))
                .foregroundColor(Color(hex: "#FFD700"))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(.white.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(.white.opacity(0.1), lineWidth: 1)
                )
        )
    }

    // MARK: - Navigation

    private func navigateKingdom(_ direction: Int) {
        let next = currentKingdom + direction
        guard next >= 0 && next < kingdoms.count else { return }
        withAnimation(.easeInOut(duration: 0.4)) {
            currentKingdom = next
        }
    }

    private func navigateToKingdom(_ index: Int) {
        guard index >= 0 && index < kingdoms.count else { return }
        withAnimation(.easeInOut(duration: 0.4)) {
            currentKingdom = index
        }
    }

    // MARK: - Helpers

    private enum NodeState {
        case completed, active, locked
    }

    private func nodeState(for skill: Skill) -> NodeState {
        if appState.completedLessons.contains(skill.id) || appState.completedChallenges.contains(skill.id) {
            return .completed
        }
        let tier = GameData.skillTiers.first { $0.skills.contains(where: { $0.id == skill.id }) }
        if let tier = tier {
            for s in tier.skills {
                let done = appState.completedLessons.contains(s.id) || appState.completedChallenges.contains(s.id)
                if !done {
                    return s.id == skill.id ? .active : .locked
                }
            }
        }
        return .completed
    }

    private func findActiveNodeIndex(skills: [Skill]) -> Int {
        for (i, skill) in skills.enumerated() {
            if nodeState(for: skill) == .active {
                return i
            }
        }
        return skills.count - 1
    }

    private func nodeBackground(state: NodeState, kingdom: KingdomData) -> Color {
        switch state {
        case .completed: return Color(hex: "#4CC864").opacity(0.75)
        case .active: return kingdom.accentColor.opacity(0.35)
        case .locked: return Color(hex: "#3C3250").opacity(0.5)
        }
    }

    private func nodeBorderColor(state: NodeState, kingdom: KingdomData) -> Color {
        switch state {
        case .completed: return Color(hex: "#6BCB77")
        case .active: return Color(hex: "#8B7BE8")
        case .locked: return Color(hex: "#645A82").opacity(0.4)
        }
    }

    private func typeBadgeText(_ type: SkillNodeType) -> String {
        switch type {
        case .lesson: return "LESSON"
        case .challenge: return "CHALLENGE"
        case .boss: return "BOSS"
        }
    }

    private func typeBadgeColor(_ type: SkillNodeType) -> Color {
        switch type {
        case .lesson: return Color(hex: "#534AB7")
        case .challenge: return Color(hex: "#D4960A")
        case .boss: return Color(hex: "#C03020")
        }
    }

    private func difficultyStars(_ type: SkillNodeType) -> String {
        switch type {
        case .lesson: return "★☆☆"
        case .challenge: return "★★☆"
        case .boss: return "★★★"
        }
    }

    private func xpForNode(_ skill: Skill) -> Int {
        switch skill.nodeType {
        case .lesson: return 10
        case .challenge: return 25
        case .boss: return 50
        }
    }

    private func coinsForNode(_ skill: Skill) -> Int {
        switch skill.nodeType {
        case .lesson: return 5
        case .challenge: return 10
        case .boss: return 25
        }
    }

    private func shortName(_ name: String) -> String {
        let words = name.split(separator: " ")
        return String(words.last ?? "")
    }

    private func findChallenge(for skill: Skill) -> Challenge? {
        GameData.challenges.first { $0.skillName == skill.name }
    }

    private func findSkillId(for skillName: String) -> String {
        for tier in GameData.skillTiers {
            if let skill = tier.skills.first(where: { $0.name == skillName }) {
                return skill.id
            }
        }
        return skillName.lowercased().replacingOccurrences(of: " ", with: "-")
    }
}

// MARK: - Full 6-Stage Challenge Overlay

struct ChallengeOverlayView: View {
    @EnvironmentObject var appState: AppState
    let challenge: Challenge
    let difficultyLevel: String
    let onComplete: (_ xpEarned: Int, _ attempt: Int) -> Void
    let onClose: () -> Void

    @State private var stage: Int = 0
    @State private var selectedTool: ChallengeTool? = nil
    @State private var submissionText: String = ""
    @State private var showSampleAnswer: Bool = false
    @State private var attempt: Int = 1
    @State private var results: ChallengeResults? = nil

    private let stageLabels = ["Challenge", "Pick Tool", "Guidelines", "Submit", "Review", "Result"]

    private var teacher: PetCharacter? { PetCharacter.all[challenge.teacher] }
    private var teacherColor: Color { teacher?.color ?? Color(hex: "#D89840") }
    private var xpMultiplier: Double {
        switch attempt { case 1: return 1.0; case 2: return 0.75; default: return 0.5 }
    }
    private var earnedXP: Int { Int(Double(challenge.xpReward) * xpMultiplier) }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 4) {
                ForEach(0..<6, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(i < stage ? Color(hex: "#8B7BE8") : (i == stage ? teacherColor : Color(hex: "#E0DDD6")))
                        .frame(height: 4)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)

            HStack {
                HStack(spacing: 4) {
                    Text("🎯").font(.pixelSystem(size: 10))
                    Text(stageLabels[stage].uppercased())
                        .font(.pixelSystem(size: 9, weight: .bold, design: .monospaced))
                        .foregroundColor(teacherColor)
                    if attempt > 1 {
                        Text("· Attempt \(attempt)")
                            .font(.pixelSystem(size: 9, weight: .medium, design: .monospaced))
                            .foregroundColor(Color(hex: "#A09B8E"))
                    }
                }
                Spacer()
                HStack(spacing: 8) {
                    Text("+\(earnedXP) XP")
                        .font(.pixelSystem(size: 9, weight: .bold, design: .monospaced))
                        .foregroundColor(Color(hex: "#D89840"))
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.pixelSystem(size: 12, weight: .medium))
                            .foregroundColor(Color(hex: "#B0A898"))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20).padding(.top, 10)

            VStack(spacing: 4) {
                Text(challenge.badge.icon).font(.pixelSystem(size: 32))
                if let t = teacher {
                    Text(t.name)
                        .font(.pixelSystem(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(teacherColor)
                }
            }.padding(.top, 8)

            ScrollView {
                VStack(spacing: 0) {
                    switch stage {
                    case 0: briefStage
                    case 1: pickToolStage
                    case 2: guidelinesStage
                    case 3: submitStage
                    case 4: reviewStage
                    case 5: resultStage
                    default: EmptyView()
                    }
                }
                .padding(.horizontal, 20).padding(.bottom, 20)
            }
        }
        .background(Color(hex: "#F7F5FC"))
    }

    // MARK: - Stage 0: Brief
    private var briefStage: some View {
        VStack(spacing: 14) {
            Text("\(challenge.skillName) Challenge").font(.pixelSystem(size: 18, weight: .bold)).multilineTextAlignment(.center)
            Text(difficultyBadge).font(.pixelSystem(size: 11, weight: .bold, design: .monospaced)).foregroundColor(difficultyColor)
                .padding(.horizontal, 14).padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 8).fill(difficultyColor.opacity(0.1)))
            VStack(alignment: .leading, spacing: 8) {
                Text("🎯 YOUR MISSION").font(.pixelSystem(size: 9, weight: .bold, design: .monospaced)).foregroundColor(teacherColor)
                Text(PersonaContent.resolve(PersonaContent.challengeBrief, id: challenge.id, persona: appState.languagePersona, fallback: challenge.brief)).font(.pixelSystem(size: 12)).foregroundColor(Color(hex: "#444444")).lineSpacing(4)
            }
            .padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 14).fill(Color(hex: "#F7F5FC")).overlay(RoundedRectangle(cornerRadius: 14).stroke(Color(hex: "#E0DBEF"), lineWidth: 1)))
            HStack(spacing: 8) {
                Text("\(challenge.xpReward) XP").font(.pixelSystem(size: 10, weight: .bold)).foregroundColor(Color(hex: "#B8860B"))
                    .padding(.horizontal, 10).padding(.vertical, 4).background(RoundedRectangle(cornerRadius: 8).fill(Color(hex: "#FFF8E8")))
                Text("\(challenge.badge.icon) \(challenge.badge.name)").font(.pixelSystem(size: 10, weight: .bold)).foregroundColor(Color(hex: "#2E7D32"))
                    .padding(.horizontal, 10).padding(.vertical, 4).background(RoundedRectangle(cornerRadius: 8).fill(Color(hex: "#EDEBF7")))
            }
            Button(action: { withAnimation { stage = 1 } }) {
                Text("Accept Challenge →").font(.pixelSystem(size: 13, weight: .bold)).foregroundColor(.white)
                    .frame(maxWidth: .infinity).padding(.vertical, 12).background(Color(hex: "#2D2B26")).cornerRadius(12)
            }.buttonStyle(.plain)
        }.padding(.top, 12)
    }

    // MARK: - Stage 1: Pick Tool
    private var pickToolStage: some View {
        VStack(spacing: 14) {
            Text("Pick Your Tool").font(.pixelSystem(size: 18, weight: .bold))
            Text("Which AI tool will you use for this challenge?").font(.pixelSystem(size: 11)).foregroundColor(Color(hex: "#888888"))
            ForEach(ChallengeTool.all) { tool in
                let isSelected = selectedTool?.id == tool.id
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8).fill(tool.color.opacity(0.1)).frame(width: 32, height: 32)
                        Text(tool.icon).font(.pixelSystem(size: 12, weight: .bold)).foregroundColor(tool.color)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(tool.name).font(.pixelSystem(size: 12, weight: .semibold)).foregroundColor(Color(hex: "#2D2B26"))
                            if tool.recommended {
                                Text("RECOMMENDED").font(.pixelSystem(size: 7, weight: .bold)).foregroundColor(.white)
                                    .padding(.horizontal, 6).padding(.vertical, 2).background(Color(hex: "#D97706")).cornerRadius(4)
                            }
                        }
                        Text(tool.desc).font(.pixelSystem(size: 10)).foregroundColor(Color(hex: "#888888"))
                    }
                    Spacer()
                    if isSelected { Image(systemName: "checkmark").font(.pixelSystem(size: 12, weight: .bold)).foregroundColor(tool.color) }
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 12).fill(isSelected ? tool.color.opacity(0.06) : Color.white)
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(isSelected ? tool.color.opacity(0.4) : Color(hex: "#E0DBEF"), lineWidth: isSelected ? 2 : 1)))
                .onTapGesture { withAnimation(.easeInOut(duration: 0.15)) { selectedTool = tool }; SoundManager.shared.playTap() }
            }
            Button(action: { withAnimation { stage = 2 } }) {
                Text("Continue →").font(.pixelSystem(size: 13, weight: .bold))
                    .foregroundColor(selectedTool != nil ? .white : Color(hex: "#B0A898"))
                    .frame(maxWidth: .infinity).padding(.vertical, 12)
                    .background(selectedTool != nil ? Color(hex: "#2D2B26") : Color(hex: "#E0DDD6")).cornerRadius(12)
            }.buttonStyle(.plain).disabled(selectedTool == nil)
        }.padding(.top, 12)
    }

    // MARK: - Stage 2: Guidelines
    private var guidelinesStage: some View {
        VStack(spacing: 14) {
            Text("How to Approach This").font(.pixelSystem(size: 18, weight: .bold))
            Text("\(teacher?.name ?? "Teacher") prepared building blocks to guide you:").font(.pixelSystem(size: 11)).foregroundColor(Color(hex: "#888888"))
            ForEach(Array(challenge.promptBlocks.enumerated()), id: \.offset) { i, block in
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) { Text(block.emoji).font(.pixelSystem(size: 16)); Text("Step \(i + 1): \(block.title)").font(.pixelSystem(size: 12, weight: .bold)).foregroundColor(Color(hex: "#2D2B26")) }
                    Text(block.hint).font(.pixelSystem(size: 11)).foregroundColor(Color(hex: "#555555")).padding(.leading, 28).lineSpacing(3)
                    Text(block.example).font(.pixelSystem(size: 10)).foregroundColor(Color(hex: "#999999")).italic().padding(.leading, 28)
                }
                .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color(hex: "#F7F5FC")).overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(hex: "#E0DBEF"), lineWidth: 1)))
            }
            HStack(spacing: 8) {
                Text("✍️").font(.pixelSystem(size: 14))
                Text("Use these steps as a guide, but write everything in your own words.").font(.pixelSystem(size: 10, weight: .medium)).foregroundColor(Color(hex: "#166534")).lineSpacing(3)
            }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color(hex: "#F0FDF4")).overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(hex: "#BBF7D0"), lineWidth: 1)))
            HStack(spacing: 8) {
                if let tool = selectedTool, let url = tool.url {
                    Link(destination: URL(string: url)!) {
                        Text("Open \(tool.name) ↗").font(.pixelSystem(size: 12, weight: .bold)).foregroundColor(.white)
                            .frame(maxWidth: .infinity).padding(.vertical, 12).background(tool.color).cornerRadius(12)
                    }
                }
                Button(action: { withAnimation { stage = 3 } }) {
                    Text("I'm Done → Submit").font(.pixelSystem(size: 12, weight: .bold)).foregroundColor(.white)
                        .frame(maxWidth: .infinity).padding(.vertical, 12).background(Color(hex: "#2D2B26")).cornerRadius(12)
                }.buttonStyle(.plain)
            }
        }.padding(.top, 12)
    }

    // MARK: - Stage 3: Submit
    private var submitStage: some View {
        VStack(spacing: 14) {
            Text("Submit Your Work").font(.pixelSystem(size: 18, weight: .bold))
            Text("Paste your work below. \(teacher?.name ?? "Teacher") will review it.").font(.pixelSystem(size: 11)).foregroundColor(Color(hex: "#888888"))
            if let sample = challenge.sampleAnswer {
                Button(action: { withAnimation { showSampleAnswer.toggle() } }) {
                    HStack(spacing: 8) {
                        Text("📝").font(.pixelSystem(size: 14))
                        Text("Stuck? See a sample answer").font(.pixelSystem(size: 11, weight: .semibold)).foregroundColor(showSampleAnswer ? teacherColor : Color(hex: "#888888"))
                        Spacer()
                        Image(systemName: "chevron.down").font(.pixelSystem(size: 10)).foregroundColor(Color(hex: "#B0A898")).rotationEffect(.degrees(showSampleAnswer ? 180 : 0))
                    }.padding(12)
                    .background(RoundedRectangle(cornerRadius: 12).fill(showSampleAnswer ? teacherColor.opacity(0.06) : Color.white)
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(showSampleAnswer ? teacherColor.opacity(0.3) : Color(hex: "#E0DBEF"), lineWidth: 1.5)))
                }.buttonStyle(.plain)
                if showSampleAnswer {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 6) {
                            Image(systemName: "lightbulb.fill").font(.pixelSystem(size: 10)).foregroundColor(teacherColor)
                            Text("SAMPLE ANSWER").font(.pixelSystem(size: 8, weight: .bold, design: .monospaced)).foregroundColor(teacherColor)
                        }
                        Text(sample.text).font(.pixelSystem(size: 10, design: .monospaced)).foregroundColor(Color(hex: "#555555")).lineSpacing(3)
                    }
                    .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 12).fill(teacherColor.opacity(0.04)).overlay(RoundedRectangle(cornerRadius: 12).stroke(teacherColor.opacity(0.15), lineWidth: 1)))
                }
            }
            TextEditor(text: $submissionText)
                .font(.pixelSystem(size: 11, design: .monospaced))
                .frame(minHeight: 120)
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 12).stroke(Color(hex: "#E0DBEF"), lineWidth: 1))
            Button(action: {
                withAnimation { stage = 4 }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    results = ChallengeResults(
                        checkpoints: challenge.checkpoints.map { cp in
                            ChallengeResults.CheckResult(
                                name: cp.label,
                                passed: cp.keywords.contains(where: { submissionText.lowercased().contains($0.lowercased()) }),
                                feedback: cp.keywords.contains(where: { submissionText.lowercased().contains($0.lowercased()) }) ? "Great job including \(cp.label.lowercased())!" : "Try to include \(cp.label.lowercased()) in your answer."
                            )
                        }
                    )
                    withAnimation { stage = 5 }
                }
            }) {
                Text("Submit for Review →").font(.pixelSystem(size: 13, weight: .bold))
                    .foregroundColor(!submissionText.isEmpty ? .white : Color(hex: "#B0A898"))
                    .frame(maxWidth: .infinity).padding(.vertical, 12)
                    .background(!submissionText.isEmpty ? Color(hex: "#2D2B26") : Color(hex: "#E0DDD6")).cornerRadius(12)
            }.buttonStyle(.plain).disabled(submissionText.isEmpty)
        }.padding(.top, 12)
    }

    // MARK: - Stage 4: Review (loading)
    private var reviewStage: some View {
        VStack(spacing: 20) {
            Text("Reviewing...").font(.pixelSystem(size: 18, weight: .bold))
            if let t = teacher {
                Image(t.imageName).resizable().interpolation(.none).scaledToFit().frame(width: 64, height: 64)
            }
            ProgressView().scaleEffect(1.2)
            Text("\(teacher?.name ?? "Teacher") is reviewing your work...").font(.pixelSystem(size: 11)).foregroundColor(Color(hex: "#888888"))
        }.padding(.top, 40)
    }

    // MARK: - Stage 5: Result
    private var resultStage: some View {
        VStack(spacing: 14) {
            if let results = results {
                let passed = results.checkpoints.filter(\.passed).count
                let total = results.checkpoints.count
                let allPassed = passed == total
                Text(allPassed ? "Challenge Complete!" : "Almost There!").font(.pixelSystem(size: 18, weight: .bold))
                Text("\(passed)/\(total) checkpoints passed").font(.pixelSystem(size: 12)).foregroundColor(Color(hex: "#888888"))
                ForEach(Array(results.checkpoints.enumerated()), id: \.offset) { _, check in
                    HStack(spacing: 8) {
                        Image(systemName: check.passed ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundColor(check.passed ? Color(hex: "#4CC864") : Color(hex: "#E05050"))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(check.name).font(.pixelSystem(size: 11, weight: .semibold))
                            Text(check.feedback).font(.pixelSystem(size: 10)).foregroundColor(Color(hex: "#888888"))
                        }
                        Spacer()
                    }.padding(10)
                    .background(RoundedRectangle(cornerRadius: 10).fill((check.passed ? Color(hex: "#4CC864") : Color(hex: "#E05050")).opacity(0.06)))
                }
                if allPassed {
                    HStack(spacing: 8) {
                        Text("🎉").font(.pixelSystem(size: 20))
                        Text("+\(earnedXP) XP earned!").font(.pixelSystem(size: 14, weight: .bold)).foregroundColor(Color(hex: "#B8860B"))
                    }.padding(14)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color(hex: "#FFF8E8")).overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(hex: "#F0E0B0"), lineWidth: 1)))
                    Button(action: { onComplete(earnedXP, attempt) }) {
                        Text("Collect Reward →").font(.pixelSystem(size: 13, weight: .bold)).foregroundColor(.white)
                            .frame(maxWidth: .infinity).padding(.vertical, 12).background(Color(hex: "#4CC864")).cornerRadius(12)
                    }.buttonStyle(.plain)
                } else {
                    Button(action: { withAnimation { stage = 3; attempt += 1 } }) {
                        Text("Try Again →").font(.pixelSystem(size: 13, weight: .bold)).foregroundColor(.white)
                            .frame(maxWidth: .infinity).padding(.vertical, 12).background(Color(hex: "#D89840")).cornerRadius(12)
                    }.buttonStyle(.plain)
                }
            }
        }.padding(.top, 12)
    }

    // MARK: - Difficulty helpers
    private var difficultyBadge: String {
        switch difficultyLevel { case "beginner": return "⬡ BEGINNER"; case "intermediate": return "⬡⬡ INTERMEDIATE"; default: return "⬡⬡⬡ ADVANCED" }
    }
    private var difficultyColor: Color {
        switch difficultyLevel { case "beginner": return Color(hex: "#2E7D32"); case "intermediate": return Color(hex: "#D97706"); default: return Color(hex: "#C62828") }
    }
}

// MARK: - Challenge Results Model

struct ChallengeResults {
    struct CheckResult {
        let name: String
        let passed: Bool
        let feedback: String
    }
    let checkpoints: [CheckResult]
}

// MARK: - Confetti View

struct ConfettiView: View {
    @State private var confetti: [(CGFloat, CGFloat, Color, Double)] = (0..<40).map { _ in
        (CGFloat.random(in: 0...1), CGFloat.random(in: -0.2...0.0),
         [Color.red, .blue, .green, .yellow, .purple, .orange, .pink, .mint].randomElement()!,
         Double.random(in: 0.5...1.0))
    }
    @State private var animate = false

    var body: some View {
        GeometryReader { geo in
            ZStack {
                ForEach(0..<confetti.count, id: \.self) { i in
                    let (x, startY, color, opacity) = confetti[i]
                    RoundedRectangle(cornerRadius: 1)
                        .fill(color.opacity(opacity))
                        .frame(width: CGFloat.random(in: 4...8), height: CGFloat.random(in: 8...14))
                        .rotationEffect(.degrees(animate ? Double.random(in: 0...360) : 0))
                        .position(
                            x: geo.size.width * x,
                            y: animate ? geo.size.height * 1.2 : geo.size.height * startY
                        )
                }
            }
        }
        .onAppear {
            withAnimation(.easeIn(duration: 2.5)) { animate = true }
        }
        .allowsHitTesting(false)
    }
}

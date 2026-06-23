import SwiftUI

/// A single challenge node on the kingdom path.
/// Three states: completed (green check), active/next (pulsing, tappable), locked (dimmed).
struct ChallengeNodeView: View {
    let skill: Skill
    let index: Int
    let isCompleted: Bool
    let isNext: Bool
    let isLocked: Bool
    let tierColor: Color
    let teacher: String?
    let onStart: () -> Void

    @State private var isPulsing = false

    private var teacherChar: PetCharacter? {
        if let t = teacher { return PetCharacter.all[t] }
        return nil
    }

    // MARK: - Extracted color helpers (prevents type-checker timeout)

    private var challengeLabelColor: Color {
        if isCompleted { return Color(hex: "#6BCB77") }
        if isNext { return tierColor }
        return Color.white.opacity(0.3)
    }

    private var cardFillColor: Color {
        if isNext { return Color.white.opacity(0.12) }
        if isCompleted { return Color.white.opacity(0.06) }
        return Color.white.opacity(0.03)
    }

    private var cardStrokeColor: Color {
        if isNext { return tierColor.opacity(0.5) }
        if isCompleted { return Color(hex: "#6BCB77").opacity(0.3) }
        return Color.white.opacity(0.06)
    }

    private var cardStrokeWidth: CGFloat {
        isNext ? 2 : 1
    }

    var body: some View {
        Button(action: {
            if isNext {
                SoundManager.shared.playTap()
                onStart()
            }
        }) {
            HStack(spacing: 14) {
                // Node circle
                nodeCircle

                // Info card
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(nodeTypeLabel)
                            .font(.pixelSystem(size: 8, weight: .bold, design: .monospaced))
                            .foregroundColor(challengeLabelColor)

                        if let lesson = LessonLibrary.all[skill.id] {
                            Text(lesson.duration)
                                .font(.pixelSystem(size: 9, design: .monospaced))
                                .foregroundColor(.white.opacity(0.4))
                        }

                        if isCompleted {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.pixelSystem(size: 10))
                                .foregroundColor(Color(hex: "#6BCB77"))
                        }
                    }

                    Text(skill.name)
                        .font(.pixelSystem(size: 15, weight: .bold))
                        .foregroundColor(isLocked ? .white.opacity(0.3) : .white)

                    Text(skill.desc)
                        .font(.pixelSystem(size: 11))
                        .foregroundColor(.white.opacity(isLocked ? 0.2 : 0.6))
                        .lineLimit(2)

                    // Teacher row
                    if let t = teacherChar, !isLocked {
                        HStack(spacing: 6) {
                            CharacterImage(t.id, size: 20)
                                .charIdle(t.id)
                            Text("with \(t.name)")
                                .font(.pixelSystem(size: 10, weight: .medium))
                                .foregroundColor(t.color.opacity(0.8))
                        }
                        .padding(.top, 2)
                    }

                    // Start button for active node
                    if isNext {
                        HStack(spacing: 6) {
                            Text("Enter Challenge")
                                .font(.pixelSystem(size: 12, weight: .bold))
                            Image(systemName: "arrow.right")
                                .font(.pixelSystem(size: 10, weight: .bold))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(
                            Capsule()
                                .fill(tierColor)
                                .shadow(color: tierColor.opacity(0.4), radius: 6, y: 2)
                        )
                        .padding(.top, 4)
                    }
                }

                Spacer()
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(cardFillColor)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(cardStrokeColor, lineWidth: cardStrokeWidth)
                    )
            )
        }
        .buttonStyle(.plain)
        .disabled(isLocked)
        .opacity(isLocked ? 0.5 : 1.0)
        .scaleEffect(isPulsing && isNext ? 1.02 : 1.0)
        .onAppear {
            if isNext {
                withAnimation(
                    .easeInOut(duration: 1.5)
                    .repeatForever(autoreverses: true)
                ) {
                    isPulsing = true
                }
            }
        }
    }

    // MARK: - Node Circle

    /// Node size varies by type: boss > challenge > lesson (matching prototype logic)
    private var nodeSize: CGFloat {
        switch skill.nodeType {
        case .boss: return 54
        case .challenge: return 48
        case .lesson: return 44
        }
    }

    private var nodeIcon: String {
        if isCompleted { return "checkmark" }
        switch skill.nodeType {
        case .boss: return isLocked ? "lock.fill" : "flame.fill"
        case .challenge: return isLocked ? "lock.fill" : "bolt.fill"
        case .lesson: return isLocked ? "lock.fill" : "play.fill"
        }
    }

    private var nodeTypeLabel: String {
        switch skill.nodeType {
        case .boss: return "BOSS"
        case .challenge: return "CHALLENGE \(index)"
        case .lesson: return "LESSON \(index)"
        }
    }

    private var nodeCircle: some View {
        ZStack {
            // Outer glow for active
            if isNext {
                Circle()
                    .fill(tierColor.opacity(0.2))
                    .frame(width: nodeSize + 8, height: nodeSize + 8)
                    .scaleEffect(isPulsing ? 1.15 : 1.0)
            }

            // Boss: extra ring
            if skill.nodeType == .boss && !isLocked {
                Circle()
                    .stroke(
                        isCompleted ? Color(hex: "#FFD700").opacity(0.5) : tierColor.opacity(0.3),
                        lineWidth: 2
                    )
                    .frame(width: nodeSize + 4, height: nodeSize + 4)
            }

            Circle()
                .fill(
                    isCompleted ?
                        LinearGradient(colors: [Color(hex: "#6BCB77"), Color(hex: "#4CAF50")], startPoint: .top, endPoint: .bottom) :
                    isNext ?
                        LinearGradient(colors: [tierColor, tierColor.opacity(0.8)], startPoint: .top, endPoint: .bottom) :
                        LinearGradient(colors: [Color.white.opacity(0.1), Color.white.opacity(0.05)], startPoint: .top, endPoint: .bottom)
                )
                .frame(width: nodeSize, height: nodeSize)
                .overlay(
                    Circle()
                        .stroke(
                            isCompleted ? Color(hex: "#6BCB77").opacity(0.5) :
                            isNext ? tierColor.opacity(0.6) :
                            Color.white.opacity(0.1),
                            lineWidth: 2
                        )
                )

            // Icon inside circle
            Image(systemName: nodeIcon)
                .font(.pixelSystem(size: skill.nodeType == .boss ? 20 : 16, weight: .bold))
                .foregroundColor(isLocked ? .white.opacity(0.3) : .white)
        }
    }
}

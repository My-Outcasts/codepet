// codepet/Demo/MockFlowCaptionBar.swift
#if DEBUG
import SwiftUI

/// The walkthrough's transport and its caption — the prototype's `#captions` box
/// and its Play / Reset / CC / pace row, over the real app.
///
/// Only ever on screen under `-CODEPET_MOCK_AUTOPLAY YES`, and the whole file is
/// `#if DEBUG`, so a release build cannot render it even by accident.
struct MockFlowCaptionBar: View {
    @ObservedObject var player: MockFlowPlayer

    var body: some View {
        VStack(spacing: 8) {
            if let caption = player.caption {
                Text(caption)
                    .font(CodepetTheme.inter(CodepetType.body))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 620)
                    .padding(.horizontal, 16).padding(.vertical, 11)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.black.opacity(0.82)))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(CodepetTheme.accentPurple.opacity(0.45), lineWidth: 1))
                    .transition(.opacity)
            }
            chapters
            transport
        }
        .padding(.bottom, 16)
        .animation(.easeOut(duration: 0.18), value: player.caption)
    }

    /// Chapter jumps — the prototype has had these from the start, and their absence
    /// here is why the app's tour had to stay under a minute: a story you can only
    /// watch linearly must be short enough to sit through, while one you can enter
    /// anywhere can afford to be complete. The player already had `jump(toChapter:)`;
    /// nothing exposed it.
    private var chapters: some View {
        let current = player.currentChapter
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 5) {
                ForEach(MockFlowScript.chapters, id: \.self) { chapter in
                    Button { player.jump(toChapter: chapter) } label: {
                        Text(chapter)
                            .font(CodepetTheme.inter(CodepetType.footnote,
                                                     weight: chapter == current ? .semibold : .regular))
                            .foregroundColor(chapter == current
                                             ? CodepetTheme.accentPurple : .white.opacity(0.7))
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(Capsule().fill(chapter == current
                                                       ? CodepetTheme.accentPurple.opacity(0.18)
                                                       : Color.white.opacity(0.06)))
                            .contentShape(Capsule())
                            .hoverAffordance(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
        }
        .frame(maxWidth: 720)
    }

    private var transport: some View {
        HStack(spacing: 7) {
            button(player.isPlaying ? "❚❚ Pause" : "▶ Play") { player.toggle() }
            button("Reset") { player.restart() }
            button(player.captionsOn ? "CC on" : "CC off") {
                player.captionsOn.toggle()
            }
            // The prototype's Slow / Steady / Brisk. Higher pace = longer beats,
            // so "Slow" is the larger multiplier.
            ForEach([("Slow", 1.5), ("Steady", 1.0), ("Brisk", 0.6)], id: \.0) { name, value in
                button(name, on: player.pace == value) { player.pace = value }
            }
            Text("\(min(player.index + 1, player.beats.count))/\(player.beats.count)")
                .font(CodepetTheme.inter(CodepetType.footnote))
                .foregroundColor(CodepetTokens.faint)
                .padding(.leading, 4)
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(Capsule().fill(Color.black.opacity(0.7)))
        .overlay(Capsule().stroke(CodepetTokens.cardEdge))
    }

    private func button(_ label: String, on: Bool = false,
                        action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(CodepetTheme.inter(CodepetType.subheadline, weight: on ? .semibold : .regular))
                .foregroundColor(on ? CodepetTheme.accentPurple : .white.opacity(0.85))
                .padding(.horizontal, 9).padding(.vertical, 5)
                .background(Capsule().fill(on ? CodepetTheme.accentPurple.opacity(0.18) : .clear))
                .contentShape(Capsule())
                .hoverAffordance(Capsule())
        }
        .buttonStyle(.plain)
    }
}
#endif

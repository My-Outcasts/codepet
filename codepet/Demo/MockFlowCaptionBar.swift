// codepet/Demo/MockFlowCaptionBar.swift
#if DEBUG
import SwiftUI

/// The walkthrough's transport and its caption — the prototype's `#captions` box
/// and its Play / Reset / CC / pace row, over the real app.
///
/// On screen whenever prototype mode is on — the switch in the rail, or any of the
/// three launch arguments. The whole file is `#if DEBUG`, so a release build cannot
/// render it even by accident.
struct MockFlowCaptionBar: View {
    @ObservedObject var player: MockFlowPlayer

    /// A DOCKED band, not an overlay.
    ///
    /// It was `.overlay(alignment: .bottom)`, on the reasoning that the walkthrough
    /// should sit over the pane so no beat could be pushed off screen by the content
    /// it narrates. True, and it traded that for something worse: an overlay does not
    /// participate in layout, so the chapter chips and the transport sat directly on
    /// top of the composer — covering the placeholder, the `+` button and the
    /// disclaimer, and swallowing clicks meant for them. A tour of a product whose
    /// central control you cannot see is not showing the product.
    ///
    /// Mounted through `safeAreaInset`, so the band RESERVES its height and the
    /// composer moves up by exactly that much. Nothing is covered and nothing is
    /// pushed off screen, which is what the overlay was reaching for.
    var body: some View {
        VStack(spacing: 8) {
            caption
            chapters
            transport
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 10)
        .padding(.bottom, 12)
        // Opaque: a reserved band with a transparent ground would show the window
        // behind it rather than the app.
        .background(CodepetTheme.surface)
        .overlay(alignment: .top) {
            Rectangle().fill(CodepetTokens.cardEdge).frame(height: 1)
        }
        .animation(.easeOut(duration: 0.18), value: player.caption)
    }

    /// The caption slot exists only when there is a caption.
    ///
    /// Held open unconditionally it measured 153pt of reserved band, most of it an
    /// empty box — charged against the conversation the whole time the mode is on and
    /// the tour is not running, which is most of the time while building. Keyed on
    /// the caption itself rather than on `isPlaying`, so turning CC off reclaims the
    /// space too: the player sets `caption` to nil when captions are off, so the two
    /// agree without a second condition to keep in sync.
    ///
    /// It still carries a floor, which is the part that matters during playback — a
    /// slot that resized to each beat's text would walk the composer up and down
    /// under the founder's cursor for the length of the tour. One shift when Play is
    /// pressed, none after.
    @ViewBuilder private var caption: some View {
        if let text = player.caption { captionBox(text) }
    }

    private func captionBox(_ text: String) -> some View {
        Text(text)
            .font(CodepetTheme.inter(CodepetType.body))
            .foregroundColor(.white)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: 620, minHeight: 34, alignment: .center)
            .padding(.horizontal, 16).padding(.vertical, 11)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.black.opacity(0.82)))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(CodepetTheme.accentPurple.opacity(0.45), lineWidth: 1))
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

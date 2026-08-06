// codepet/Views/Shell/HoverTooltip.swift
import SwiftUI

/// A hover label that can name its own keyboard shortcut — GitHub's pattern, which the founder
/// gave as the reference (Aug 6): a small dark plate under the control, the action in words, and
/// the keys that do the same thing sitting beside it as chips.
///
/// Why not `.help()`: the system tooltip is plain text in a system plate, so it cannot show a
/// shortcut as a chip, and it waits out AppKit's own delay. Teaching the shortcut is the point
/// here — a control whose only label is an icon or a wordmark has nowhere else to say it.
///
/// The plate draws OUTSIDE the control's bounds, so any ancestor that paints after the tooltip's
/// owner will cover it. Callers put the owner on a raised `zIndex` (see `AppShellView`).
struct HoverTooltip: ViewModifier {
    let label: String
    /// Shortcut chips, already formatted for display ("⇧⌘H"). Empty → label only.
    let keys: [String]
    /// Where the plate hangs relative to the control.
    var edge: Edge = .bottom

    @State private var hovering = false
    @State private var shown = false
    @State private var reveal: Task<Void, Never>?

    /// Long enough that crossing the control on the way somewhere else stays quiet, short enough
    /// that a deliberate hover feels answered. AppKit's own tooltip delay is ~1s, which reads as
    /// broken when you are hovering precisely to learn what something does.
    private static let delay: Duration = .milliseconds(350)

    func body(content: Content) -> some View {
        content
            .onHover { inside in
                hovering = inside
                reveal?.cancel()
                guard inside else { shown = false; return }
                reveal = Task { @MainActor in
                    try? await Task.sleep(for: Self.delay)
                    guard !Task.isCancelled, hovering else { return }
                    withAnimation(.easeOut(duration: 0.12)) { shown = true }
                }
            }
            .onDisappear { reveal?.cancel(); shown = false }
            .overlay(alignment: edge == .bottom ? .bottomLeading : .topLeading) {
                if shown {
                    plate
                        .fixedSize()
                        .alignmentGuide(edge == .bottom ? .bottom : .top) { _ in
                            edge == .bottom ? -6 : 6
                        }
                        .transition(.opacity)
                        .allowsHitTesting(false)   // never steal the hover that opened it
                }
            }
    }

    private var plate: some View {
        HStack(spacing: 8) {
            Text(label)
                .font(CodepetTheme.inter(11.5, weight: .medium))
                .foregroundColor(CodepetTheme.primaryText)
            ForEach(keys, id: \.self) { key in
                Text(key)
                    .font(CodepetTheme.inter(10.5, weight: .semibold))
                    .foregroundColor(CodepetTheme.mutedText)
                    .padding(.horizontal, 5).padding(.vertical, 1.5)
                    .background(RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(CodepetTokens.faint.opacity(0.5)))
                    .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .stroke(CodepetTheme.hairline, lineWidth: 1))
            }
        }
        .padding(.horizontal, 9).padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 7, style: .continuous)
            .fill(CodepetTokens.cardRaised))
        .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous)
            .stroke(CodepetTheme.hairline, lineWidth: 1))
        .shadow(color: .black.opacity(0.35), radius: 8, y: 3)
    }
}

extension View {
    /// Name what a control does on hover, and the keys that do it too.
    func hoverTooltip(_ label: String, keys: [String] = [], edge: Edge = .bottom) -> some View {
        modifier(HoverTooltip(label: label, keys: keys, edge: edge))
    }
}

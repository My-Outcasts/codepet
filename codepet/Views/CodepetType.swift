// codepet/Views/CodepetType.swift
import AppKit
import CoreGraphics

/// The type scale, aligned to macOS's own text styles.
///
/// **Why this exists.** Codepet's type was ported from the web app's px values —
/// `CodepetTheme.title()` is 28, `sectionName()` 25, `cardTitle()` 14 — and every
/// surface since has hand-picked from the gaps between them. The two-mode shell
/// alone reached THIRTEEN distinct sizes (9, 10, 10.5, 11, 11.5, 12, 12.5, 13,
/// 13.5, 14, 14.5, 16.5, 22) and the app 24. None of them is wrong on its own;
/// together they are not a scale, and half-point steps like 10.5 next to 11 are
/// differences the eye reads as sloppiness rather than hierarchy.
///
/// **The values are not invented.** They are what `NSFont.preferredFont(forTextStyle:)`
/// actually returns on this OS, read at runtime rather than remembered:
///
///     largeTitle 26 · title1 22 · title2 17 · title3 15
///     headline 13 · body 13 · callout 12 · subheadline 11 · footnote 10
///     caption1 10 · caption2 10
///     systemFontSize 13 · smallSystemFontSize 11 · labelFontSize 10
///
/// Two consequences worth stating, because both were being broken:
///
/// - **Nothing goes below 10.** macOS has no text style smaller than `footnote`;
///   10 is `labelFontSize`, the floor for text a user is expected to read. A 9pt
///   badge is below every style the system defines.
/// - **A standard control label is 13**, a small one 11, a mini one 9. Button and
///   sidebar-row text belongs on those, not between them.
///
/// `CodepetTypeTests` asserts each value against the live AppKit metric, so a
/// future hand-tuned number cannot quietly drift off the system scale.
enum CodepetType {
    /// 22 — `title1`. The dock hero's greeting.
    static let title1: CGFloat = 22
    /// 17 — `title2`. The pane hero's question: the largest thing in the pane.
    static let title2: CGFloat = 17
    /// 15 — `title3`. A pane title, the beacon card's work item, the composer field.
    static let title3: CGFloat = 15
    /// 13 — `body` and `headline`, and `systemFontSize`. Prose, sidebar rows, and
    /// standard control labels. Semibold turns body into headline.
    static let body: CGFloat = 13
    /// 12 — `callout`. Supporting detail under a title.
    static let callout: CGFloat = 12
    /// 11 — `subheadline`, and `smallSystemFontSize`. Chips and small controls.
    static let subheadline: CGFloat = 11
    /// 10 — `footnote`/`caption`, and `labelFontSize`. Eyebrows, badges, legal
    /// lines. **The floor.**
    static let footnote: CGFloat = 10

    /// Every size on the scale, largest first — for the tests and for anyone
    /// checking whether a value they want already exists.
    static let all: [CGFloat] = [title1, title2, title3, body, callout, subheadline, footnote]
}

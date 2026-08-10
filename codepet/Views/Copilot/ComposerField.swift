// codepet/Views/Copilot/ComposerField.swift
import SwiftUI

/// How tall a chat input may get before it scrolls instead of growing.
///
/// Founder, Aug 10, with a screenshot of a pasted email: the composer was a vertical `TextField`
/// capped at `lineLimit(1...6)`, so past six lines the rest of the message was still in the draft
/// but had no way to be seen — no scrollbar, no wheel, and the caret walking off the bottom edge.
/// A cap without a scroll surface is a truncation.
///
/// The caps themselves are deliberately unchanged. Both composers sit above the content they
/// belong to, and letting either grow further would eat that content to solve a problem
/// scrolling solves without taking a single point.
enum ComposerMetrics {
    /// ~6 lines of Inter 15 — the height the chat composer's old `lineLimit(1...6)` settled at.
    static let maxTextHeight: CGFloat = 132
    /// ~8 lines of the 12pt pixel font — the reflection panel's old `lineLimit(1...8)`.
    static let reflectionMaxTextHeight: CGFloat = 120
    /// Shown before the first measurement lands, so a field never flashes at zero height.
    static let minTextHeight: CGFloat = 21

    /// How tall the field should be for content of the measured height.
    ///
    /// Pure so it can be tested: these views cannot be screenshotted from here, and the two ways
    /// this goes wrong are both silent — an unmeasured first frame collapsing the field to
    /// nothing, and a long paste growing it until it swallows what is above it.
    static func fieldHeight(forContent contentHeight: CGFloat,
                            cap: CGFloat = maxTextHeight) -> CGFloat {
        min(max(contentHeight, minTextHeight), cap)
    }

    /// Whether the content is taller than the field can show — the scrollbar, the bounce and
    /// the caret-following all key off this, and each is noise when it is false.
    static func scrolls(contentHeight: CGFloat, cap: CGFloat = maxTextHeight) -> Bool {
        contentHeight > cap
    }
}

private struct ComposerTextHeight: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// A `TextField` that grows with its content and then scrolls.
///
/// It stays a `TextField` rather than becoming a `TextEditor`: the placeholder, `onSubmit`, and
/// the focus binding are all free here and would each have to be rebuilt by hand there. The
/// field is given unbounded lines so it always reports its TRUE height, and the cap is applied
/// to the `ScrollView` around it — which is what supplies the wheel, the scrollbar, and the
/// ability to read back what was pasted.
///
/// Shared by the chat composer and the reflection panel, which had the same defect with
/// different styling. Padding and background belong OUTSIDE this view: put them inside the
/// scroll surface and they scroll away with the text.
struct ComposerField: View {
    let placeholder: String
    @Binding var text: String
    var focus: FocusState<Bool>.Binding
    var font: Font = CodepetTheme.inter(15)
    var foreground: Color = CodepetTheme.primaryText
    var cap: CGFloat = ComposerMetrics.maxTextHeight
    var onSend: () -> Void

    @State private var contentHeight: CGFloat = ComposerMetrics.minTextHeight
    private let fieldID = "composer-field"

    private var overflows: Bool {
        ComposerMetrics.scrolls(contentHeight: contentHeight, cap: cap)
    }

    var body: some View {
        // The width is measured OUTSIDE the scroll view and pinned onto the field inside it.
        //
        // Founder, Aug 11: after the scroll surface landed, the text began wrapping about
        // two-thirds of the way across the card, leaving a wide empty gutter beside prose that
        // was already wrapping — while the chip row below still ran the full width.
        //
        // A ScrollView proposes an UNSPECIFIED width to its content, and against a nil
        // proposal `.frame(maxWidth: .infinity)` resolves to the content's IDEAL size — so the
        // obvious fix is a no-op here, which is exactly what happened on the first attempt.
        // `.frame(width:)` is unconditional, so the field wraps where the column ends.
        //
        // Measured rather than assumed: rendered offscreen with ImageRenderer, a bare
        // TextField inks to x=399 of a 400pt column at every line limit, so the field itself
        // was never the problem — and ImageRenderer draws nothing inside a ScrollView, which
        // is why this had to be reasoned to rather than seen.
        GeometryReader { outer in
            ScrollViewReader { proxy in
                ScrollView(.vertical) {
                    TextField(placeholder, text: $text, axis: .vertical)
                        .textFieldStyle(.plain)
                        .font(font)
                        .foregroundColor(foreground)
                        // Unbounded on purpose: the ScrollView owns the cap now. Leaving a line
                        // limit here would clip the content INSIDE the scroll view, so
                        // scrolling would reveal nothing.
                        .lineLimit(nil)
                        .frame(width: max(outer.size.width, 1), alignment: .leading)
                        .focused(focus)
                        .onSubmit(onSend)
                        .id(fieldID)
                        .background(
                            GeometryReader { geo in
                                Color.clear.preference(key: ComposerTextHeight.self,
                                                       value: geo.size.height)
                            }
                        )
                }
                // No rubber-banding while the draft is short — a one-line composer that
                // bounces reads as broken.
                .scrollBounceBehavior(.basedOnSize)
                .scrollIndicators(overflows ? .automatic : .never)
                .onPreferenceChange(ComposerTextHeight.self) { contentHeight = $0 }
                .onChange(of: text) { old, new in
                    // Follow the caret while TYPING, but leave a scroll position alone
                    // otherwise — pasting a long message and reading back up through it is the
                    // whole point, and yanking to the bottom on every keystroke would fight it.
                    guard overflows, new.count > old.count else { return }
                    proxy.scrollTo(fieldID, anchor: .bottom)
                }
            }
        }
        // The GeometryReader is greedy, so the cap lives out here on the whole field.
        .frame(height: ComposerMetrics.fieldHeight(forContent: contentHeight, cap: cap))
    }
}

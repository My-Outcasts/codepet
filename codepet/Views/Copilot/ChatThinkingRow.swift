import SwiftUI

/// The streaming/producing state: a label that names WHO is working and on what
/// (via ChatThinkingLabel), with a subtle light sweep through the text.
///
/// **No orb.** It was a decorative circle that said "something is happening" while the
/// label said the same thing in words — and on a product built around eight departments
/// each having their own voice, the one thing neither of them said was WHICH pet. Founder
/// call, 7 Sep: drop the icon, name the pet. Consistent with the project's standing rule
/// that only functional icons earn their place.
/// Replaces the old static typingRow/producingRow. Reduce Motion → orb static +
/// no sweep. Dock-sized: orb ≤ 22pt, label truncates to one line at the 380pt
/// dock width instead of wrapping.
struct ChatThinkingRow: View {
    /// A real in-flight title, or nil for a plain chat turn (→ "Working on it…").
    var taskTitle: String? = nil
    /// The specialist working (a department handoff); nil → the global companion.
    var companionId: String? = nil
    /// A tool running RIGHT NOW ("Luna is reading web.murror.app…"). Non-rotating, same as
    /// `taskTitle` — see `ChatThinkingLabel`'s doc comment for the precedence between the
    /// two. Only ever non-nil on the local sidecar path; the cloud transport emits no
    /// `tool` frame, so this stays nil there (a known parity gap, not this row's problem).
    var activity: ChatToolActivity? = nil

    @Environment(\.uiLanguage) private var lang
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Resolved from `companionId` rather than passed in, so a caller cannot name one pet
    /// while the avatar-less row is attributed to another. Unknown id → nil → the label falls
    /// back to the unnamed copy rather than inventing a specialist.
    private var petName: String? { PetCharacter.all[companionId ?? ""]?.name }

    /// The phrase this appearance shows, rolled ONCE.
    ///
    /// `@State` with a rolled initial value, rather than something computed in `body`:
    /// `body` re-runs on every frame of the shimmer (it is a `TimelineView`), and a phrase
    /// that changed 60 times a second would be far worse than the flat string it replaces.
    /// SwiftUI keeps the first storage for a given identity and discards later structs'
    /// initial values, so extra initialisations cannot change what is on screen — and
    /// `lastShown` is written in `.onAppear` (once per appearance) rather than here, so the
    /// no-repeat rule is measured against what was actually displayed.
    ///
    /// One roll covers both title-less cases: if a department handoff lands mid-reply the
    /// row switches from the unnamed phrase to the pet-named one at the SAME index, so the
    /// wording keeps its register instead of jumping to an unrelated line.
    @State private var variant = ChatThinkingLabel.rolled()

    private var label: String {
        ChatThinkingLabel.text(petName: petName, taskTitle: taskTitle, activity: activity,
                               language: lang, variant: variant)
    }

    var body: some View {
        HStack(spacing: 10) {
            shimmerLabel
            Spacer(minLength: 24)
        }
        .onAppear { ChatThinkingLabel.lastShown = variant }
    }

    @ViewBuilder private var shimmerLabel: some View {
        let base = Text(label)
            .font(CodepetTheme.inter(13))
            .foregroundColor(CodepetTheme.mutedText)
            .lineLimit(1)
            .truncationMode(.tail)
        if reduceMotion {
            base
        } else {
            TimelineView(.animation) { tl in
                let phase = tl.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 2.1) / 2.1
                base.overlay(
                    LinearGradient(
                        gradient: Gradient(colors: [.clear, CodepetTheme.primaryText.opacity(0.7), .clear]),
                        startPoint: .leading, endPoint: .trailing)
                    .frame(width: 60)
                    .offset(x: CGFloat(phase * 260 - 60))
                    .mask(base)
                    .allowsHitTesting(false)
                )
            }
        }
    }
}

#if DEBUG
#Preview("ChatThinkingRow") {
    VStack(alignment: .leading, spacing: 16) {
        ChatThinkingRow(taskTitle: nil)
        ChatThinkingRow(taskTitle: "positioning brief")
        // The activity state — literal, non-rotating, reviewable alongside the two
        // rotations below on the same 380pt dock width the founder actually sees.
        ChatThinkingRow(companionId: "luna",
                        activity: ChatToolActivity(kind: .readFile, target: "mml-book.pdf"))
        ChatThinkingRow(companionId: "luna",
                        activity: ChatToolActivity(kind: .fetchPage, target: "web.murror.app/welcome"))
        ChatThinkingRow(companionId: "luna",
                        activity: ChatToolActivity(kind: .searchWeb, target: nil))
        Divider()
        // Both rotations, reviewable on one canvas. Read off `ChatThinkingLabel` rather
        // than by building rows: `variant` is private `@State` (rolled once per appearance,
        // on purpose) and there is no injecting it from out here.
        ForEach(0..<ChatThinkingLabel.phraseCount, id: \.self) { i in
            Text(ChatThinkingLabel.text(taskTitle: nil, language: .en, variant: i)
                 + "   ·   "
                 + ChatThinkingLabel.text(petName: "Nova", taskTitle: nil,
                                          language: .en, variant: i))
                .font(CodepetTheme.inter(13))
                .foregroundColor(CodepetTheme.mutedText)
        }
    }
    .padding(40)
    .frame(width: 380)
    .environmentObject(CompanyStore())
}
#endif

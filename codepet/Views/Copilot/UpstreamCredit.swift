import SwiftUI

/// "Built on Luna's brand direction" — what a deliverable inherited, on the card that carries it.
///
/// **Why this exists.** A department's run now receives the finished work of the departments it
/// `dependsOn` (`UpstreamWork`), and a founder who cannot see that has no way to tell a team
/// from eight strangers working in the same window. The roadmap drew the dependency arrows all
/// along; this is the first place the founder learns that the arrow carried something.
///
/// **The line is a pure static, not a `switch` in `body`.** Every decision worth getting wrong
/// here — absent versus empty, which contribution gets named, whether the unapproved note
/// appears — is in `line(_:)`, so the suite pins it without rendering anything.
struct UpstreamCredit: View {
    let work: [UpstreamWork]

    /// The credit sentence, or nil when there is nothing to credit.
    ///
    /// **Nil, not an empty string.** A task with no dependencies is the common case, and a
    /// blank row above the deliverable reads as a card that failed to load something.
    ///
    /// Names the first contribution and counts the rest. Listing all three would put more
    /// words about the provenance on the card than the deliverable gets, and `dependsOn`
    /// order is deliberate in the fixture, so "first" is the one worth naming.
    ///
    /// The unapproved note is appended whenever ANY item is unapproved, not only the first:
    /// what the founder is being told is that something under this card skipped approval, and
    /// the position it arrived in is not something they can see.
    /// **The title is QUOTED, and that is not decoration.** `taskTitle` is a deliverable's
    /// title, and a deliverable's title is frequently an imperative sentence — the fallback in
    /// `buildDeliverable` is the task's own name, so the real value here is "Shape the Murror
    /// visual direction", not "brand direction". Unquoted, the possessive produced
    /// *"Built on Luna's Shape the Murror visual direction"*, which is not a sentence. Caught
    /// by rendering the row and reading it; every test fixture written for this used a tidy
    /// noun phrase and none of them could have found it.
    static func line(_ work: [UpstreamWork], _ lang: AppLanguage = .en) -> String? {
        guard let first = work.first else { return nil }
        let who = first.petName.isEmpty ? first.deptName : first.petName
        let title = "\u{201C}\(first.taskTitle)\u{201D}"
        var line: String
        if lang == .vi {
            // Vietnamese puts the owner AFTER the thing owned ("X của Luna"), so this is a
            // different sentence rather than a word-for-word swap.
            line = who.isEmpty ? "Dựa trên \(title)" : "Dựa trên \(title) của \(who)"
            if work.count > 1 { line += " + \(work.count - 1) nữa" }
            if work.contains(where: \.unapproved) { line += " (bản nháp chưa duyệt)" }
        } else {
            line = who.isEmpty ? "Built on \(title)" : "Built on \(who)'s \(title)"
            if work.count > 1 { line += " + \(work.count - 1) more" }
            if work.contains(where: \.unapproved) { line += " (unapproved draft)" }
        }
        return line
    }

    @Environment(\.uiLanguage) private var lang

    var body: some View {
        if let line = Self.line(work, lang) {
            HStack(spacing: 8) {
                // A 2pt rule rather than an icon: this is a provenance note attached to the
                // deliverable above it, and Codepet keeps only functional icons.
                Rectangle()
                    .fill(CodepetTheme.accentPurple.opacity(0.5))
                    .frame(width: 2)
                Text(line)
                    .font(.pixelSystem(size: 11.5))
                    .foregroundColor(CodepetTheme.accentPurple)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            // **Deliberately NOT tappable.** It was — pointing-hand cursor and all — and the tap
            // opened `showDetail`, i.e. the DOWNSTREAM draft the founder was already looking at,
            // not the upstream work the line names. A pointer cursor promising to open "Luna's
            // brand direction" and showing you Nova's landing page instead is worse than no
            // affordance. Opening the right thing is not reliably possible here: the library
            // case is resolvable through `sourceTaskId`, but a CHAINED item is an unapproved
            // draft that is deliberately not in the library and has nothing to open.
            .accessibilityLabel(line)
        }
    }
}

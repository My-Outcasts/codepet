import SwiftUI

/// A card for a *live* dictionary entry — a term Codepet actually detected in the
/// user's code. Unlike `DictionaryCard` (static reference content), this renders
/// real provenance ("seen in LoginView.swift") and the term's
/// Encountered → Used → Mastered evolution. Same pixel-card visual language.
struct ProjectDictionaryCard: View {

    @Environment(\.uiLanguage) private var uiLanguage

    let entry: DictionaryEntry
    /// Topic brand color, passed down from `DictionaryView` so the card matches
    /// its sidebar group.
    let accent: Color
    let isExpanded: Bool
    let onToggleExpand: () -> Void

    @State private var hovering = false

    private var monogram: String {
        let t = entry.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return String(t.prefix(1)).uppercased()
    }

    var body: some View {
        PixelCard(fill: accent.opacity(0.07), borderColor: accent,
                  shadowOffset: 2, blockSize: 2, steps: 2, borderWidth: 2) {
            VStack(alignment: .leading, spacing: 10) {
                header

                Text(markdown: entry.cardDefinition)
                    .font(CodepetTheme.body(14))
                    .foregroundColor(CodepetTheme.bodyText)
                    .lineLimit(isExpanded ? nil : 3)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)

                seenInRow

                if isExpanded {
                    deepDive
                        .transition(.opacity)
                }

                Spacer(minLength: 6)
                footer
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .offset(y: hovering ? -3 : 0)
        .shadow(color: hovering ? accent.opacity(0.28) : .clear, radius: 8, x: 0, y: 5)
        .contentShape(Rectangle())
        .onTapGesture { if !isExpanded { onToggleExpand() } }
        .onHover { hovering = $0 }
        .animation(.easeInOut(duration: 0.18), value: hovering)
        .animation(.easeInOut(duration: 0.22), value: isExpanded)
    }

    // MARK: - Header (monogram + title + evolution)

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            Text(monogram)
                .font(.pixelSystem(size: 15, weight: .bold))
                .foregroundColor(.white)
                .frame(width: 32, height: 32)
                .pixelBox(fill: accent, shadowOffset: 2, blockSize: 2, steps: 1, borderWidth: 2)

            Text(entry.title)
                .font(CodepetTheme.body(16, weight: .bold))
                .foregroundColor(CodepetTheme.primaryText)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            evolutionPill
        }
    }

    // MARK: - Evolution pill (Encountered → Used → Mastered)

    private struct Stage {
        let label: String
        let filled: Int
        let color: Color
    }

    private var stage: Stage {
        switch entry.evolution {
        case "mastered":
            return Stage(label: uiLanguage == .vi ? "Thành thạo" : "Mastered",
                         filled: 3, color: CodepetTheme.accentGold)
        case "used":
            return Stage(label: uiLanguage == .vi ? "Đã dùng" : "Used",
                         filled: 2, color: accent)
        default:
            return Stage(label: uiLanguage == .vi ? "Gặp qua" : "Encountered",
                         filled: 1, color: CodepetTheme.mutedText)
        }
    }

    private var evolutionPill: some View {
        let s = stage
        return HStack(spacing: 5) {
            HStack(spacing: 3) {
                ForEach(0..<3, id: \.self) { i in
                    Circle()
                        .fill(i < s.filled ? s.color : s.color.opacity(0.22))
                        .frame(width: 6, height: 6)
                }
            }
            Text(s.label.uppercased())
                .font(.pixelSystem(size: 9, weight: .semibold))
                .tracking(0.8)
                .foregroundColor(s.color)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Capsule().fill(s.color.opacity(0.12)))
    }

    // MARK: - "Seen in" provenance

    @ViewBuilder
    private var seenInRow: some View {
        let files = entry.seenIn.prefix(3)
        if !files.isEmpty {
            HStack(spacing: 6) {
                Image(systemName: "doc.text.fill")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(accent)
                Text(uiLanguage == .vi ? "thấy trong" : "seen in")
                    .font(.pixelSystem(size: 9, weight: .semibold))
                    .foregroundColor(CodepetTheme.mutedText)
                ForEach(Array(files.enumerated()), id: \.offset) { _, ref in
                    Text(ref.file)
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundColor(accent)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(accent.opacity(0.12)))
                        .lineLimit(1)
                }
                if entry.seenIn.count > 3 {
                    Text("+\(entry.seenIn.count - 3)")
                        .font(.pixelSystem(size: 9, weight: .semibold))
                        .foregroundColor(CodepetTheme.mutedText)
                }
                Spacer(minLength: 0)
            }
        }
    }

    // MARK: - Memory-strength ladder (spaced retrieval)

    /// ◆◆◆◇◇ — how deep the term is stuck — plus when it next wants a rep. Shows
    /// only once the term has a review schedule; "due" reads in gold for pull.
    @ViewBuilder
    private var reviewLadder: some View {
        if let review = entry.review {
            let filled = min(review.box + 1, 5)
            let due = review.dueAt <= Date()
            HStack(spacing: 6) {
                HStack(spacing: 3) {
                    ForEach(0..<5, id: \.self) { i in
                        Image(systemName: i < filled ? "diamond.fill" : "diamond")
                            .font(.system(size: 7, weight: .bold))
                            .foregroundColor(i < filled ? accent : accent.opacity(0.32))
                    }
                }
                Text(nextReviewLabel(review))
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(due ? CodepetTheme.accentGold : CodepetTheme.mutedText)
            }
            .help(uiLanguage == .vi ? "Độ ghi nhớ (lặp lại ngắt quãng)" : "Memory strength (spaced retrieval)")
        }
    }

    private func nextReviewLabel(_ review: ReviewState) -> String {
        let now = Date()
        if review.dueAt <= now { return uiLanguage == .vi ? "đến hạn" : "due today" }
        let days = max(1, Int(ceil(review.dueAt.timeIntervalSince(now) / 86_400)))
        return uiLanguage == .vi ? "ôn sau \(days) ngày" : "review in \(days)d"
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 6) {
            reviewLadder
            Spacer(minLength: 0)
            Button(action: onToggleExpand) {
                HStack(spacing: 4) {
                    Text(isExpanded
                         ? (uiLanguage == .vi ? "Thu gọn" : "Less")
                         : (uiLanguage == .vi ? "Tìm hiểu" : "Learn more"))
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10, weight: .bold))
                }
                .font(.pixelSystem(size: 11, weight: .semibold))
                .foregroundColor(accent)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Deep dive

    @ViewBuilder
    private var deepDive: some View {
        VStack(alignment: .leading, spacing: 16) {
            if !entry.milestoneNote.isEmpty {
                milestoneBanner
            }

            section(title: uiLanguage == .vi ? "Hiểu sâu hơn" : "What it really means",
                    body: entry.whatItReallyMeans)

            if !entry.analogy.isEmpty {
                section(title: uiLanguage == .vi ? "Hình dung" : "Think of it like",
                        body: entry.analogy)
            }

            if !entry.codeExample.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    sectionLabel("Code")
                    Text(entry.codeExample)
                        .font(.system(size: 14, weight: .regular, design: .monospaced))
                        .foregroundColor(CodepetTheme.primaryText)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .pixelBox(fill: Color(white: 0.96), shadowOffset: 2,
                                  blockSize: 2, steps: 2, borderWidth: 2)
                }
            }

            if !entry.whenToUse.isEmpty {
                section(title: uiLanguage == .vi ? "Khi nào dùng" : "When to use",
                        body: entry.whenToUse)
            }

            if !entry.related.isEmpty {
                relatedChips
            }
        }
        .padding(.top, 4)
    }

    /// The pet's note on reaching this stage — the moment the term levels up.
    private var milestoneBanner: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "sparkles")
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(stage.color)
            Text(markdown: entry.milestoneNote)
                .font(CodepetTheme.body(13))
                .foregroundColor(CodepetTheme.bodyText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(stage.color.opacity(0.10))
        )
    }

    private var relatedChips: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionLabel(uiLanguage == .vi ? "Liên quan" : "Related")
            FlexWrap(spacing: 6, runSpacing: 6) {
                ForEach(entry.related, id: \.self) { rel in
                    Text(rel)
                        .font(.pixelSystem(size: 11, weight: .semibold))
                        .foregroundColor(accent)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(accent.opacity(0.12)))
                }
            }
        }
    }

    private func section(title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionLabel(title)
            Text(markdown: body)
                .font(CodepetTheme.body(15))
                .foregroundColor(CodepetTheme.bodyText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 1, style: .continuous)
                .fill(accent)
                .frame(width: 14, height: 4)
            Text(text.uppercased())
                .font(CodepetTheme.body(11, weight: .semibold))
                .tracking(1.2)
                .foregroundColor(CodepetTheme.bodyText)
        }
    }
}

/// Minimal flow layout for the related-term chips (wraps to the next line when a
/// row fills). Kept local so the card doesn't depend on a global wrap helper.
private struct FlexWrap: Layout {
    var spacing: CGFloat = 6
    var runSpacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                x = 0; y += rowHeight + runSpacing; rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: maxWidth == .infinity ? x : maxWidth, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX; y += rowHeight + runSpacing; rowHeight = 0
            }
            sub.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

import SwiftUI

// =============================================================================
// MARK: - MentorQADetailView
// =============================================================================

/// Full Q&A reader. Shows the expert avatar, question, full answer in serif
/// font, and follow-up question pills at the bottom. Marks the Q&A as read
/// on appear.
struct MentorQADetailView: View {
    @EnvironmentObject var learnProgress: LearnProgress
    @Environment(\.dismiss) private var dismiss

    let qa: MentorQA

    private var expert: Expert? {
        ExpertContent.experts.first { $0.id == qa.expertId }
    }

    private var isRead: Bool {
        learnProgress.readQAIds.contains(qa.id)
    }

    private let borderColor = Color(hex: "#2D2B26")

    var body: some View {
        ZStack {
            Color(hex: "#F7F5FC")
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // ─────────────────────────────────────────────────────────────
                // Top bar
                // ─────────────────────────────────────────────────────────────
                topBar

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 24) {

                        // ─────────────────────────────────────────────────────
                        // Expert header
                        // ─────────────────────────────────────────────────────
                        expertHeader

                        // ─────────────────────────────────────────────────────
                        // Question
                        // ─────────────────────────────────────────────────────
                        questionSection

                        // ─────────────────────────────────────────────────────
                        // Answer
                        // ─────────────────────────────────────────────────────
                        answerSection

                        // ─────────────────────────────────────────────────────
                        // Follow-up questions
                        // ─────────────────────────────────────────────────────
                        if !qa.followUps.isEmpty {
                            followUpSection
                        }

                        // ─────────────────────────────────────────────────────
                        // Mark as read button
                        // ─────────────────────────────────────────────────────
                        markAsReadButton

                        Spacer(minLength: 40)
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 16)
                }
            }
        }
        .onAppear {
            // Auto-mark as read when opened
            if !isRead {
                learnProgress.markQARead(qa.id)
            }
        }
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack {
            Button(action: { dismiss() }) {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 14, weight: .semibold))
                    Text("Ask Astro")
                        .font(CodepetTheme.body(14, weight: .semibold))
                }
                .foregroundColor(Color(hex: "#7C3AED"))
            }
            .buttonStyle(.plain)

            Spacer()
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
        .background(Color(hex: "#F7F5FC"))
    }

    // MARK: - Expert Header

    private var expertHeader: some View {
        HStack(spacing: 12) {
            if let expert = expert {
                // Expert avatar
                ZStack {
                    PixelStaircaseRectangle(blockSize: 3, steps: 2)
                        .fill(Color(hex: expert.avatarColor))
                        .frame(width: 44, height: 44)

                    Text(expert.initials)
                        .font(CodepetTheme.pixel(16))
                        .foregroundColor(.white)
                }
                .overlay(
                    PixelStaircaseRectangle(blockSize: 3, steps: 2)
                        .stroke(borderColor, lineWidth: 2)
                )

                VStack(alignment: .leading, spacing: 2) {
                    Text("\(expert.name) answers:")
                        .font(CodepetTheme.body(14, weight: .semibold))
                        .foregroundColor(borderColor)
                    Text(expert.role)
                        .font(CodepetTheme.body(11, weight: .medium))
                        .foregroundColor(CodepetTheme.mutedText)
                }
            }
        }
    }

    // MARK: - Question

    private var questionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Icon
            ZStack {
                PixelStaircaseRectangle(blockSize: 2, steps: 2)
                    .fill(Color(hex: qa.iconColor))
                    .frame(width: 36, height: 36)

                Image(systemName: qa.iconName)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.white)
            }
            .overlay(
                PixelStaircaseRectangle(blockSize: 2, steps: 2)
                    .stroke(borderColor, lineWidth: 2)
            )

            Text(qa.question)
                .font(CodepetTheme.display(20))
                .foregroundColor(borderColor)

            Text(qa.hint)
                .font(CodepetTheme.body(13, weight: .medium))
                .foregroundColor(CodepetTheme.mutedText)
        }
    }

    // MARK: - Answer

    private var answerSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            let paragraphs = qa.answer
                .components(separatedBy: "\n\n")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }

            ForEach(Array(paragraphs.enumerated()), id: \.offset) { _, paragraph in
                Text(paragraph)
                    .font(ReflectionTheme.serif(14))
                    .foregroundColor(CodepetTheme.bodyText)
                    .lineSpacing(6)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .pixelBox(
            fill: Color(hex: "#FDFCFF"),
            borderColor: borderColor.opacity(0.3),
            shadowOffset: 0,
            blockSize: 3,
            steps: 2,
            borderWidth: 2
        )
    }

    // MARK: - Follow-Up Questions

    private var followUpSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 5) {
                Image(systemName: "arrow.turn.down.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(Color(hex: "#7C3AED"))
                Text("FOLLOW-UP QUESTIONS")
                    .font(CodepetTheme.body(10, weight: .semibold))
                    .tracking(1.2)
                    .foregroundColor(Color(hex: "#7C3AED"))
            }

            FlowLayout(spacing: 8) {
                ForEach(qa.followUps, id: \.self) { followUp in
                    Button(action: {
                        // Connect to pet chat in the future
                        print("[Learn] Follow-up tapped: \(followUp)")
                    }) {
                        Text(followUp)
                            .font(CodepetTheme.body(12, weight: .medium))
                            .foregroundColor(Color(hex: "#7C3AED"))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(
                                Capsule()
                                    .fill(Color(hex: "#7C3AED").opacity(0.08))
                            )
                            .overlay(
                                Capsule()
                                    .stroke(Color(hex: "#7C3AED").opacity(0.2), lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Mark as Read Button

    private var markAsReadButton: some View {
        HStack {
            Spacer()

            if isRead {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 14))
                    Text("Read")
                        .font(CodepetTheme.body(13, weight: .semibold))
                }
                .foregroundColor(Color(hex: "#029902"))
            } else {
                Button(action: {
                    learnProgress.markQARead(qa.id)
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "book.closed.fill")
                            .font(.system(size: 13))
                        Text("Mark as read")
                            .font(CodepetTheme.body(13, weight: .bold))
                    }
                }
                .buttonStyle(PixelButtonStyle(
                    fill: Color(hex: "#7C3AED"),
                    foreground: .white,
                    borderColor: borderColor,
                    paddingH: 18,
                    paddingV: 9,
                    blockSize: 3,
                    steps: 2,
                    borderWidth: 3,
                    shadowOffset: 3
                ))
            }

            Spacer()
        }
        .padding(.top, 8)
    }
}

// =============================================================================
// MARK: - FlowLayout
// =============================================================================

/// A simple flow layout that wraps children horizontally, moving to the next
/// line when the available width is exhausted. Used for follow-up question pills.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = arrange(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(proposal: proposal, subviews: subviews)
        for (index, subview) in subviews.enumerated() {
            guard index < result.positions.count else { continue }
            let position = result.positions[index]
            subview.place(
                at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y),
                proposal: .unspecified
            )
        }
    }

    private struct ArrangeResult {
        var size: CGSize
        var positions: [CGPoint]
    }

    private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> ArrangeResult {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var lineHeight: CGFloat = 0
        var totalWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)

            if currentX + size.width > maxWidth, currentX > 0 {
                currentX = 0
                currentY += lineHeight + spacing
                lineHeight = 0
            }

            positions.append(CGPoint(x: currentX, y: currentY))
            lineHeight = max(lineHeight, size.height)
            currentX += size.width + spacing
            totalWidth = max(totalWidth, currentX - spacing)
        }

        return ArrangeResult(
            size: CGSize(width: totalWidth, height: currentY + lineHeight),
            positions: positions
        )
    }
}

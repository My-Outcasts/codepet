import SwiftUI

// =============================================================================
// MARK: - CaseStudyDetailView
// =============================================================================

/// Full detail view for a case study, shown as a sheet. Displays header info,
/// chapter list with completion checkmarks, and overall progress. Tapping a
/// chapter opens ChapterReaderView.
struct CaseStudyDetailView: View {
    @EnvironmentObject var learnProgress: LearnProgress
    @Environment(\.dismiss) private var dismiss

    let caseStudy: CaseStudy

    @State private var selectedChapter: Chapter? = nil

    private var expert: Expert? {
        ExpertContent.experts.first { $0.id == caseStudy.expertId }
    }

    private var completedCount: Int {
        learnProgress.completedCount(for: caseStudy)
    }

    private var totalCount: Int {
        learnProgress.totalCount(for: caseStudy)
    }

    private var progressFraction: Double {
        learnProgress.progress(for: caseStudy)
    }

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
                    VStack(alignment: .leading, spacing: 20) {
                        // ─────────────────────────────────────────────────────
                        // Header
                        // ─────────────────────────────────────────────────────
                        headerSection

                        // ─────────────────────────────────────────────────────
                        // Progress bar
                        // ─────────────────────────────────────────────────────
                        overallProgress

                        // ─────────────────────────────────────────────────────
                        // Chapter list
                        // ─────────────────────────────────────────────────────
                        chapterListSection

                        Spacer(minLength: 40)
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 16)
                }
            }
        }
        .sheet(item: $selectedChapter) { chapter in
            ChapterReaderView(
                chapter: chapter,
                caseStudyTitle: caseStudy.title,
                chapterNumber: chapterNumber(for: chapter)
            )
            .environmentObject(learnProgress)
        }
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack {
            Button(action: { dismiss() }) {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 14, weight: .semibold))
                    Text("Learn")
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

    // MARK: - Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Icon + color accent
            ZStack {
                PixelStaircaseRectangle(blockSize: 3, steps: 2)
                    .fill(Color(hex: caseStudy.color))
                    .frame(width: 48, height: 48)

                Image(systemName: caseStudy.icon)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.white)
            }
            .overlay(
                PixelStaircaseRectangle(blockSize: 3, steps: 2)
                    .stroke(Color(hex: "#2D2B26"), lineWidth: 2)
            )

            Text(caseStudy.title)
                .font(CodepetTheme.display(22))
                .foregroundColor(Color(hex: "#2D2B26"))

            if let expert = expert {
                HStack(spacing: 6) {
                    // Mini avatar
                    ZStack {
                        Circle()
                            .fill(Color(hex: expert.avatarColor))
                            .frame(width: 20, height: 20)
                        Text(expert.initials)
                            .font(CodepetTheme.body(8, weight: .bold))
                            .foregroundColor(.white)
                    }
                    Text("by \(expert.name)")
                        .font(CodepetTheme.body(12, weight: .medium))
                        .foregroundColor(CodepetTheme.mutedText)
                }
            }

            // Tags
            HStack(spacing: 6) {
                ForEach(caseStudy.tags, id: \.self) { tag in
                    Text(tag)
                        .font(CodepetTheme.body(10, weight: .semibold))
                        .foregroundColor(Color(hex: caseStudy.color))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(
                            Capsule()
                                .fill(Color(hex: caseStudy.color).opacity(0.12))
                        )
                }
            }
        }
    }

    // MARK: - Overall Progress

    private var overallProgress: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("\(completedCount) of \(totalCount) chapters completed")
                    .font(CodepetTheme.body(12, weight: .medium))
                    .foregroundColor(CodepetTheme.bodyText)
                Spacer()
                Text("\(Int(progressFraction * 100))%")
                    .font(CodepetTheme.body(12, weight: .bold))
                    .foregroundColor(Color(hex: "#7C3AED"))
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    PixelStaircaseRectangle(blockSize: 2, steps: 1)
                        .fill(Color(hex: "#2D2B26").opacity(0.1))
                        .frame(height: 10)

                    PixelStaircaseRectangle(blockSize: 2, steps: 1)
                        .fill(Color(hex: "#7C3AED"))
                        .frame(width: max(geo.size.width * progressFraction, 0), height: 10)
                }
            }
            .frame(height: 10)
        }
        .padding(14)
        .pixelBox(
            fill: Color(hex: "#FDFCFF"),
            borderColor: Color(hex: "#2D2B26"),
            shadowOffset: 2,
            blockSize: 3,
            steps: 2,
            borderWidth: 2
        )
    }

    // MARK: - Chapter List

    private var chapterListSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("CHAPTERS")
                .font(CodepetTheme.body(10, weight: .semibold))
                .tracking(1.4)
                .foregroundColor(CodepetTheme.mutedText)

            VStack(spacing: 0) {
                ForEach(Array(caseStudy.chapters.enumerated()), id: \.element.id) { index, chapter in
                    let isCompleted = learnProgress.completedChapterIds.contains(chapter.id)

                    Button(action: { selectedChapter = chapter }) {
                        HStack(spacing: 12) {
                            // Chapter number or checkmark
                            ZStack {
                                PixelStaircaseRectangle(blockSize: 2, steps: 1)
                                    .fill(isCompleted ? Color(hex: "#029902") : Color(hex: "#2D2B26").opacity(0.08))
                                    .frame(width: 32, height: 32)

                                if isCompleted {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 13, weight: .bold))
                                        .foregroundColor(.white)
                                } else {
                                    Text("\(index + 1)")
                                        .font(CodepetTheme.pixel(14))
                                        .foregroundColor(Color(hex: "#2D2B26"))
                                }
                            }
                            .overlay(
                                PixelStaircaseRectangle(blockSize: 2, steps: 1)
                                    .stroke(isCompleted ? Color(hex: "#029902") : Color(hex: "#2D2B26").opacity(0.2), lineWidth: 2)
                            )

                            // Title
                            Text(chapter.title)
                                .font(CodepetTheme.body(14, weight: isCompleted ? .regular : .medium))
                                .foregroundColor(isCompleted ? CodepetTheme.mutedText : Color(hex: "#2D2B26"))
                                .strikethrough(isCompleted, color: CodepetTheme.mutedText)

                            Spacer()

                            Image(systemName: "chevron.right")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(CodepetTheme.mutedText)
                        }
                        .padding(.vertical, 12)
                        .padding(.horizontal, 14)
                    }
                    .buttonStyle(.plain)

                    // Divider between chapters
                    if index < caseStudy.chapters.count - 1 {
                        Rectangle()
                            .fill(Color(hex: "#2D2B26").opacity(0.08))
                            .frame(height: 1)
                            .padding(.leading, 58)
                    }
                }
            }
            .pixelBox(
                fill: .white,
                borderColor: Color(hex: "#2D2B26"),
                shadowOffset: 2,
                blockSize: 3,
                steps: 2,
                borderWidth: 2
            )
        }
    }

    // MARK: - Helpers

    private func chapterNumber(for chapter: Chapter) -> Int {
        (caseStudy.chapters.firstIndex(where: { $0.id == chapter.id }) ?? 0) + 1
    }
}

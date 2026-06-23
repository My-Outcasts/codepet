import SwiftUI

// =============================================================================
// MARK: - LearnTabView
// =============================================================================

struct LearnTabView: View {
    @EnvironmentObject var learnProgress: LearnProgress

    @State private var selectedCaseStudy: CaseStudy? = nil
    @State private var selectedQA: MentorQA? = nil

    private let expert = ExpertContent.experts.first!
    private let caseStudies = ExpertContent.caseStudies
    private let mentorQAs = ExpertContent.mentorQAs

    private let columns = [
        GridItem(.flexible(minimum: 100), spacing: 16),
        GridItem(.flexible(minimum: 100), spacing: 16)
    ]

    var body: some View {
        ZStack {
            Color(hex: "#F7F5FC")
                .ignoresSafeArea()

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 24) {
                    expertHeroSection

                    sectionEyebrow(icon: "hammer.fill", label: "BUILD-ALONG CASE STUDIES")

                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(caseStudies) { cs in
                            CaseStudyCard(
                                caseStudy: cs,
                                progress: learnProgress.progress(for: cs),
                                completedCount: learnProgress.completedCount(for: cs)
                            ) {
                                selectedCaseStudy = cs
                            }
                        }
                    }

                    sectionEyebrow(icon: "bubble.left.and.bubble.right.fill", label: "ASK ASTRO")

                    VStack(spacing: 12) {
                        ForEach(mentorQAs) { qa in
                            MentorQACard(qa: qa, isRead: learnProgress.readQAIds.contains(qa.id)) {
                                selectedQA = qa
                            }
                        }
                    }

                    Spacer(minLength: 40)
                }
                .padding(.horizontal, 24)
                .padding(.top, 24)
            }
        }
        .sheet(item: $selectedCaseStudy) { cs in
            CaseStudyDetailView(caseStudy: cs)
                .environmentObject(learnProgress)
        }
        .sheet(item: $selectedQA) { qa in
            MentorQADetailView(qa: qa)
                .environmentObject(learnProgress)
        }
    }

    // MARK: - Expert Hero Section

    private var expertHeroSection: some View {
        PixelCard(fill: Color(hex: expert.avatarColor), borderWidth: 3) {
            HStack(spacing: 16) {
                // Avatar — white square with colored initials
                ZStack {
                    PixelStaircaseRectangle(blockSize: 2, steps: 1)
                        .fill(Color.white)
                    Text(expert.initials)
                        .font(CodepetTheme.pixel(24))
                        .foregroundColor(Color(hex: expert.avatarColor))
                }
                .frame(width: 56, height: 56)
                .overlay(
                    PixelStaircaseRectangle(blockSize: 2, steps: 1)
                        .stroke(Color(hex: "#2D2B26"), lineWidth: 2)
                )

                VStack(alignment: .leading, spacing: 4) {
                    Text(expert.name)
                        .font(CodepetTheme.display(20))
                        .foregroundColor(.white)

                    Text(expert.role)
                        .font(.pixelSystem(size: 11, weight: .medium))
                        .foregroundColor(Color.white.opacity(0.75))

                    Text(expert.bio)
                        .font(.pixelSystem(size: 12))
                        .foregroundColor(Color.white.opacity(0.85))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 2)
                }

                Spacer(minLength: 0)
            }
            .padding(18)
        }
    }

    // MARK: - Section Eyebrow

    private func sectionEyebrow(icon: String, label: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(CodepetTheme.mutedText)
            Text(label)
                .font(CodepetTheme.body(10, weight: .semibold))
                .tracking(1.4)
                .foregroundColor(CodepetTheme.mutedText)
        }
        .padding(.top, 4)
    }
}

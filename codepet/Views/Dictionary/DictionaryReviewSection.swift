import SwiftUI

/// Spaced-retrieval surface for the Dictionary: the daily "Review" hook and the
/// reveal-then-self-grade recall flow. Self-hides entirely when nothing is due,
/// so it costs the user nothing until a term is actually drifting.
///
/// The passive path (a term recurring in real code) is handled upstream in
/// `DictionaryEnricher`; this view is only the *active* safety net for terms
/// that did NOT recur on their own. Grading is self-rated — no typing test —
/// because forced friction gets abandoned.
struct DictionaryReviewSection: View {

    @Environment(\.uiLanguage) private var uiLanguage
    @EnvironmentObject private var store: ProjectDictionaryStore

    // A captured queue, so grading (which reschedules terms) can't reshuffle the
    // deck mid-flow.
    @State private var reviewing = false
    @State private var queue: [DictionaryEntry] = []
    @State private var index = 0
    @State private var revealed = false
    @State private var lastNote: String?

    private let gold = Color(hex: "#C99A4E")
    private let goldTint = Color(hex: "#F4ECDA")
    private let goldLine = Color(hex: "#E6D3AC")
    private let green = Color(hex: "#4F6B4A")
    private let clay = Color(hex: "#B4654A")

    var body: some View {
        let due = store.dueReviewEntries()
        if reviewing {
            reviewFlow
        } else if !due.isEmpty {
            hookCard(count: due.count)
        }
    }

    // MARK: - Surface 1: the hook

    private func hookCard(count: Int) -> some View {
        PixelCard(fill: goldTint, borderColor: gold,
                  shadowOffset: 2, blockSize: 2, steps: 2, borderWidth: 2) {
            HStack(spacing: 14) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 44, height: 44)
                    .pixelBox(fill: gold, shadowOffset: 2, blockSize: 2, steps: 1, borderWidth: 2)

                VStack(alignment: .leading, spacing: 3) {
                    Text(uiLanguage == .vi ? "Ôn tập · \(count) từ" : "Review · \(count) term\(count == 1 ? "" : "s") ready")
                        .font(CodepetTheme.body(14, weight: .bold))
                        .foregroundColor(CodepetTheme.primaryText)
                    Text(uiLanguage == .vi
                         ? "~30 giây. Bạn không phải học bài — byte chỉ hỏi những từ sắp quên."
                         : "~30 seconds. You don’t study — byte only asks about the ones drifting away.")
                        .font(CodepetTheme.body(12))
                        .foregroundColor(CodepetTheme.bodyText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)

                Button { startReview() } label: {
                    Text(uiLanguage == .vi ? "Ôn ngay →" : "Review →")
                        .font(.pixelSystem(size: 11, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Capsule().fill(gold))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
        .padding(.bottom, 4)
    }

    // MARK: - Surface 2: the recall flow

    @ViewBuilder
    private var reviewFlow: some View {
        if index >= queue.count {
            doneCard
        } else {
            recallCard(queue[index])
        }
    }

    private func recallCard(_ entry: DictionaryEntry) -> some View {
        PixelCard(fill: CodepetTheme.surface, borderColor: goldLine,
                  shadowOffset: 2, blockSize: 2, steps: 2, borderWidth: 2) {
            VStack(alignment: .leading, spacing: 0) {
                // progress
                HStack(spacing: 8) {
                    HStack(spacing: 4) {
                        ForEach(0..<queue.count, id: \.self) { i in
                            Capsule()
                                .fill(i < index ? green : (i == index ? gold : CodepetTheme.hairline))
                                .frame(width: 20, height: 4)
                        }
                    }
                    Spacer()
                    Text("\(min(index + 1, queue.count)) / \(queue.count)")
                        .font(.pixelSystem(size: 9, weight: .semibold))
                        .foregroundColor(CodepetTheme.mutedText)
                }
                .padding(.bottom, 16)

                Text(entry.term)
                    .font(.system(size: 18, weight: .medium, design: .monospaced))
                    .foregroundColor(green)
                Rectangle().fill(CodepetTheme.hairline).frame(height: 1).padding(.vertical, 12)

                if revealed {
                    Text(entry.cardDefinition)
                        .font(CodepetTheme.body(14))
                        .foregroundColor(CodepetTheme.bodyText)
                        .fixedSize(horizontal: false, vertical: true)
                    if let seenLabel = firstSeenLabel(entry) {
                        Text(seenLabel)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(CodepetTheme.mutedText)
                            .padding(.top, 8)
                    }
                    gradeRow(entry)
                        .padding(.top, 18)
                } else {
                    Text(uiLanguage == .vi ? "Bạn còn nhớ nó là gì không?" : "Do you remember what it does?")
                        .font(CodepetTheme.body(13))
                        .foregroundColor(CodepetTheme.mutedText)
                    Button {
                        withAnimation(.easeInOut(duration: 0.25)) { revealed = true }
                    } label: {
                        Text(uiLanguage == .vi ? "Cho tôi xem" : "Show me")
                            .font(.pixelSystem(size: 12, weight: .semibold))
                            .foregroundColor(green)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 9)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(green.opacity(0.12))
                                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .strokeBorder(green.opacity(0.4), style: StrokeStyle(lineWidth: 1, dash: [3])))
                            )
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 16)
                }
            }
            .padding(18)
        }
        .padding(.bottom, 4)
    }

    private func gradeRow(_ entry: DictionaryEntry) -> some View {
        HStack(spacing: 8) {
            gradeButton(uiLanguage == .vi ? "Nhớ rồi" : "Got it", icon: "checkmark", tint: green) {
                grade(entry, .gotIt)
            }
            gradeButton(uiLanguage == .vi ? "Mơ hồ" : "Fuzzy", icon: "wave.3.right", tint: gold) {
                grade(entry, .fuzzy)
            }
            gradeButton(uiLanguage == .vi ? "Quên mất" : "Forgot", icon: "xmark", tint: clay) {
                grade(entry, .forgot)
            }
        }
    }

    private func gradeButton(_ title: String, icon: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: icon).font(.system(size: 13, weight: .bold))
                Text(title).font(CodepetTheme.body(12, weight: .semibold))
            }
            .foregroundColor(tint)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(tint.opacity(0.10))
                    .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(tint.opacity(0.30), lineWidth: 1))
            )
        }
        .buttonStyle(.plain)
    }

    private var doneCard: some View {
        PixelCard(fill: CodepetTheme.surface, borderColor: CodepetTheme.accentTeal,
                  shadowOffset: 2, blockSize: 2, steps: 2, borderWidth: 2) {
            VStack(spacing: 8) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 30))
                    .foregroundColor(CodepetTheme.accentTeal)
                Text(uiLanguage == .vi ? "Xong — bạn đã ôn hết." : "Nice — caught up.")
                    .font(CodepetTheme.body(15, weight: .bold))
                    .foregroundColor(CodepetTheme.primaryText)
                Text(lastNote ?? (uiLanguage == .vi
                     ? "byte chỉ nhắc khi có từ sắp quên."
                     : "byte will only ping you when something’s slipping."))
                    .font(CodepetTheme.body(12))
                    .foregroundColor(CodepetTheme.mutedText)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Button { withAnimation { reviewing = false } } label: {
                    Text(uiLanguage == .vi ? "Xong" : "Done")
                        .font(.pixelSystem(size: 11, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 18).padding(.vertical, 7)
                        .background(Capsule().fill(CodepetTheme.accentTeal))
                }
                .buttonStyle(.plain)
                .padding(.top, 2)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 22)
            .padding(.horizontal, 16)
        }
        .padding(.bottom, 4)
    }

    // MARK: - Logic

    private func startReview() {
        queue = store.dueReviewEntries()
        index = 0
        revealed = false
        lastNote = nil
        withAnimation(.easeInOut(duration: 0.2)) { reviewing = !queue.isEmpty }
    }

    private func grade(_ entry: DictionaryEntry, _ g: RecallGrade) {
        store.recordReview(slug: entry.id, grade: g)
        lastNote = closingNote(for: g)
        withAnimation(.easeInOut(duration: 0.2)) {
            index += 1
            revealed = false
        }
    }

    private func closingNote(for g: RecallGrade) -> String {
        switch g {
        case .gotIt, .recurred:
            return uiLanguage == .vi ? "Tốt. Sẽ quay lại sau ~30 ngày." : "Solid — it comes back in ~30 days."
        case .fuzzy:
            return uiLanguage == .vi ? "Đã hẹn lại cho ngày mai." : "Brought it back for tomorrow."
        case .forgot:
            return uiLanguage == .vi ? "Không sao — sẽ xuất hiện lại trong vài giờ." : "No worries — it’ll resurface in a few hours."
        }
    }

    private func firstSeenLabel(_ entry: DictionaryEntry) -> String? {
        guard let first = entry.seenIn.last?.file ?? entry.seenIn.first?.file, !first.isEmpty else { return nil }
        return (uiLanguage == .vi ? "lần đầu thấy ở " : "first seen in ") + first
    }
}

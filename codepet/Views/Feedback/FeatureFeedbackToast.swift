import SwiftUI

/// Centered feedback pop-up shown after a user's first experience of a feature:
/// an icon + "Review rating" eyebrow, the feature's question, and a row of five
/// emoji faces (frown → smile). Picking a face reveals an optional comment +
/// Send. Styled with Codepet's pixel-box look rather than glassmorphism.
struct FeatureFeedbackPopup: View {
    let feature: FeedbackFeature
    let onSubmit: (Int, String) -> Void
    let onDismiss: () -> Void

    @Environment(\.uiLanguage) private var uiLanguage
    @State private var rating: Int = 0
    @State private var comment: String = ""

    private let ink = Color(hex: "#2D2B26")
    private let accent = Color(hex: "#7B6BD8")

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Eyebrow row: icon chip + label, with the close button trailing.
            HStack(spacing: 10) {
                Image(systemName: feature.icon)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(accent)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(accent.opacity(0.15)))
                Text(feature.eyebrow(uiLanguage).uppercased())
                    .font(.system(size: 12, weight: .semibold))
                    .tracking(0.8)
                    .foregroundColor(ink.opacity(0.5))
                Spacer(minLength: 0)
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(ink.opacity(0.4))
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(ink.opacity(0.06)))
                }
                .buttonStyle(.plain)
            }

            // Question.
            Text(feature.question(uiLanguage))
                .font(.system(size: 21, weight: .bold))
                .foregroundColor(ink)
                .fixedSize(horizontal: false, vertical: true)

            // Five faces, frown → smile.
            HStack(spacing: 10) {
                ForEach(1...5, id: \.self) { value in
                    faceButton(value)
                }
            }
            .frame(maxWidth: .infinity)

            // Comment + Send appear once a face is picked.
            if rating > 0 {
                HStack(spacing: 10) {
                    TextField(uiLanguage == .vi ? "Thêm nhận xét… (tuỳ chọn)" : "Add a comment… (optional)",
                              text: $comment)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(RoundedRectangle(cornerRadius: 10).fill(Color.white))
                        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(ink.opacity(0.12)))

                    Button(action: { onSubmit(rating, comment) }) {
                        Text(uiLanguage == .vi ? "Gửi" : "Send")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 18)
                            .padding(.vertical, 10)
                            .background(RoundedRectangle(cornerRadius: 10).fill(accent))
                    }
                    .buttonStyle(.plain)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .padding(22)
        .frame(width: 400)
        .pixelBox(fill: Color(hex: "#FDFCFF"), borderColor: accent,
                  shadowOffset: 3, blockSize: 2, steps: 2, borderWidth: 2)
    }

    // MARK: - Face button

    private func faceButton(_ value: Int) -> some View {
        let selected = rating == value
        return Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) { rating = value }
        } label: {
            ZStack {
                Circle().fill(selected ? Color.white : ink.opacity(0.05))
                Circle().strokeBorder(selected ? accent : ink.opacity(0.15),
                                      lineWidth: selected ? 2.5 : 1.5)
                MouthShape(curve: CGFloat(value - 3) / 2)
                    .stroke(selected ? accent : ink.opacity(0.5),
                            style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .frame(width: 22, height: 14)
            }
            .frame(width: 54, height: 54)
            .scaleEffect(selected ? 1.08 : 1)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
    }
}

/// A simple mouth curve: `curve` of -1 is a full frown (∩), 0 is flat, +1 is a
/// full smile (∪).
private struct MouthShape: Shape {
    var curve: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let left = CGPoint(x: rect.minX, y: rect.midY)
        let right = CGPoint(x: rect.maxX, y: rect.midY)
        // +curve dips the middle downward (smile); -curve raises it (frown).
        let control = CGPoint(x: rect.midX, y: rect.midY + curve * rect.height)
        path.move(to: left)
        path.addQuadCurve(to: right, control: control)
        return path
    }
}

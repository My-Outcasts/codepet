import SwiftUI

/// Reveals `text` one character at a time. Tap or click to skip to the end.
/// Used for the reflection summary in DemoReflectionView.
struct DemoTypewriterText: View {
    let text: String
    let charactersPerSecond: Double
    let font: Font
    let foregroundColor: Color

    @State private var revealedCount: Int = 0
    @State private var task: Task<Void, Never>? = nil

    init(
        text: String,
        charactersPerSecond: Double = 30,
        font: Font = .system(size: 14),
        foregroundColor: Color = .primary
    ) {
        self.text = text
        self.charactersPerSecond = charactersPerSecond
        self.font = font
        self.foregroundColor = foregroundColor
    }

    var body: some View {
        Text(String(text.prefix(revealedCount)))
            .font(font)
            .foregroundColor(foregroundColor)
            .multilineTextAlignment(.leading)
            .lineSpacing(3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .onAppear { startTyping() }
            .onDisappear { task?.cancel() }
            .onTapGesture { skipToEnd() }
            .contentShape(Rectangle())
    }

    private func startTyping() {
        task?.cancel()
        revealedCount = 0
        let totalChars = text.count
        let interval = 1.0 / charactersPerSecond
        task = Task { @MainActor in
            for _ in 0..<totalChars {
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                if Task.isCancelled { return }
                if revealedCount < totalChars { revealedCount += 1 }
            }
        }
    }

    private func skipToEnd() {
        task?.cancel()
        revealedCount = text.count
    }
}

#Preview {
    DemoTypewriterText(
        text: "Trong 12 phút, bạn build 1 landing page. Tôi để ý.",
        charactersPerSecond: 20
    )
    .padding()
    .frame(width: 400, height: 100)
}

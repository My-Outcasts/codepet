import SwiftUI

/// Terminal-style boot sequence shown above health-nudge modal content.
/// Each line of the input string is revealed sequentially with a small delay,
/// mimicking the `[ OK ] ...` boot log of an old terminal. Lines that begin
/// with `[` get the green-OK marker treatment; lines starting with `>` are
/// rendered as a status callout in the tone color.
///
/// On completion, calls `onCompleted` so the parent modal can transition to
/// its actual body content.
struct HealthBootLines: View {
    /// Multi-line string. One line per `\n`.
    let raw: String
    /// Time between successive line reveals.
    var lineInterval: TimeInterval = 0.42
    /// Pause after the final line before firing `onCompleted`.
    var trailingPause: TimeInterval = 0.5
    var onCompleted: () -> Void

    @State private var visibleCount: Int = 0
    @State private var task: Task<Void, Never>? = nil

    private var lines: [String] {
        raw.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(lines.enumerated()), id: \.offset) { (index, line) in
                if index < visibleCount {
                    bootLine(line)
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .move(edge: .leading)),
                            removal: .opacity
                        ))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear { startSequence() }
        .onDisappear { task?.cancel() }
    }

    @ViewBuilder
    private func bootLine(_ raw: String) -> some View {
        let okMarker = "[  OK  ]"
        if raw.hasPrefix(okMarker) {
            let rest = String(raw.dropFirst(okMarker.count))
            (
                Text(okMarker)
                    .foregroundColor(Color(hex: "#4FAE5C"))
                +
                Text(rest)
                    .foregroundColor(Color(hex: "#2D2B26"))
            )
            .font(.system(size: 11, weight: .regular, design: .monospaced))
        } else if raw.hasPrefix(">") {
            Text(raw)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundColor(Color(hex: "#7C3AED"))
        } else {
            Text(raw)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(Color(hex: "#2D2B26"))
        }
    }

    private func startSequence() {
        task?.cancel()
        visibleCount = 0
        let total = lines.count
        task = Task { @MainActor in
            for i in 0..<total {
                try? await Task.sleep(nanoseconds: UInt64(lineInterval * 1_000_000_000))
                if Task.isCancelled { return }
                withAnimation(.easeOut(duration: 0.22)) {
                    visibleCount = i + 1
                }
            }
            try? await Task.sleep(nanoseconds: UInt64(trailingPause * 1_000_000_000))
            if Task.isCancelled { return }
            onCompleted()
        }
    }
}

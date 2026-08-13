import SwiftUI

/// One line of a diff, with the hit target a future comment attaches to.
///
/// Its own file, and its own view, for one reason: **inline line comments are
/// the first thing after freeze** (design §10), and they attach here. Building
/// the diff as an undifferentiated `Text` block would mean rewriting the
/// renderer to add per-line interaction; building the row now means the comment
/// affordance drops into a place that already exists.
///
/// The hit target is live today — it tracks hover and reports the anchor — and
/// nothing is wired to it. That is deliberate rather than incomplete: the
/// geometry is the hard part to retrofit, the action is not.
struct DiffLineView: View {
    let line: DiffLine
    /// Called with the line a comment would attach to. `nil` today, which is
    /// what makes the row inert while still owning its target.
    var onComment: ((Int) -> Void)?

    @State private var hovering = false

    /// Gutter width for two line numbers. Fixed rather than measured so every
    /// row's code starts at the same x — a diff whose text shifts as numbers
    /// gain a digit is much harder to scan.
    private let gutter: CGFloat = 34

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            number(line.oldLine)
            number(line.newLine)

            Text(marker)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(markerColour)
                .frame(width: 12, alignment: .center)

            Text(line.text.isEmpty ? " " : line.text)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(textColour)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)

            // The affordance itself. Reserved even when hidden, so revealing it
            // on hover cannot reflow the line under the pointer.
            Group {
                if hovering, line.commentAnchor != nil, onComment != nil {
                    Image(systemName: "plus")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(CodepetTheme.accentBlue)
                } else {
                    Color.clear
                }
            }
            .frame(width: 14, height: 12)
        }
        .padding(.vertical, 1)
        .background(rowBackground)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture {
            guard let anchor = line.commentAnchor else { return }
            onComment?(anchor)
        }
    }

    @ViewBuilder private func number(_ value: Int?) -> some View {
        Text(value.map(String.init) ?? "")
            .font(.system(size: 10, design: .monospaced))
            .foregroundColor(CodepetTheme.mutedText.opacity(0.7))
            .frame(width: gutter, alignment: .trailing)
            .padding(.trailing, 4)
    }

    private var marker: String {
        switch line.kind {
        case .added: return "+"
        case .removed: return "−"
        case .context, .hunk: return " "
        }
    }

    private var markerColour: Color {
        switch line.kind {
        case .added: return CodepetTheme.accentTeal
        case .removed: return CodepetTheme.accentGold
        case .context, .hunk: return CodepetTheme.mutedText
        }
    }

    private var textColour: Color {
        // A hunk header is a jump in the file, not code — muted so the eye skips
        // it rather than reading it as a line that changed.
        line.kind == .hunk ? CodepetTheme.mutedText : CodepetTheme.bodyText
    }

    /// Colour carries WHICH KIND of change, never whether it is good. Added is
    /// teal and removed is gold rather than green-and-red: a deletion is not an
    /// error, and red on every removed line makes a normal refactor read as a
    /// screen full of problems.
    private var rowBackground: Color {
        switch line.kind {
        case .added: return CodepetTheme.accentTeal.opacity(0.10)
        case .removed: return CodepetTheme.accentGold.opacity(0.10)
        case .hunk: return CodepetTheme.mutedText.opacity(0.06)
        case .context: return .clear
        }
    }
}

#if DEBUG
#Preview("Diff lines") {
    VStack(alignment: .leading, spacing: 0) {
        ForEach(DiffPatch.parse("""
        @@ -10,3 +10,4 @@
         const cart = useCart()
        -const total = 0
        +const total = cart.sum()
        +const tax = total * 0.2
         return { total }
        """)) { line in
            DiffLineView(line: line, onComment: { _ in })
        }
    }
    .padding()
    .frame(width: 520)
}
#endif

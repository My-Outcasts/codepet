import SwiftUI

struct DictionaryCard: View {

    @Environment(\.uiLanguage) private var uiLanguage

    let term: DictionaryTerm
    let isExpanded: Bool
    let onToggleExpand: () -> Void

    /// The active/most-recent project's inferred stack + name, computed once by
    /// `DictionaryView` and passed down so cards don't re-infer per render.
    var projectTags: Set<ProjectTag> = []
    var projectName: String? = nil

    @State private var hovering = false

    private var usedInProject: String? {
        guard let projectName else { return nil }
        return DictionaryMatcher.projectUsing(term, projectTags: projectTags, projectName: projectName)
    }

    /// The card's color — its topic's brand color, so every card in a topic
    /// shares one consistent, category-coded hue.
    private var accentColor: Color {
        DictionaryContent.accent(forTopicId: term.topicId).color
    }

    /// First letter of the term — a per-term monogram so cards in a category
    /// aren't visually identical (replaces the repeated topic icon).
    private var monogram: String {
        let t = term.title(uiLanguage).trimmingCharacters(in: .whitespacesAndNewlines)
        return String(t.prefix(1)).uppercased()
    }

    var body: some View {
        PixelCard(fill: accentColor.opacity(0.07), borderColor: accentColor,
                  shadowOffset: 2, blockSize: 2, steps: 2, borderWidth: 2) {
            VStack(alignment: .leading, spacing: 10) {
                header

                Text(markdown: term.cardDefinition(uiLanguage))
                    .font(CodepetTheme.body(14))
                    .foregroundColor(CodepetTheme.bodyText)
                    .lineLimit(isExpanded ? nil : 3)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if isExpanded {
                    deepDive
                        .transition(.opacity)
                }

                Spacer(minLength: 10)
                footer
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        // Subtle hover lift for interactivity.
        .offset(y: hovering ? -3 : 0)
        .shadow(color: hovering ? accentColor.opacity(0.28) : .clear, radius: 8, x: 0, y: 5)
        .contentShape(Rectangle())
        .onTapGesture {
            // Tap anywhere to expand; once open, only the footer collapses so
            // the code block inside stays selectable.
            if !isExpanded { onToggleExpand() }
        }
        .onHover { hovering = $0 }
        .animation(.easeInOut(duration: 0.18), value: hovering)
        .animation(.easeInOut(duration: 0.22), value: isExpanded)
    }

    // MARK: - Header (monogram + title)

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            Text(monogram)
                .font(.pixelSystem(size: 15, weight: .bold))
                .foregroundColor(.white)
                .frame(width: 32, height: 32)
                .pixelBox(fill: accentColor, shadowOffset: 2, blockSize: 2, steps: 1, borderWidth: 2)

            Text(term.title(uiLanguage))
                .font(CodepetTheme.body(16, weight: .bold))
                .foregroundColor(CodepetTheme.primaryText)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
        }
    }

    // MARK: - Footer (used-in badge + lightweight expand control)

    private var footer: some View {
        HStack(spacing: 6) {
            if let project = usedInProject {
                usedInBadge(project)
            }
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
                .foregroundColor(accentColor)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    private func usedInBadge(_ project: String) -> some View {
        let tint = techTagColor(projectTagLabels(Set(term.tags)).first ?? "")
        return HStack(spacing: 4) {
            Image(systemName: "shippingbox.fill")
                .font(.system(size: 8, weight: .bold))
            Text(uiLanguage == .vi ? "Dùng trong \(project)" : "Used in \(project)")
                .font(.pixelSystem(size: 10, weight: .semibold))
                .lineLimit(1)
        }
        .foregroundColor(tint)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Capsule().fill(tint.opacity(0.14)))
    }

    // MARK: - Deep dive

    @ViewBuilder
    private var deepDive: some View {
        VStack(alignment: .leading, spacing: 16) {
            section(title: uiLanguage == .vi ? "Hiểu sâu hơn" : "What it really means",
                    body: term.whatItReallyMeans(uiLanguage))

            if let diagram = term.diagram {
                VStack(alignment: .leading, spacing: 6) {
                    sectionLabel(uiLanguage == .vi ? "Hình dung" : "Picture it")
                    DictionaryDiagramView(spec: diagram)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 4)
                }
            }

            if let code = term.codeExample {
                VStack(alignment: .leading, spacing: 6) {
                    sectionLabel("Code")
                    Text(code)
                        .font(.system(size: 14, weight: .regular, design: .monospaced))
                        .foregroundColor(CodepetTheme.primaryText)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .pixelBox(
                            fill: Color(white: 0.96),
                            shadowOffset: 2,
                            blockSize: 2,
                            steps: 2,
                            borderWidth: 2
                        )
                }
            }

            if let when = term.whenToUse {
                section(title: uiLanguage == .vi ? "Khi nào dùng" : "When to use", body: when(uiLanguage))
            }
        }
        .padding(.top, 4)
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
                .fill(accentColor)
                .frame(width: 14, height: 4)
            Text(text.uppercased())
                .font(CodepetTheme.body(11, weight: .semibold))
                .tracking(1.2)
                .foregroundColor(CodepetTheme.bodyText)
        }
    }
}

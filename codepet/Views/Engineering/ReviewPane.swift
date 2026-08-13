import SwiftUI

/// The diff, and the three things about it that would otherwise be lies of
/// omission.
///
/// Layout follows this codebase's long-format rule: a fixed head, a scrolling
/// body, a fixed foot. A 60-file diff must scroll without the scope selector or
/// the totals sliding away — those are the controls you reach for *because* the
/// list is long.
struct ReviewPane: View {
    @ObservedObject var store: EngineeringRunStore
    /// Called when the founder picks a different scope, so the caller can refetch.
    var onScope: (ReviewScope) async -> Void

    @Environment(\.uiLanguage) private var lang
    @State private var scope: ReviewScope = .branch
    @State private var expanded: Set<String> = []
    @State private var loading = false

    private var hue: Color { CodepetTheme.accentBlue }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            head
            Divider()
            body_
            if let diff = store.diff, !diff.files.isEmpty {
                Divider()
                foot(diff)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task { await load(.branch) }
    }

    // MARK: - head: scope + totals, never scrolled away

    @ViewBuilder private var head: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                ForEach(ReviewScope.allCases, id: \.self) { option in
                    scopeButton(option)
                }
                Spacer(minLength: 8)
                if let diff = store.diff {
                    Text("+\(diff.additions) −\(diff.deletions)")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(CodepetTheme.mutedText)
                }
            }

            // Every warning the diff carries, rendered from ONE list so the set
            // that shows is the set a test can assert.
            ForEach(Self.warnings(for: store.diff), id: \.self) { warning in
                Text(Self.warningText(warning, lang: lang))
                    .font(CodepetTheme.inter(11))
                    .foregroundColor(CodepetTheme.accentGold)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - body: the only part that scrolls

    @ViewBuilder private var body_: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if loading {
                    message(lang == .vi ? "Đang tải diff…" : "Loading the diff…")
                } else if let failure = store.failure, store.diff == nil {
                    message(EngineeringResultBar.message(for: failure, lang: lang))
                } else if let diff = store.diff {
                    if diff.files.isEmpty {
                        message(lang == .vi
                                ? "Chưa có thay đổi nào trên nhánh này."
                                : "No changes on this branch yet.")
                    } else {
                        ForEach(diff.files) { file in fileRow(file) }
                    }
                } else {
                    message(lang == .vi ? "Chưa có gì để xem." : "Nothing to review yet.")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxHeight: .infinity)
    }

    /// Extracted from the `ForEach` above, and not for tidiness: with the
    /// selected-state ternaries inline, the Swift type-checker gave up on the
    /// whole expression ("unable to type-check in reasonable time"). Hoisting
    /// the weight and colour into plain `let`s is what makes it compile.
    @ViewBuilder private func scopeButton(_ option: ReviewScope) -> some View {
        let selected = scope == option
        let weight: Font.Weight = selected ? .semibold : .regular
        let colour: Color = selected ? hue : CodepetTheme.mutedText
        Button(Self.scopeLabel(option, lang: lang)) {
            Task { await load(option) }
        }
        .font(CodepetTheme.inter(11, weight: weight))
        .foregroundColor(colour)
        .buttonStyle(.plain)
        .disabled(loading)
    }

    @ViewBuilder private func message(_ text: String) -> some View {
        Text(text)
            .font(CodepetTheme.inter(12))
            .foregroundColor(CodepetTheme.mutedText)
            .fixedSize(horizontal: false, vertical: true)
            .padding(16)
    }

    @ViewBuilder private func fileRow(_ file: EngFileDiff) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                if expanded.contains(file.id) { expanded.remove(file.id) } else { expanded.insert(file.id) }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: expanded.contains(file.id) ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(CodepetTheme.mutedText)
                    // `path`, not `file`: a rename reads "old → new", so a
                    // renamed file does not look like one that appeared from
                    // nowhere.
                    Text(file.path)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(CodepetTheme.primaryText)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 8)
                    Text("+\(file.additions) −\(file.deletions)")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(CodepetTheme.mutedText)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 7)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if expanded.contains(file.id) {
                if file.isBinary {
                    // A binary file has no patch to show. Naming it is still
                    // information; an empty body would read as a bug.
                    Text(lang == .vi
                         ? "Tệp nhị phân — không hiển thị được nội dung."
                         : "Binary file — no text to show.")
                        .font(CodepetTheme.inter(11))
                        .foregroundColor(CodepetTheme.mutedText)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 8)
                } else {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(DiffPatch.parse(file.patch)) { line in
                            // `onComment` stays nil: the hit target exists, the
                            // action does not. Inline comments are v1.1.
                            DiffLineView(line: line)
                        }
                    }
                    .padding(.bottom, 6)
                }
            }
            Divider().opacity(0.4)
        }
    }

    // MARK: - foot: the file count, never scrolled away

    @ViewBuilder private func foot(_ diff: EngDiffSummary) -> some View {
        HStack(spacing: 8) {
            Text(Self.fileCountLabel(diff.files.count, lang: lang))
                .font(CodepetTheme.inter(11))
                .foregroundColor(CodepetTheme.mutedText)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - what the pane must admit

    /// A partial answer the founder would otherwise read as a complete one.
    ///
    /// A pure value rather than inline `if`s in the body, so a test can assert
    /// exactly which warnings show. Rendered warnings are otherwise unprovable:
    /// `ImageRenderer` gives pixels, not text, so deleting a banner from the
    /// view would leave every test green — and these two banners are precisely
    /// the difference between a partial diff and a misleading one.
    enum Warning: Equatable, Hashable {
        /// The founder asked for one turn and is looking at the whole branch.
        case scopeFellBack
        /// GitHub capped the compare; there are more files than listed.
        case truncated
    }

    static func warnings(for diff: EngDiffSummary?) -> [Warning] {
        guard let diff else { return [] }
        var found: [Warning] = []
        if diff.scopeFellBack { found.append(.scopeFellBack) }
        if diff.truncated { found.append(.truncated) }
        return found
    }

    static func warningText(_ warning: Warning, lang: AppLanguage) -> String {
        switch (warning, lang) {
        case (.scopeFellBack, .vi):
            return "Chưa ghi được mốc của lượt này — đang hiện toàn bộ nhánh."
        case (.scopeFellBack, _):
            return "This turn's starting point isn't recorded yet — showing the whole branch."
        case (.truncated, .vi):
            return "Danh sách bị cắt — còn nhiều tệp hơn thế này."
        case (.truncated, _):
            return "This list is cut short — there are more files than shown."
        }
    }

    // MARK: - copy + loading

    static func scopeLabel(_ scope: ReviewScope, lang: AppLanguage) -> String {
        switch (scope, lang) {
        case (.branch, .vi): return "Cả nhánh"
        case (.branch, _):   return "Branch"
        case (.turn, .vi):   return "Lượt gần nhất"
        case (.turn, _):     return "Last turn"
        }
    }

    static func fileCountLabel(_ count: Int, lang: AppLanguage) -> String {
        if lang == .vi { return "\(count) tệp" }
        return count == 1 ? "1 file" : "\(count) files"
    }

    private func load(_ option: ReviewScope) async {
        scope = option
        loading = true
        await onScope(option)
        loading = false
    }
}

#if DEBUG
#Preview("Review pane") {
    let store = EngineeringRunStore(runner: MockEngineeringRunner())
    return ReviewPane(store: store, onScope: { await store.loadDiff(scope: $0) })
        .environment(\.uiLanguage, .en)
        .frame(width: 620, height: 460)
}
#endif

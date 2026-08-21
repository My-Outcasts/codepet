// codepet/Views/Shell/TwoModeInspector.swift
import SwiftUI

/// The inspector — `rail │ work │ inspector`, spec §5, which had said "Not yet drawn".
///
/// Adopted from the reference the founder supplied (Codex desktop: the work on the
/// left, `Review` and a preview as tabs on the right). Two rules from the spec shape
/// everything here:
///
/// - **The conversation is never replaced by the thing it produced.** The first
///   prototype had to OVERLAY the pane to show a deliverable, which destroyed the
///   transcript and its live controls. This is a sibling column, never a cover.
/// - **Every output has two views**, and the link flips the SAME panel between them
///   rather than opening a second tab. A diff and "what the diff did" are one object
///   seen two ways, not two objects.
struct TwoModeInspector: View {
    @Binding var tabs: InspectorTabs
    let diffs: [ClaudeCodeRunner.FileDiff]
    /// The branch the change is committed to, when there is one. Shown in the
    /// breadcrumb because "which branch" is half of what makes a diff safe to read.
    let branch: String?
    let projectName: String

    @Environment(\.uiLanguage) private var lang

    var body: some View {
        VStack(spacing: 0) {
            tabStrip
            if let tab = tabs.active {
                head(tab)
                Divider()
                ScrollView { body(tab).padding(14) }
            } else {
                empty
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(CodepetTheme.pageBackground)
        .overlay(alignment: .leading) {
            Rectangle().fill(CodepetTokens.cardEdge).frame(width: 1)
        }
    }

    // MARK: - Tabs

    private var tabStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(tabs.tabs) { tab in
                    let on = tab.id == tabs.active?.id
                    HStack(spacing: 7) {
                        Button { tabs.activate(tab.id) } label: {
                            Text(tab.title)
                                .font(CodepetTheme.inter(CodepetType.subheadline,
                                                         weight: on ? .semibold : .regular))
                                .foregroundStyle(on ? CodepetTheme.primaryText
                                                    : CodepetTheme.mutedText)
                                .lineLimit(1)
                        }
                        .buttonStyle(.plain)
                        Button { tabs.close(tab.id) } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(CodepetTokens.faint)
                        }
                        .buttonStyle(.plain)
                        .help(lang == .vi ? "Đóng" : "Close")
                    }
                    .padding(.horizontal, 9).padding(.vertical, 6)
                    .background(RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(on ? CodepetTokens.cardRaised : .clear))
                    .overlay(on ? RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .stroke(CodepetTokens.cardEdge) : nil)
                    .contentShape(Rectangle())
                }
            }
            .padding(.horizontal, 8).padding(.vertical, 7)
        }
        .background(CodepetTheme.surface)
    }

    /// Breadcrumb, then the link that flips the panel. Codex's shape exactly.
    private func head(_ tab: InspectorTab) -> some View {
        HStack(spacing: 10) {
            Text(crumb(tab))
                .font(CodepetTheme.inter(CodepetType.footnote))
                .foregroundStyle(CodepetTokens.faint)
                .lineLimit(1).truncationMode(.head)
            Spacer(minLength: 8)
            Button { tabs.flip() } label: {
                Text(tab.view == .source
                     ? (lang == .vi ? "Xem kết quả" : "View result")
                     : (lang == .vi ? "Xem nguồn" : "View source"))
                    .font(CodepetTheme.inter(CodepetType.subheadline))
                    .foregroundStyle(CodepetTheme.accentPurple)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(lang == .vi ? "Cùng một kết quả, hai cách xem"
                              : "One output, two views")
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(CodepetTheme.surface)
    }

    private func crumb(_ tab: InspectorTab) -> String {
        var parts = [projectName]
        if let branch { parts.append(branch) }
        parts.append(diffs.count == 1
                     ? (lang == .vi ? "1 tệp" : "1 file")
                     : (lang == .vi ? "\(diffs.count) tệp" : "\(diffs.count) files"))
        return parts.joined(separator: "  /  ")
    }

    // MARK: - Bodies

    @ViewBuilder private func body(_ tab: InspectorTab) -> some View {
        switch (tab.kind, tab.view) {
        case (.review, .source), (.files, .source):
            diffBody
        case (.review, .result):
            resultBody
        case (.files, .result):
            fileList
        }
    }

    /// The diff. Monospaced, with the line numbers the founder needs to find the
    /// change in their own editor — the file viewer is read-only on purpose (§2.4:
    /// not an IDE), so the numbers ARE the handoff.
    private var diffBody: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(diffs) { diff in
                VStack(alignment: .leading, spacing: 0) {
                    Text(diff.fileName)
                        .font(CodepetTheme.inter(CodepetType.subheadline, weight: .semibold))
                        .foregroundStyle(CodepetTheme.primaryText)
                        .padding(.bottom, 6)
                    ForEach(Array(diff.lines.enumerated()), id: \.offset) { i, line in
                        HStack(alignment: .top, spacing: 8) {
                            Text("\(i + 1)")
                                .foregroundStyle(CodepetTokens.faint)
                                .frame(width: 26, alignment: .trailing)
                            Text(prefix(line.kind) + line.text)
                                .foregroundStyle(ink(line.kind))
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .font(.system(size: CodepetType.subheadline, design: .monospaced))
                        .padding(.vertical, 1).padding(.horizontal, 4)
                        .background(tint(line.kind))
                    }
                }
            }
        }
    }

    private func prefix(_ kind: ClaudeCodeRunner.FileDiff.LineKind) -> String {
        switch kind {
        case .added: return "+ "
        case .removed: return "− "
        case .context: return "  "
        }
    }
    private func ink(_ kind: ClaudeCodeRunner.FileDiff.LineKind) -> Color {
        switch kind {
        case .added: return CodepetTheme.accentGreen
        case .removed: return CodepetTheme.accentOrange
        case .context: return CodepetTheme.mutedText
        }
    }
    private func tint(_ kind: ClaudeCodeRunner.FileDiff.LineKind) -> Color {
        switch kind {
        case .added: return CodepetTheme.accentGreen.opacity(0.10)
        case .removed: return CodepetTheme.accentOrange.opacity(0.10)
        case .context: return .clear
        }
    }

    /// "Result" for a code change is what the change DID.
    ///
    /// Which the app cannot fully answer yet: nothing runs the founder's tests, so
    /// there is no verification to report. It states the facts it has and names the
    /// one it does not, rather than dressing a file count up as an outcome — the
    /// spec's own note is that "result = verification" for native code is a section
    /// the design still owes.
    private var resultBody: some View {
        let added = diffs.reduce(0) { $0 + $1.lines.filter { $0.kind == .added }.count }
        let removed = diffs.reduce(0) { $0 + $1.lines.filter { $0.kind == .removed }.count }
        return VStack(alignment: .leading, spacing: 12) {
            Text(lang == .vi ? "\(diffs.count) tệp đã đổi · +\(added) −\(removed)"
                             : "\(diffs.count) files changed · +\(added) −\(removed)")
                .font(CodepetTheme.inter(CodepetType.title3, weight: .semibold))
                .foregroundStyle(CodepetTheme.primaryText)
            ForEach(diffs) { diff in
                Text("· " + diff.fileName + (diff.isNewFile
                                             ? (lang == .vi ? "  (mới)" : "  (new)") : ""))
                    .font(CodepetTheme.inter(CodepetType.body))
                    .foregroundStyle(CodepetTheme.bodyText)
            }
            Rectangle().fill(CodepetTokens.cardEdge).frame(height: 1).padding(.top, 4)
            Text(lang == .vi
                 ? "Chưa chạy kiểm thử. Đây là những gì đã thay đổi, không phải bằng chứng nó đúng — hãy đọc diff trước khi duyệt."
                 : "No tests were run. This is what changed, not evidence that it works — read the diff before approving.")
                .font(CodepetTheme.inter(CodepetType.subheadline))
                .foregroundStyle(CodepetTheme.mutedText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var fileList: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(diffs) { diff in
                HStack(spacing: 8) {
                    Image(systemName: diff.isNewFile ? "doc.badge.plus" : "doc.text")
                        .font(.system(size: 11))
                        .foregroundStyle(CodepetTokens.faint)
                    Text(diff.fileName)
                        .font(CodepetTheme.inter(CodepetType.body))
                        .foregroundStyle(CodepetTheme.bodyText)
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private var empty: some View {
        Text(lang == .vi ? "Chưa có gì để xem." : "Nothing open.")
            .font(CodepetTheme.inter(CodepetType.subheadline))
            .foregroundStyle(CodepetTokens.faint)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

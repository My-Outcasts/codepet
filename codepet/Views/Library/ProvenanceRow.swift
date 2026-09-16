// codepet/Views/Library/ProvenanceRow.swift
import SwiftUI

/// "Ran on Claude Code" plus, when it would change anything, "Re-run on Codex".
///
/// Modelled on `EngineeringResultBar`'s worked row — run metadata, grey and quiet, above
/// the rule, because it is not the answer — and on `CopilotChatView`'s `onRunLocally`,
/// which is offered only when `localBuildAvailable`. Same sentence, different noun.
///
/// Kept as static functions, not view logic, so a test can call them directly without
/// standing up a `@MainActor` store — see landmine 3 in CLAUDE.md.
enum ProvenanceRow {

    /// What ran, in the founder's language. Reads the deliverable's OWN stamp — never
    /// re-derived from what is installed or granted now, which would relabel old work
    /// every time the founder changes providers.
    static func text(for provider: AIProvider, lang: AppLanguage) -> String {
        let name = provider.displayName
        return lang == .vi ? "Chạy trên \(name)" : "Ran on \(name)"
    }

    /// The provider to offer a re-run on, or nil when there is nothing worth offering.
    /// An offer that changes nothing must not appear — mirrors `localBuildAvailable`.
    static func offer(producedBy: AIProvider, otherInstalled: Bool) -> AIProvider? {
        guard otherInstalled else { return nil }
        return producedBy == .claudeCode ? .codex : .claudeCode
    }

    static func offerText(_ provider: AIProvider, lang: AppLanguage) -> String {
        lang == .vi ? "Chạy lại trên \(provider.displayName)"
                    : "Re-run on \(provider.displayName)"
    }
}

/// The rendered row: provenance text, plus a trailing re-run button when `onReRun` is set
/// and `offer` names a provider worth offering. Renders nothing for a `nil` provenance —
/// never a guess, never a default to Claude Code.
struct ProvenanceRowView: View {
    let producedBy: AIProvider
    let lang: AppLanguage
    var otherInstalled: Bool = false
    var onReRun: ((AIProvider) -> Void)? = nil

    var body: some View {
        HStack(spacing: 8) {
            Text(ProvenanceRow.text(for: producedBy, lang: lang))
                .font(CodepetTheme.inter(12))
                .foregroundColor(CodepetTheme.mutedText)
            Spacer(minLength: 8)
            if let onReRun,
               let target = ProvenanceRow.offer(producedBy: producedBy, otherInstalled: otherInstalled) {
                Button {
                    onReRun(target)
                } label: {
                    Text(ProvenanceRow.offerText(target, lang: lang))
                        .font(CodepetTheme.inter(12))
                }
                .buttonStyle(.plain)
                .foregroundColor(CodepetTheme.mutedText)
            }
        }
    }
}

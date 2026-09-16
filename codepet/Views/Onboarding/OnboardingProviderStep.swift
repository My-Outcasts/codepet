// codepet/Views/Onboarding/OnboardingProviderStep.swift
import SwiftUI
import AppKit

/// Onboarding's CLI gate. **Installation only — never consent.**
///
/// Nothing in this product can run without a CLI the founder already pays for: Claude
/// Code, or Codex. Today onboarding never says so, and a founder with neither installed
/// reaches the app and finds every card blocked with no idea why. That is the gap this
/// closes — and only that gap. An earlier phase deferred the whole gate pending a design
/// decision, made now: **installation is a fact and can be detected here; consent is a
/// decision and is asked for later**, on the deliverable card, at the moment a plan would
/// actually be spent (`ProviderConsentFlow`, `ClaudeCodePanel`'s grant rows). Asking a
/// founder to authorise spending before she has seen Codepet do anything is a bad trade
/// for both sides, which is why this screen has no toggle at all.
///
/// **One provider is enough, never both.** A founder who pays OpenAI and not Anthropic
/// is a complete founder; a gate that demanded both would be telling her to buy a
/// competitor's product on the way in the door.
///
/// Kept as a static function outside any `@MainActor ObservableObject` — landmine 3 in
/// CLAUDE.md, the XCTest host crash on Xcode 26.2 — so a test exercises it directly with
/// no SwiftUI, no view, no store. Modelled on `ProvenanceRow` and `ProviderGrantRow` for
/// the same reason.
enum OnboardingProviderStep {
    /// Codepet needs ONE way to run a model, not a preferred one.
    static func passes(installed: Set<AIProvider>) -> Bool { !installed.isEmpty }
}

/// The gate screen. Rendered inside the onboarding card's existing chrome (art panel,
/// progress bar, footer) at the reveal step, rather than as a numbered step of its own —
/// see `OnboardingView.awaitingProvider`'s doc comment for why.
///
/// One row per provider, in the states `ClaudeCodePanel` already models — not installed
/// (with a copyable install command), installed but not signed in, signed in — but with
/// **no toggle**. Sign-in is shown only because it is a fact worth telling her; it never
/// gates `passes`, which reads installation alone.
struct OnboardingProviderGateView: View {
    let status: [AIProvider: CLIStatus]
    let probing: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("One more thing before you start")
                .font(CodepetTheme.body(20, weight: .semibold))
                .foregroundColor(CodepetTheme.primaryText)
            Text("Codepet runs every task on a CLI you already have — Claude Code, or Codex. Install either one; you'll choose whether to use it later.")
                .font(CodepetTheme.body(14)).foregroundColor(CodepetTheme.bodyText)
                .padding(.top, 9)

            VStack(alignment: .leading, spacing: 14) {
                ForEach(AIProvider.allCases, id: \.self) { provider in
                    row(for: provider)
                }
            }
            .padding(.top, 20)
        }
    }

    @ViewBuilder private func row(for provider: AIProvider) -> some View {
        let s = status[provider] ?? .unprobed(provider)
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                statusDot(for: s)
                Text(provider.displayName)
                    .font(CodepetTheme.body(14, weight: .semibold))
                    .foregroundColor(CodepetTheme.primaryText)
                Spacer()
                Text(stateLabel(for: s))
                    .font(CodepetTheme.body(12))
                    .foregroundColor(CodepetTheme.mutedText)
            }
            if s.install == .missing {
                installBox(for: provider)
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12).fill(OnboardingContent.Palette.surface2))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(CodepetTheme.hairline, lineWidth: 1))
    }

    @ViewBuilder private func statusDot(for s: CLIStatus) -> some View {
        Circle()
            .fill(s.install == .missing ? OnboardingContent.Palette.faint : CodepetTheme.accentTeal)
            .frame(width: 8, height: 8)
    }

    /// Named from install + auth directly — never from `CLIStatus.blocker`, which folds
    /// in `authorised` (always `false` here, since onboarding asks for no grant and would
    /// otherwise misreport a signed-in founder as blocked on "authorise").
    private func stateLabel(for s: CLIStatus) -> String {
        if probing && s.install == .missing { return "Checking…" }
        switch s.install {
        case .missing:
            return "Not installed"
        case .present:
            switch s.auth {
            case .loggedIn: return "Signed in"
            case .loggedOut: return "Installed — not signed in"
            case .unknown: return "Installed"
            }
        }
    }

    @ViewBuilder private func installBox(for provider: AIProvider) -> some View {
        let command = installCommand(for: provider)
        VStack(alignment: .leading, spacing: 6) {
            Text(command)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(CodepetTheme.bodyText)
                .textSelection(.enabled)
                .padding(.horizontal, 10).padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 8).fill(CodepetTheme.pageBackground))
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(command, forType: .string)
            } label: {
                Text("Copy command")
                    .font(CodepetTheme.body(11.5, weight: .medium))
                    .foregroundColor(OnboardingContent.Palette.accentDeep)
            }
            .buttonStyle(.plain)
        }
    }

    /// **Claude Code** — same command as `ClaudeCodePanel`'s install group.
    /// **Codex** — `brew install codex`, a Homebrew **cask** (verified on a real machine:
    /// it links to `/opt/homebrew/bin/codex` on Apple silicon). The npm global route
    /// (`npm install -g @openai/codex`) failed with EACCES on that same machine, so it is
    /// deliberately not offered as the primary instruction.
    private func installCommand(for provider: AIProvider) -> String {
        switch provider {
        case .claudeCode: return "curl -fsSL https://claude.ai/install.sh | bash"
        case .codex:      return "brew install codex"
        }
    }
}

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
    ///
    /// **Cannot write a grant, by construction, not by convention.** This is a pure
    /// static function on a `Set<AIProvider>` — no store parameter, no `ProviderAuthorisation`
    /// in scope, no global it could reach around its own signature. There is nothing here
    /// for a "never writes a grant" test to catch: any such test can only assert on a
    /// `FakeAuthStore` this function never sees, which passes whether or not `passes` is
    /// even called (this is exactly what shipped once, as `testOnboardingWritesNoGrant` —
    /// deleted, because a test that cannot fail is worse than no test). The real guard
    /// against onboarding writing a grant lives at the call sites in `OnboardingView`
    /// (`attemptFinish`, `recheckProviderAndFinishIfReady`, `refreshProviderStatus`,
    /// `finish()`): none of them holds a `ProviderAuthorisation`, and `CLIEnvironment.probe`
    /// is called there with `authorised: false` hardcoded, never read from a store.
    static func passes(installed: Set<AIProvider>) -> Bool { !installed.isEmpty }

    /// The gate's subtitle.
    ///
    /// It used to end "you'll choose whether to use it later", which is not true — without a
    /// grant nothing in the product runs, so the later moment is a delay rather than a choice.
    /// What IS true is that nothing is spent until she is asked, which is the promise this
    /// screen can actually keep (`ProviderConsentFlow`, and the grant button on a blocked card).
    ///
    /// Moved off the view for the same reason `passes` lives here: a string inside a SwiftUI
    /// `body` can only be asserted by building the view.
    /// The gate's heading, beside `gateSubtitle` so both follow the language. It was a literal
    /// until CP-012, which put English above Vietnamese body copy.
    static func gateHeading(lang: AppLanguage) -> String {
        lang == .vi ? "Còn một bước nữa trước khi bắt đầu" : "One more thing before you start"
    }

    /// The install row's copy button — the same literal-string bug on the same screen (CP-012).
    static func copyCommandLabel(lang: AppLanguage) -> String {
        lang == .vi ? "Sao chép lệnh" : "Copy command"
    }

    /// A provider row's state, per language. These were literals too — the render of the merged
    /// CP-012 fix still read "Not installed" on both rows of the Vietnamese gate.
    static func stateLabel(install: CLIStatus.Install, auth: CLIStatus.Auth, probing: Bool,
                           lang: AppLanguage) -> String {
        let vi = lang == .vi
        if probing && install == .missing { return vi ? "Đang kiểm tra…" : "Checking…" }
        switch install {
        case .missing:
            return vi ? "Chưa cài" : "Not installed"
        case .present:
            switch auth {
            case .loggedIn: return vi ? "Đã đăng nhập" : "Signed in"
            case .loggedOut: return vi ? "Đã cài — chưa đăng nhập" : "Installed — not signed in"
            case .unknown: return vi ? "Đã cài" : "Installed"
            }
        }
    }

    static func gateSubtitle(lang: AppLanguage) -> String {
        lang == .vi
            ? "Codepet chạy mọi việc trên CLI bạn đã có — Claude Code hoặc Codex. Hãy cài một trong hai; Codepet sẽ hỏi bạn trước khi dùng tới hạn mức của bạn."
            : "Codepet runs every task on a CLI you already have — Claude Code, or Codex. Install either one; Codepet will ask before it spends your plan."
    }
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

    @Environment(\.uiLanguage) private var lang

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(OnboardingProviderStep.gateHeading(lang: lang))
                .font(CodepetTheme.body(20, weight: .semibold))
                .foregroundColor(CodepetTheme.primaryText)
            Text(OnboardingProviderStep.gateSubtitle(lang: lang))
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
        OnboardingProviderStep.stateLabel(install: s.install, auth: s.auth, probing: probing, lang: lang)
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
                Text(OnboardingProviderStep.copyCommandLabel(lang: lang))
                    .font(CodepetTheme.body(11.5, weight: .medium))
                    .foregroundColor(OnboardingContent.Palette.accentDeep)
            }
            .buttonStyle(.plain)
        }
    }

    /// Reads `AIProvider.installCommand` — the one shared copy, so this screen and
    /// `ClaudeCodePanel` can never drift onto two different install commands.
    private func installCommand(for provider: AIProvider) -> String {
        provider.installCommand
    }
}

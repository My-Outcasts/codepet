import Foundation

/// Which CLI — and therefore which of the founder's plans — ran a model call.
///
/// **This is a name, not a switch.** Codepet spends no API key of its own: every model call
/// runs on something the founder already pays for. Until now `Transport.local` carried
/// nothing, so a run that had already happened could not say what paid for it — and with a
/// second CLI arriving (the TypeScript side already routes both behind `CliAdapter`) "local"
/// stopped being an answer. Recording the provider is what lets a run, a log line, or a
/// receipt name the plan.
///
/// **Nothing here selects a provider.** The routers derive it from the grant that exists;
/// per-provider consent, and the choosing that follows from it, is a separate piece of work.
/// Adding a case to this enum therefore does not make that provider reachable — it makes it
/// nameable, which is the smaller and earlier thing.
///
/// `String`-backed because the value is PERSISTED and wire-encoded: the raw values are the
/// stored form and are pinned by test. `CaseIterable` because a later chooser has to
/// enumerate them, and a provider that exists but is not listed is unreachable there.
enum AIProvider: String, CaseIterable, Equatable {
    /// Anthropic's `claude` CLI. The only provider any Swift path can reach today.
    case claudeCode
    /// OpenAI's `codex` CLI. Nameable here; not yet reachable from any router.
    case codex

    /// What the SIDECAR must be handed, which is **not** `rawValue`.
    ///
    /// `oneShotSidecar`'s `adapterFor` accepts exactly `undefined`, `""`, `"claude"` or
    /// `"codex"`, and THROWS on anything else — so a Claude run handed `"claudeCode"` does not
    /// quietly fall back, it fails outright. That is precisely what shipped for one commit:
    /// `rawValue` was passed as the wire word on the assumption the two vocabularies matched.
    ///
    /// They are separate on purpose and must stay separate. `rawValue` is the PERSISTED form,
    /// pinned by test; this is the CLI's word. Changing either must not silently change the
    /// other, and each is pinned on both sides of the boundary — the Swift test asserts the
    /// string the sidecar accepts, and the sidecar's own test asserts the string Swift sends.
    var cliName: String {
        switch self {
        case .claudeCode: return "claude"
        case .codex: return "codex"
        }
    }

    /// What the founder is shown. **Never the raw value** — she did not pick `claudeCode`,
    /// she picked a product, and the credit line on a run has to read like the product's name.
    var displayName: String {
        switch self {
        case .claudeCode: return "Claude Code"
        case .codex: return "Codex"
        }
    }

    /// The one command shown to install this provider's CLI. A fact about the provider,
    /// not about a screen — hoisted here so `OnboardingProviderStep` and `ClaudeCodePanel`
    /// read the same string instead of each hardcoding its own copy. Two copies is how a
    /// future installer change updates one screen and quietly leaves the other telling
    /// founders to run a stale command.
    ///
    /// **Codex** is `brew install codex`, a Homebrew **cask** — verified on a real
    /// machine, where it links to `/opt/homebrew/bin/codex` on Apple silicon. The npm
    /// global route (`npm install -g @openai/codex`) failed with EACCES on that same
    /// machine, so it is deliberately never offered.
    var installCommand: String {
        switch self {
        case .claudeCode: return "curl -fsSL https://claude.ai/install.sh | bash"
        case .codex:      return "brew install codex"
        }
    }
}

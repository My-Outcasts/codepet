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

    /// What the founder is shown. **Never the raw value** — she did not pick `claudeCode`,
    /// she picked a product, and the credit line on a run has to read like the product's name.
    var displayName: String {
        switch self {
        case .claudeCode: return "Claude Code"
        case .codex: return "Codex"
        }
    }
}

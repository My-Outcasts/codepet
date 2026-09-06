import Foundation

/// The founder's grant: "Codepet may spend my Claude plan."
///
/// **Why this exists at all.** A Mac has exactly ONE Claude Code login, in the
/// Keychain under `Claude Safe Storage`, and `claude` neither knows nor cares which
/// process spawned it. So the moment Codepet can find that login, it can also spend
/// it — and before this flag, it announced itself as "connected" to a founder who
/// had never agreed to anything. They had signed into Claude Code in a terminal,
/// possibly months earlier, for entirely unrelated reasons.
///
/// That is a consent gap, not a bug: the code did what it was asked. This is the
/// missing step. Nothing spends the founder's plan until they say so here.
///
/// **Keyed per company, never device-global** — the same reasoning
/// `VirtualCompanyInterviewFlag` records, and it bites harder here. One Mac has one
/// Claude Code login, so a device-global grant would mean founder A's consent
/// silently authorises founder B to spend the plan A signed in with. B never agreed,
/// and B is exactly the person who would never be asked.
///
/// The `cp_` prefix puts the key in the set `AccountDataStore` snapshots per uid on
/// an account switch; the company suffix keeps it correct even if some future switch
/// path forgets to go through that vault.
///
/// Closures rather than direct `UserDefaults` reads, like every other I/O seam
/// injected into `CompanyStore`, so tests never touch the real defaults domain and
/// cannot leak a grant between cases.
///
/// **Amendment 6 Sep — `CODEPET_LIVE_AI` is a second, narrower grant, not a bypass of
/// this one.** Prototype mode's live-transport switch (`PrototypeMode.liveAI`, see its
/// doc comment) runs the demo on the founder's own Claude plan instead of `MockChat`'s
/// fixtures. That still spends the plan, so it still needs a "yes" — but the founder
/// gave that yes on the command line, deliberately, the moment they typed the flag.
/// `-CODEPET_LIVE_AI` IS the grant, in exactly the sense this file's opening paragraph
/// requires: it does not exist until they set it, it is per-launch (never persisted, so
/// it cannot outlive the session the way a stored `cp_claude_authorised_*` key would),
/// and it is scoped to `ContentView.prototypeCompanyId` — the literal `"prototype"` —
/// and nothing else. Every real company id still resolves only from the stored
/// per-company grant below; this default closure is the ONLY place that reads
/// `PrototypeMode.liveAI`, so a real company can never pick up an implicit grant this
/// way, and the injected-closure seam a test supplies still overrides it completely.
struct ClaudeCodeAuthorisation {
    static func key(_ companyId: String) -> String { "cp_claude_authorised_\(companyId)" }

    /// Absent means NOT granted. `bool(forKey:)` returning false for a missing key is
    /// the behaviour we want, not an accident to work around: a founder who has never
    /// seen the toggle has never agreed.
    ///
    /// The `liveAI` check runs first and only ever ADDS an authorisation for the
    /// prototype id — it can never take one away, and it never runs for any other id,
    /// so a real company's stored grant (or lack of one) is untouched either way.
    var isAuthorised: (String) -> Bool = {
        if $0 == ContentView.prototypeCompanyId, PrototypeMode.liveAI { return true }
        return UserDefaults.standard.bool(forKey: key($0))
    }
    var setAuthorised: (String, Bool) -> Void = { UserDefaults.standard.set($1, forKey: key($0)) }
}

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
struct ClaudeCodeAuthorisation {
    static func key(_ companyId: String) -> String { "cp_claude_authorised_\(companyId)" }

    /// Absent means NOT granted. `bool(forKey:)` returning false for a missing key is
    /// the behaviour we want, not an accident to work around: a founder who has never
    /// seen the toggle has never agreed.
    var isAuthorised: (String) -> Bool = { UserDefaults.standard.bool(forKey: key($0)) }
    var setAuthorised: (String, Bool) -> Void = { UserDefaults.standard.set($1, forKey: key($0)) }
}

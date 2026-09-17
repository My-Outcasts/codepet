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
/// requires: it does not exist until they set it, and it is per-launch (never persisted,
/// so it cannot outlive the session the way a stored `cp_claude_authorised_*` key would).
///
/// **Amendment 2, 6 Sep — the exception is keyed on PROTOTYPE MODE, not on a literal id.**
/// This was first written as `$0 == ContentView.prototypeCompanyId, PrototypeMode.liveAI`,
/// on the assumption that prototype mode always hydrates under that literal string. It
/// does — but ONLY while nobody is signed in (`ContentView.prototypeStandIn` requires
/// `!signedIn`). A founder who is actually signed in and flips prototype mode on from
/// inside the running app (`PrototypeModeToggle`, no sign-out involved) keeps her REAL
/// uid as `companyId` the entire time. Under the literal-id check, her `-CODEPET_LIVE_AI`
/// consent — or the in-app toggle's runtime equivalent — silently granted nothing: the
/// grant checked an id prototype mode wasn't using, `transport()` fell through to
/// `.cloud`, and the founder's own signed-in token made the Cloud Function call actually
/// go out and 401 (the API key was deleted 26 Aug), instead of failing at the offline
/// guard the literal-id version was supposed to hit. Same dead-end this file's opening
/// paragraph describes for a missing grant, reached from the opposite direction: a grant
/// that exists but is keyed to an id nobody is using.
///
/// The fix asks the actual question — "is this prototype mode's live-AI switch on?" —
/// rather than "does this specific id match a literal string prototype mode sometimes
/// uses." `PrototypeMode.isOn` is still required alongside `liveAI` (see that property's
/// own doc comment: `liveAI` is meaningless with every `launchKeys` flag off, since
/// nothing schedules a call for it to swap), so this still cannot fire for a founder who
/// never turned prototype mode on at all — it only widens WHICH id it fires for once she
/// has.
///
/// This is still not a device-global bypass. It is gated on a mode + flag that, once on,
/// answers true for every id a `CompanyStore` in this process could possibly carry — but
/// `PrototypeMode.allowsCloudWrites` is false for that entire duration, so there is no
/// path from this to a real company document; the only thing "authorised" changes here
/// is which TRANSPORT a call takes, never what gets persisted. A real company's stored
/// grant is untouched either way: with prototype mode off, this branch never runs, full
/// stop, and the stored check below is the only answer, exactly as before this amendment.
///
/// **Amendment 16 Sep — the grant is per PROVIDER, and it is never inherited.**
/// A second CLI arrived (`codex`, spending the founder's ChatGPT plan), and one switch for
/// two plans is the consent gap this file's opening paragraph describes, one level up:
/// "Codepet may spend my Claude plan" says nothing about an OpenAI account. A founder who
/// granted Claude Code before this change was never asked about Codex, so she must be
/// ASKED — migrating her stored `true` into a second provider would spend money on an
/// account she never put on the table.
///
/// So the key gains the provider, and `cp_claude_authorised_<id>` — the string already on
/// founders' disks — stays byte-for-byte what it was. Renaming it would silently withdraw
/// every grant ever given and ask again for something already agreed to.
///
/// The type was renamed to `ProviderAuthorisation` in a follow-up task, kept separate from
/// this consent change so a rename could never hide a behaviour change inside it.
struct ProviderAuthorisation {
    /// **Written out per case, deliberately — never derived from `rawValue`.** These strings
    /// are PERSISTED on founders' machines. Deriving them would mean a future rename of an
    /// enum case silently relocates a stored grant, and the founder who gave it quietly
    /// loses it. The explicit switch also makes a new provider a COMPILE error rather than
    /// a case that quietly shares somebody else's key.
    static func key(_ provider: AIProvider, _ companyId: String) -> String {
        switch provider {
        case .claudeCode: return "cp_claude_authorised_\(companyId)"
        case .codex:      return "cp_codex_authorised_\(companyId)"
        }
    }

    /// Absent means NOT granted. `bool(forKey:)` returning false for a missing key is
    /// the behaviour we want, not an accident to work around: a founder who has never
    /// seen the toggle has never agreed. That now holds PER PROVIDER: a stored Claude
    /// grant reads `false` for `.codex`, because she was asked one question, not two.
    ///
    /// The `liveAI` check runs first and only ever ADDS an authorisation while prototype
    /// mode is on — it can never take one away, and it never runs at all with prototype
    /// mode off, so a real company's stored grant (or lack of one) is untouched either way.
    ///
    /// **It is scoped to `.claudeCode`, and that is the same rule, not a new one.**
    /// `-CODEPET_LIVE_AI` is the founder typing "spend my Claude plan on the demo" on the
    /// command line — that is the plan the flag has always meant and the only one she named.
    /// Letting it answer true for `.codex` would be exactly the inheritance the stored keys
    /// were just split to prevent, reached through the branch that bypasses storage.
    var isAuthorised: (AIProvider, String) -> Bool = { provider, companyId in
        if provider == .claudeCode, PrototypeMode.isOn, PrototypeMode.liveAI { return true }
        return UserDefaults.standard.bool(forKey: key(provider, companyId))
    }

    var setAuthorised: (AIProvider, String, Bool) -> Void = { provider, companyId, on in
        UserDefaults.standard.set(on, forKey: key(provider, companyId))
    }
}

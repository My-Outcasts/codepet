// codepet/Managers/VirtualCompanyInterviewFlag.swift
import Foundation

/// Remembers that the Virtual Company already asked a founder for runway and
/// constraints — **per company id**, never device-global.
///
/// Two reasons it is persisted rather than session-only:
///
/// 1. **Skip is a no-write path.** `answerInterview` only writes a non-empty answer,
///    and its skip semantics are shared with the onboarding interview another
///    engineer owns, so they are not ours to change. A founder who skipped therefore
///    has no `constraints` on record, and a session-only flag would ask them both
///    questions again on the first brief of every launch, forever.
/// 2. **A device-global flag leaks across accounts.** Sign out, sign in as someone
///    else, and founder B — with an empty brief and nothing on record — would never
///    be asked at all, because A's flag is still set.
///
/// Keying by company id fixes both. It also agrees with `AccountDataStore` rather
/// than fighting it: that vault snapshots every non-preserved `cp_*` key per uid on
/// an account switch, so `cp_vc_asked_<A>` is stored under A, cleared from the
/// working set, and restored when A signs back in. The suffix makes the flag correct
/// even if a future switch path forgets to go through the vault.
///
/// Injected into `CompanyStore` (like every other I/O seam there) so tests never
/// touch the real defaults domain and cannot leak asked-ness between cases.
struct VirtualCompanyInterviewFlag {
    static func key(_ companyId: String) -> String { "cp_vc_asked_\(companyId)" }

    var wasAsked: (String) -> Bool = { UserDefaults.standard.bool(forKey: key($0)) }
    var markAsked: (String) -> Void = { UserDefaults.standard.set(true, forKey: key($0)) }
}

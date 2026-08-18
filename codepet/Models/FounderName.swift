// codepet/Models/FounderName.swift
import Foundation

/// Who is signed in — one answer, from the two places the app can actually
/// learn it.
///
/// Six surfaces resolved this independently and gave five different answers for
/// the same unknown founder: the chat hero said "there", the two-mode rail said
/// "Founder", the account menu and Preferences said "You", the roadmap beacon
/// rewrote its sentence to "You are here", and the first-run greeting rewrote
/// its lead. In the two-mode shell two of those are on screen at once — the rail
/// reading `Founder` beside a hero reading `there` — which is exactly what
/// `TwoModeSidebar`'s own comment claims cannot happen.
///
/// It also meant a founder who signed in with Google was called "there" by an
/// app that already had their name: `AuthManager` captures Firebase's
/// `displayName` into `AppState.displayName` (`ContentView.swift:131`) and no
/// greeting ever read it.
enum FounderName {
    /// The founder's name, or `nil` when neither source has one.
    ///
    /// The brief wins: it is what the founder typed about their own company, and
    /// the account name is whatever their Google profile happens to say. Blank
    /// and whitespace-only both count as absent — a brief saved with a stray
    /// space is not a name.
    static func resolve(brief: CompanyBrief, accountName: String?) -> String? {
        for candidate in [brief.founderName, accountName] {
            let trimmed = (candidate ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
        }
        return nil
    }

    /// What to call them where a LABEL is required and a sentence cannot be
    /// rewritten — the rail's account row, the account menu.
    ///
    /// "You", which is what `AccountMenuView` and `PreferencesPanel` already say.
    /// Not "Founder": a role is not a name, and it reads as a placeholder that
    /// someone forgot to fill in.
    static func label(brief: CompanyBrief, accountName: String?, language: AppLanguage) -> String {
        resolve(brief: brief, accountName: accountName)
            ?? (language == .vi ? "Bạn" : "You")
    }

    /// A greeting. Named when we have one, and otherwise the clause is DROPPED
    /// rather than filled with a placeholder — "Good afternoon." is a complete
    /// greeting, where "Good afternoon, there." is a stock chatbot tic that makes
    /// the app sound like it is pretending to know you.
    ///
    /// This is the rule `herePhrase` and `FirstRunGreetingBuilder` already follow:
    /// when the name is missing, rewrite the sentence, never substitute a noun.
    static func greeting(part: String, brief: CompanyBrief, accountName: String?) -> String {
        guard let name = resolve(brief: brief, accountName: accountName) else { return "\(part)." }
        return "\(part), \(name)."
    }
}

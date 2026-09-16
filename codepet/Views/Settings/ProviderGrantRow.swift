// codepet/Views/Settings/ProviderGrantRow.swift
import Foundation

/// Which providers get a grant row in `ClaudeCodePanel`'s permission group.
///
/// Settings is where a grant is reviewed and revoked — so a provider must get a row
/// whenever there is something to review: either it is signed in right now, OR a grant
/// for it is already stored. Filtering on "signed in" alone (the original rule) makes a
/// stored grant invisible and unreachable the moment its CLI is signed out or
/// uninstalled — `CLIStatus.account` is non-nil only for `.loggedIn`, so a founder who
/// grants Codex and later signs out of it loses the only row that could revoke it, and
/// the toggle comes back ON, unreviewed, the moment she signs back in. See
/// `ClaudeCodePanel`'s doc comment on `rowsToShow` for the full defect this closes.
///
/// Probing never grants, and it must never revoke either — an unreachable CLI is not
/// evidence the founder changed her mind, so this filter only ever ADDS rows a
/// signed-in-only rule would have hidden. It never removes a row for a stored grant.
///
/// Kept as a static function outside any `@MainActor ObservableObject` — landmine 3 in
/// CLAUDE.md, the XCTest host crash on Xcode 26.2 — so a test exercises it directly with
/// no SwiftUI, no view, no store. Modelled on `ProvenanceRow` for the same reason.
enum ProviderGrantRow {
    static func rowsToShow(status: [AIProvider: CLIStatus], granted: Set<AIProvider>) -> [AIProvider] {
        AIProvider.allCases.filter { status[$0]?.account != nil || granted.contains($0) }
    }
}

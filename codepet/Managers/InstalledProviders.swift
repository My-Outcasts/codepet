import Foundation

/// Which CLIs are on this Mac, probed once rather than per render.
///
/// A stale-but-cheap answer is the right trade here: a founder who installs a CLI
/// mid-session sees the offer after the next refresh, and the alternative is a subprocess
/// every time a card draws. Settings and onboarding call `refresh()`; everything else reads
/// the cache.
@MainActor
final class InstalledProviders {
    private(set) var installed: Set<AIProvider> = []

    func refresh(shell: ShellRunning = LoginShellRunner()) async {
        var found: Set<AIProvider> = []
        for provider in AIProvider.allCases
        where await CLIEnvironment.probeInstall(provider: provider, shell: shell) != .missing {
            found.insert(provider)
        }
        installed = found
    }

    /// Updates the cache from `CLIStatus` a caller already probed, instead of running
    /// `probeInstall` a second time to get the same answer. `OnboardingView`'s
    /// "Check again" needs the full status (install + auth) per provider regardless —
    /// `CLIEnvironment.probe` runs `probeInstall` internally on the way to that — so
    /// calling `refresh()` first, only to re-derive the same install facts a moment
    /// later, doubled the subprocesses every tap spawned for no different answer.
    func apply(_ statuses: [AIProvider: CLIStatus]) {
        installed = Set(statuses.filter { $0.value.install != .missing }.keys)
    }
}

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
}

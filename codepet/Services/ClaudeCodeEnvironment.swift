import Foundation

/// What Codepet knows about the founder's Claude Code installation, as a value.
///
/// A struct and not an `ObservableObject`: landmine 3 in CLAUDE.md — the XCTest host on
/// Xcode 26.2 crashes when a `@MainActor ObservableObject` deallocates, and this type
/// exists to be built and thrown away in tests.
struct ClaudeCodeStatus: Equatable {

    enum Install: Equatable {
        case missing
        /// Reachable. `version` is "" when the binary answered but its version string
        /// did not parse — present-at-an-unknown-version, never `.missing`.
        case present(version: String)
    }

    /// The account `claude` is signed in as, when it is.
    struct Account: Equatable {
        let email: String?
        /// "claude.ai" for a subscription, "console" for API billing.
        let authMethod: String?
        /// "firstParty", or a cloud provider. Carried because it is how Codepet can tell
        /// an exported API key has quietly taken over the founder's runs.
        let apiProvider: String?
        /// "pro", "max", "team", … — how a model picker learns which models this
        /// founder's plan can actually reach, so one they cannot use is never offered.
        let subscriptionType: String?
        let orgName: String?
    }

    enum Auth: Equatable {
        /// Could not be determined — an older CLI without `auth status`, or output that
        /// did not parse. Deliberately distinct from `loggedOut`.
        case unknown
        case loggedOut
        case loggedIn(Account)
    }

    /// The single reason Codepet cannot run yet, in the order the founder must fix them.
    enum Blocker: Equatable {
        case notInstalled
        case notSignedIn
        /// Installed, and possibly signed in, but the CLI is too old to say. The fix is
        /// updating Claude Code, not signing in.
        case versionUnknown
    }

    /// Codepet works, but the founder may not be paying the way they think.
    /// Deliberately NOT a `Blocker`: these cases run fine.
    enum BillingWarning: Equatable {
        /// A credential outranking the subscription is in the environment despite the
        /// scrub — a login shell can re-export one from the founder's profile.
        case apiKeyInEnvironment
        /// Signed in with a Console account, so runs bill per token rather than being
        /// covered by a subscription.
        case consoleAccount
    }

    let install: Install
    let auth: Auth

    var blocker: Blocker? {
        if install == .missing { return .notInstalled }
        switch auth {
        case .loggedIn: return nil
        case .loggedOut: return .notSignedIn
        case .unknown: return .versionUnknown
        }
    }

    var isReady: Bool { blocker == nil }

    var billingWarning: BillingWarning? {
        guard case .loggedIn(let account) = auth else { return nil }
        if account.authMethod == "console" { return .consoleAccount }
        return nil
    }

    /// The account, when signed in — for surfaces that want the email or the plan.
    var account: Account? {
        if case .loggedIn(let account) = auth { return account }
        return nil
    }

    /// Nothing probed yet. Distinct from a probe that ran and found nothing.
    static let unprobed = ClaudeCodeStatus(install: .missing, auth: .unknown)
}

/// Probes the founder's Claude Code installation. A namespace, not an instance: it holds
/// no state, and every function takes the shell it should use.
enum ClaudeCodeEnvironment {

    /// Where the documented installers put `claude`, tried by absolute path when PATH
    /// resolution fails. A founder whose shell profile the installer never touched has
    /// the binary installed and invisible, and telling them to install software they
    /// already have is the specific wrong answer this avoids.
    static let knownInstallPaths = [
        "~/.local/bin/claude",        // native installer
        "/opt/homebrew/bin/claude",   // Homebrew on Apple silicon
        "/usr/local/bin/claude"       // Homebrew on Intel, or an npm global
    ]

    /// Is `claude` reachable, and at what version.
    ///
    /// Reads the leading semver out of `claude --version`, whose current shape is
    /// "2.1.241 (Claude Code)". Only when PATH resolution AND every known install path
    /// fail do we conclude `.missing`.
    static func probeInstall(shell: ShellRunning) async -> ClaudeCodeStatus.Install {
        let onPath = await shell.run("claude --version")
        if onPath.succeeded {
            return .present(version: parseVersion(onPath.trimmedOut))
        }
        for path in knownInstallPaths {
            let expanded = (path as NSString).expandingTildeInPath
            let direct = await shell.run("\"\(expanded)\" --version")
            if direct.succeeded {
                return .present(version: parseVersion(direct.trimmedOut))
            }
        }
        return .missing
    }

    /// Leading dotted-numeric run of a version line, or "" when there is none.
    static func parseVersion(_ output: String) -> String {
        var version = ""
        for ch in output {
            if ch.isNumber || ch == "." {
                version.append(ch)
            } else if version.isEmpty {
                continue        // skip any prefix before the digits start
            } else {
                break           // stop at the first character after the run
            }
        }
        // A trailing dot ("2.1." from odd input) is not part of the version.
        while version.hasSuffix(".") { version.removeLast() }
        return version
    }

    /// Whether `claude` is signed in, and as whom.
    ///
    /// `claude auth status --json` is machine-readable by design — `--json` is already
    /// its default, passed explicitly so a future default flip cannot silently start
    /// handing us prose. Three outcomes, and the difference between the last two is the
    /// point: signed-out is something the founder can act on, unknown is not their fault
    /// and needs a different message.
    static func probeAuth(shell: ShellRunning) async -> ClaudeCodeStatus.Auth {
        let result = await shell.run("claude auth status --json")
        // A non-zero exit is an older CLI without the subcommand, or a broken install.
        // Either way we do not know — and must not claim signed-out.
        guard result.succeeded,
              let data = result.trimmedOut.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let loggedIn = obj["loggedIn"] as? Bool
        else { return .unknown }

        guard loggedIn else { return .loggedOut }

        return .loggedIn(.init(
            email: obj["email"] as? String,
            authMethod: obj["authMethod"] as? String,
            apiProvider: obj["apiProvider"] as? String,
            subscriptionType: obj["subscriptionType"] as? String,
            orgName: obj["orgName"] as? String
        ))
    }

    /// Full preflight. Skips the auth probe when nothing is installed: asking a binary
    /// that is not there costs a spawn and yields a second, confusing not-found.
    static func probe(shell: ShellRunning = LoginShellRunner()) async -> ClaudeCodeStatus {
        let install = await probeInstall(shell: shell)
        guard install != .missing else {
            return ClaudeCodeStatus(install: install, auth: .unknown)
        }
        return ClaudeCodeStatus(install: install, auth: await probeAuth(shell: shell))
    }
}

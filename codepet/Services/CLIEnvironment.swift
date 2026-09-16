import Foundation

/// What Codepet knows about the founder's Claude Code installation, as a value.
///
/// A struct and not an `ObservableObject`: landmine 3 in CLAUDE.md — the XCTest host on
/// Xcode 26.2 crashes when a `@MainActor ObservableObject` deallocates, and this type
/// exists to be built and thrown away in tests.
struct CLIStatus: Equatable {

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
        /// Everything works; the founder just has not agreed to let Codepet spend their
        /// plan. Last in the order because being asked to authorise software that is not
        /// installed, or a login that does not exist, is an instruction nobody can follow.
        case notAuthorised
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

    let provider: AIProvider
    let install: Install
    let auth: Auth
    /// Whether the founder has agreed to let Codepet spend this plan. NOT a fact about
    /// the Mac — it is Codepet's own gate, and it is deliberately NOT defaulted: a
    /// defaulted permission is how `sendChat`'s `convenesRoom:` left eight tests red for
    /// a day, and this one guards the founder's money rather than a render path.
    let authorised: Bool

    var blocker: Blocker? {
        if install == .missing { return .notInstalled }
        switch auth {
        case .loggedOut: return .notSignedIn
        case .unknown: return .versionUnknown
        case .loggedIn: return authorised ? nil : .notAuthorised
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
    static func unprobed(_ provider: AIProvider = .claudeCode) -> CLIStatus {
        CLIStatus(provider: provider, install: .missing, auth: .unknown, authorised: false)
    }
}

/// What differs between one CLI and another. Everything else about probing is shared.
///
/// A struct of values rather than a protocol: the two providers differ only in strings and
/// in how one line of output is read, and a protocol would be a ceremony around a table.
/// This mirrors `CliAdapter` on the TypeScript side deliberately — same seam, same reason.
struct CLISpec {
    let binary: String
    /// Tried by absolute path only when PATH resolution fails. A founder whose shell
    /// profile the installer never touched has the binary installed and invisible, and
    /// telling them to install software they already have is the specific wrong answer.
    let knownInstallPaths: [String]
    /// The sub-command that answers "is this signed in", and how to read its answer.
    let authCommand: String
    let readAuth: (ShellResult) -> CLIStatus.Auth
}

/// Probes the founder's Claude Code installation. A namespace, not an instance: it holds
/// no state, and every function takes the shell it should use.
enum CLIEnvironment {

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
    ///
    /// Delegates to the per-provider probe so this and `probeInstall(provider:shell:)`
    /// cannot drift into two different notions of "installed".
    static func probeInstall(shell: ShellRunning) async -> CLIStatus.Install {
        await probeInstall(provider: .claudeCode, shell: shell)
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
    ///
    /// Delegates to the per-provider probe, same reason as `probeInstall(shell:)` above.
    static func probeAuth(shell: ShellRunning) async -> CLIStatus.Auth {
        await probeAuth(provider: .claudeCode, shell: shell)
    }

    /// Full preflight. Skips the auth probe when nothing is installed: asking a binary
    /// that is not there costs a spawn and yields a second, confusing not-found.
    ///
    /// `authorised` is passed in rather than read here, because it is not a fact about
    /// the machine — it is the founder's grant, which lives per company id and is the
    /// caller's to supply.
    ///
    /// Delegates to `probe(provider:shell:authorised:)`, same reason as the two probes above.
    static func probe(shell: ShellRunning = LoginShellRunner(),
                      authorised: Bool) async -> CLIStatus {
        await probe(provider: .claudeCode, shell: shell, authorised: authorised)
    }
}

extension CLIEnvironment {

    static func spec(for provider: AIProvider) -> CLISpec {
        switch provider {
        case .claudeCode:
            return CLISpec(
                binary: "claude",
                knownInstallPaths: knownInstallPaths,
                authCommand: "claude auth status --json",
                readAuth: readClaudeAuth
            )
        case .codex:
            // Homebrew ships Codex as a CASK, linked to /opt/homebrew/bin on Apple
            // silicon — verified on a real install, where the npm global route failed
            // with EACCES. /usr/local/bin is kept for Intel and a writable npm prefix.
            return CLISpec(
                binary: "codex",
                knownInstallPaths: ["/opt/homebrew/bin/codex",
                                    "/usr/local/bin/codex",
                                    "~/.local/bin/codex"],
                authCommand: "codex login status",
                readAuth: readCodexAuth
            )
        }
    }

    static func probeInstall(provider: AIProvider, shell: ShellRunning) async -> CLIStatus.Install {
        let spec = spec(for: provider)
        let onPath = await shell.run("\(spec.binary) --version")
        if onPath.succeeded { return .present(version: parseVersion(onPath.trimmedOut)) }
        for path in spec.knownInstallPaths {
            let expanded = (path as NSString).expandingTildeInPath
            let direct = await shell.run("\"\(expanded)\" --version")
            if direct.succeeded { return .present(version: parseVersion(direct.trimmedOut)) }
        }
        return .missing
    }

    static func probeAuth(provider: AIProvider, shell: ShellRunning) async -> CLIStatus.Auth {
        let spec = spec(for: provider)
        return spec.readAuth(await shell.run(spec.authCommand))
    }

    /// Claude answers in JSON, by design — `--json` is passed explicitly so a future
    /// default flip cannot silently start handing us prose.
    static func readClaudeAuth(_ result: ShellResult) -> CLIStatus.Auth {
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

    /// Codex answers in one prose line and reports NOTHING about the account -- no
    /// email, no plan type. Verified on the real binary: exit 0 "Logged in using
    /// ChatGPT", exit 1 "Not logged in". Keyed on the exit code with the string as
    /// corroboration, because an exit code cannot be reworded by a release note.
    ///
    /// The signed-OUT shape is checked FIRST, because "not logged in" contains
    /// "logged in" as a substring -- checking the signed-IN shape first would let an
    /// exit-0 response worded "Not logged in" match it and misreport `.loggedIn`. Once
    /// that shape is matched, the exit code corroborates: exit 1 confirms `.loggedOut`,
    /// while a mismatched exit code (never seen against the real CLI) means the text
    /// and the exit status disagree -- exactly what `.unknown` is for.
    ///
    /// An empty `Account` is the honest answer for signed-in-but-anonymous. Anything
    /// that matches neither shape -- or whose exit code contradicts the shape it
    /// matched -- is `.unknown`, never `.loggedOut`.
    static func readCodexAuth(_ result: ShellResult) -> CLIStatus.Auth {
        let out = result.trimmedOut.lowercased()
        if out.contains("not logged in") {
            return result.succeeded ? .unknown : .loggedOut
        }
        if result.succeeded, out.contains("logged in") {
            return .loggedIn(.init(email: nil, authMethod: nil, apiProvider: nil,
                                   subscriptionType: nil, orgName: nil))
        }
        return .unknown
    }

    static func probe(provider: AIProvider,
                      shell: ShellRunning = LoginShellRunner(),
                      authorised: Bool) async -> CLIStatus {
        let install = await probeInstall(provider: provider, shell: shell)
        guard install != .missing else {
            return CLIStatus(provider: provider, install: install,
                             auth: .unknown, authorised: authorised)
        }
        return CLIStatus(provider: provider, install: install,
                         auth: await probeAuth(provider: provider, shell: shell),
                         authorised: authorised)
    }
}

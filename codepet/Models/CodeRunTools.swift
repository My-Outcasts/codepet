import Foundation

/// Which tools a coding run may use — the one place the list lives, and pure so it is
/// testable without spawning `claude`.
///
/// **Why this type exists.** The list was a default argument on `ClaudeCodeRunner.run`, and
/// the comma-join that turns it into a shell argument sat next to the invocation. Neither was
/// reachable from a test, and the list had no way to grow with a founder's toolkit: a coding
/// run could not search the web no matter what Environment said.
///
/// **The `WebSearch` lesson, applied on purpose rather than by accident (7 Sep).** In the chat
/// sidecar, `--tools` made `WebSearch` available while `--allowedTools` never permitted it, so
/// every search was denied and the founder got an apology instead of an answer. This path is
/// different in an important way — it passes NO `--tools`, so `--allowedTools` is the only
/// gate — but the consequence is the same: a tool absent from this list is denied. So the
/// toggle has to reach here, or "Web research — Enabled" keeps meaning nothing on a coding run.
///
/// **This widens what a coding run can do, deliberately.** Unlike chat, nothing in the coding
/// UI ever promised search, so adding it is a capability change and not the repair of a broken
/// promise: a run that edits files may now also reach the network. It is opt-in — gated on the
/// founder's own `web-research` toolkit item — and the base list stays as scoped as it was.
enum CodeRunTools {

    /// What a coding run may always do. Deliberately narrow: this run edits a real project on
    /// the founder's disk, and `--allowedTools` is the only thing keeping it scoped.
    static let base = ["Edit", "Write", "Read", "Bash", "Glob", "Grep"]

    /// The base list, plus `WebSearch` when the founder has the `web-research` skill on.
    ///
    /// Appended rather than substituted — permitting the search must not un-permit the editing
    /// tools, which is the mistake the sidecar's allow-list made in the other direction.
    static func allowed(webSearch: Bool) -> [String] {
        webSearch ? base + ["WebSearch"] : base
    }

    /// The `--allowedTools` value as one shell argument.
    ///
    /// Comma-joined with NO spaces, and that is the contract: the invocation interpolates this
    /// inside quotes, so a stray space would be parsed as part of a tool name and silently
    /// deny that tool. Joining here rather than at the call site keeps the shape testable.
    static func argument(_ tools: [String]) -> String {
        tools.joined(separator: ",")
    }
}

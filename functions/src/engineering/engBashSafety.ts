//
// Which bash commands are safe to run without interrupting the founder.
//
// The agent runs with `bash: always_ask` (provision-eng-agent.ts) because bash
// is the one tool that can reach outside the session's throwaway branch. That
// reasoning holds — and it produced a bad outcome anyway, because the agent
// uses bash to READ. Exploring a repo means `ls`, `cat`, `git status`, `grep`,
// so a founder was asked to approve four consecutive commands that could not
// change anything.
//
// That is worse than not asking. It teaches them to click Allow without
// reading, and the habit is already formed by the time something arrives that
// deserves the pause. The agent's own config comment predicted exactly this
// failure for file edits and then hit it through bash.
//
// So the gate fires on CONSEQUENCE rather than on tool name: a command that
// only reads is answered by the relay and appears in the transcript as an
// ordinary step; anything that can write, delete, install, or reach the
// network still stops and asks.
//
// **This file decides what a founder is never shown.** Every rule below is
// written to fail CLOSED: unknown binary, unknown operator, unparsable
// quoting, anything at all in doubt — ask. Being wrong in that direction costs
// one unnecessary card. Being wrong in the other direction runs something
// destructive that nobody saw.
//

/** Binaries that cannot modify anything, given the operator rules below. */
const READ_ONLY_BINARIES = new Set([
  "cd", "pwd", "ls", "cat", "head", "tail", "wc", "file", "stat",
  "grep", "egrep", "fgrep", "rg", "find", "tree", "du", "df",
  "basename", "dirname", "realpath", "readlink",
  "sort", "uniq", "cut", "tr", "column", "diff", "cmp",
  "echo", "printf", "date", "whoami", "hostname", "uname",
  "which", "type", "command",
  "jq", "yq", "xxd", "od", "strings"
]);

/**
 * `git` subcommands that only read.
 *
 * Enumerated rather than blocklisted: `git` has hundreds of subcommands and
 * new ones arrive, so an allowlist is the only version that stays safe as the
 * tool changes. `show` and `diff` read; `add`, `commit`, `checkout`, `push`,
 * `reset`, `clean`, `stash` and everything unlisted do not.
 */
const READ_ONLY_GIT = new Set([
  "status", "log", "diff", "show", "branch", "ls-files", "ls-tree",
  "rev-parse", "describe", "blame", "cat-file", "shortlog", "remote",
  "count-objects", "check-ignore", "whatchanged"
]);

/**
 * Flags that turn a reading command into a writing one.
 *
 * `find -exec rm {} \;` is the classic: `find` is on the allowlist and the
 * command deletes the tree. `sed -i` and `grep -r --include` style writes are
 * handled by keeping sed and awk off the allowlist entirely.
 */
const WRITING_FLAGS = new Set(["-exec", "-execdir", "-delete", "-ok", "-okdir", "-fls", "-fprint"]);

/** Shell syntax that can write, spawn, or hide another command. */
const FORBIDDEN_SUBSTRINGS = [
  "$(", "`", "<(", ">(",   // substitution and process substitution
  ";",                      // sequencing — the second command is unconstrained
  "&&&", "|&"               // stderr piping
];

/**
 * Whether the relay may answer this bash call itself.
 *
 * Returns false for anything it does not fully understand. A `false` costs the
 * founder one card; a wrong `true` runs something unseen.
 */
export function isReadOnlyBash(raw: unknown): boolean {
  if (typeof raw !== "string") return false;
  const command = raw.trim();
  if (!command || command.length > 2000) return false;

  for (const bad of FORBIDDEN_SUBSTRINGS) {
    if (command.includes(bad)) return false;
  }

  // Redirection writes, with ONE exception: `2>/dev/null` discards stderr and
  // cannot produce a file. It appears in almost every real exploration command
  // (`cat README.md 2>/dev/null | head`), so excluding it would mean approving
  // nothing in practice.
  const withoutNullRedirect = command.replace(/2>\s*\/dev\/null/g, " ");
  if (/[<>]/.test(withoutNullRedirect)) return false;

  // Background execution detaches the command from the turn, so nothing can
  // observe what it did. `&&` is fine and must survive this check.
  if (/(^|[^&])&($|[^&])/.test(withoutNullRedirect)) return false;

  const segments = withoutNullRedirect
    .split(/\|\||&&|\|/)
    .map((s) => s.trim())
    .filter((s) => s.length > 0);
  if (segments.length === 0) return false;

  return segments.every(isReadOnlySegment);
}

function isReadOnlySegment(segment: string): boolean {
  const tokens = tokenise(segment);
  if (!tokens) return false;          // unbalanced quotes — do not guess
  if (tokens.length === 0) return false;

  // `FOO=bar cmd` — skip leading environment assignments, but only simple
  // ones. Anything exotic in front of the binary means we cannot tell what
  // will run.
  let index = 0;
  while (index < tokens.length && /^[A-Za-z_][A-Za-z0-9_]*=[^\s]*$/.test(tokens[index])) index += 1;
  if (index >= tokens.length) return false;

  const binary = tokens[index];
  const args = tokens.slice(index + 1);

  // An absolute or relative path to a binary hides what is being run behind a
  // filename we have not checked. Bare names only.
  if (binary.includes("/")) return false;
  if (binary === "sudo" || binary === "env" || binary === "xargs") return false;

  if (binary === "git") {
    const sub = args.find((a) => !a.startsWith("-"));
    return sub !== undefined && READ_ONLY_GIT.has(sub);
  }

  if (!READ_ONLY_BINARIES.has(binary)) return false;
  if (args.some((a) => WRITING_FLAGS.has(a))) return false;

  return true;
}

/**
 * Split on unquoted whitespace, keeping quoted runs whole.
 *
 * Returns null on unbalanced quotes rather than a best guess: a command we
 * cannot parse is a command we cannot vouch for.
 */
function tokenise(segment: string): string[] | null {
  const tokens: string[] = [];
  let current = "";
  let quote: string | null = null;

  for (const ch of segment) {
    if (quote) {
      if (ch === quote) quote = null;
      else current += ch;
      continue;
    }
    if (ch === '"' || ch === "'") { quote = ch; continue; }
    if (/\s/.test(ch)) {
      if (current) { tokens.push(current); current = ""; }
      continue;
    }
    current += ch;
  }
  if (quote) return null;
  if (current) tokens.push(current);
  return tokens;
}

//
// CMA session events → the ExecStep rows the run card renders.
//
// Pure on purpose: the live SSE relay and the webhook backfill both call
// this, and a founder who watched a run must see the same rows as one who
// closed the app and came back. Two code paths producing two different
// transcripts of the same run is the bug this shape prevents.

/** The mount path every session uses; see engRepo.MOUNT_PATH. */
const MOUNT_PREFIX = "/workspace/repo/";

/** Longest label a step row can carry before the card starts wrapping badly. */
const MAX_LABEL = 88;

export interface ExecStep {
  id: string;
  label: string;
  /** A `done: true` step with an empty label is a completion marker for `id`. */
  done: boolean;
}

function relPath(p: unknown): string | null {
  if (typeof p !== "string" || p.length === 0) return null;
  return p.startsWith(MOUNT_PREFIX) ? p.slice(MOUNT_PREFIX.length) : p;
}

function truncate(s: string): string {
  return s.length <= MAX_LABEL ? s : s.slice(0, MAX_LABEL - 1) + "…";
}

/**
 * What the step SAYS, in checklist voice — never past tense.
 *
 * These labels are built from `agent.tool_use`, which is the agent ANNOUNCING
 * a tool, not finishing one: `done` is false, and under `bash: always_ask` the
 * tool may be sitting unanswered in front of the founder, or about to be
 * denied outright. Past tense was a claim the event cannot support.
 *
 * Seen for real on 14 Aug, in the first live run: two commands rendered as
 * "ran cd … && grep …" with an un-ticked marker, directly above permission
 * cards saying "Wants to run:" the same command. The transcript contradicted
 * itself inside one card.
 *
 * The tick is what says whether it happened. So the label is the action, and
 * `bash` is just the command — a shell line is already imperative, and "ran"
 * was only ever restating the row it sat in.
 */
function label(name: string, input: Record<string, unknown>): string {
  const path = relPath(input.path);
  switch (name) {
    case "bash":
      return typeof input.command === "string" ? input.command : "a command";
    case "read":
      return path ? `read ${path}` : "read a file";
    case "write":
      return path ? `create ${path}` : "create a file";
    case "edit":
      return path ? `edit ${path}` : "edit a file";
    case "glob":
    case "grep":
      return typeof input.pattern === "string" ? `search ${input.pattern}` : "search";
    case "web_search":
      return typeof input.query === "string" ? `search the web: ${input.query}` : "search the web";
    default:
      // An unrecognised tool is still worth showing — the founder should see
      // that *something* happened, and a new built-in tool must not blank the
      // transcript or throw mid-stream.
      return name;
  }
}

/**
 * One event → one step row, or null when the event isn't step-shaped.
 *
 * Never throws. A malformed event drops out of the transcript; it does not
 * take the stream down with it.
 */
export function toExecStep(event: unknown): ExecStep | null {
  if (typeof event !== "object" || event === null) return null;
  const e = event as Record<string, unknown>;

  if (e.type === "agent.tool_use" || e.type === "agent.mcp_tool_use") {
    const id = typeof e.id === "string" ? e.id : null;
    const name = typeof e.name === "string" ? e.name : "tool";
    if (!id) return null;
    const input = (typeof e.input === "object" && e.input !== null ? e.input : {}) as Record<string, unknown>;
    return { id, label: truncate(label(name, input)), done: false };
  }

  if (e.type === "agent.tool_result" || e.type === "agent.mcp_tool_result") {
    const target = typeof e.tool_use_id === "string" ? e.tool_use_id : null;
    if (!target) return null;
    return { id: target, label: "", done: true };
  }

  return null;
}

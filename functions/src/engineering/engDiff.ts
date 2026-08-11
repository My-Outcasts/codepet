//
// GitHub's compare payload → the diff the Review pane renders.
//
// The diff deliberately comes from GitHub rather than from parsing what the
// agent said it did. The agent's narration is a claim; `base...head` is the
// fact. It also gives all three review scopes (branch, last turn, a single
// commit) from the same call, because each is just a different base.

/** GitHub caps a compare response at 300 files. */
const COMPARE_FILE_CAP = 300;

export interface FileDiff {
  /** The file's current name — what consumers key off when fetching contents.
   * For a rename, `file` is the new name; `path` is the display label. */
  file: string;
  /** Display label. For a rename, shows "old → new"; for other changes, equals `file`. */
  path: string;
  additions: number;
  deletions: number;
  status: string;
  /** null for binary files — GitHub omits the patch. */
  patch: string | null;
}

export interface DiffSummary {
  files: FileDiff[];
  additions: number;
  deletions: number;
  /** True when GitHub hit its file cap and the list is incomplete. */
  truncated: boolean;
}

function emptyDiffSummary(): DiffSummary {
  return { files: [], additions: 0, deletions: 0, truncated: false };
}

function num(v: unknown): number {
  return typeof v === "number" && Number.isFinite(v) ? v : 0;
}

export function parseCompare(payload: unknown): DiffSummary {
  if (typeof payload !== "object" || payload === null) return emptyDiffSummary();
  const raw = (payload as Record<string, unknown>).files;
  if (!Array.isArray(raw)) return emptyDiffSummary();

  const files: FileDiff[] = [];
  let additions = 0;
  let deletions = 0;

  // Derive truncated from the RAW input length, before filtering. If GitHub hit
  // the cap, we must report it even if some entries are malformed and filtered out.
  const truncated = raw.length >= COMPARE_FILE_CAP;

  for (const entry of raw) {
    if (typeof entry !== "object" || entry === null) continue;
    const f = entry as Record<string, unknown>;
    if (typeof f.filename !== "string") continue;

    // A rename with no content change would otherwise show as a file that
    // appeared from nowhere. Showing both names costs one arrow and saves
    // the founder wondering where the old file went.
    const path =
      typeof f.previous_filename === "string" ? `${f.previous_filename} → ${f.filename}` : f.filename;

    const add = num(f.additions);
    const del = num(f.deletions);
    additions += add;
    deletions += del;

    files.push({
      file: typeof f.filename === "string" ? f.filename : "",
      path,
      additions: add,
      deletions: del,
      status: typeof f.status === "string" ? f.status : "modified",
      // Binary files carry no patch. Keep the row — "we changed your logo"
      // is information even when we cannot show the bytes.
      patch: typeof f.patch === "string" ? f.patch : null
    });
  }

  return { files, additions, deletions, truncated };
}

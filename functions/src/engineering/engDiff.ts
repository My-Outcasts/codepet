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

// ---------------------------------------------------------------------------
// The handler. Everything above is pure and was written in Plan 1; nothing
// called it until now, so the Review pane had no data source at all.
// ---------------------------------------------------------------------------

import { Request } from "firebase-functions/v2/https";
import { Response } from "express";
import * as admin from "firebase-admin";
import * as logger from "firebase-functions/logger";
import { verifyAuth } from "../auth";
import { isSafePathSegment, safeErrorDetail } from "./engClient";
import { loadGitHubToken, parseRepoUrl } from "./engRepo";
import { compare } from "./engGitHub";

/** Which base to compare the run's branch against. */
export type ReviewScope = "branch" | "turn";

export interface DiffResponse extends DiffSummary {
  scope: ReviewScope;
  /**
   * True when `turn` was asked for and `branch` was returned. The founder
   * asked to see one turn's work and is looking at the whole branch; saying
   * so is the difference between a wider diff and a WRONG one.
   */
  scopeFellBack: boolean;
}

interface RunDoc {
  repo?: string;
  branch?: string;
  baseBranch?: string;
  /** Written by nothing yet — see the fallback below. */
  lastTurnBaseSha?: string;
}

export function parseScope(value: unknown): ReviewScope {
  // `commit` is in the spec's selector but needs a commit id this endpoint is
  // not given; it is not silently accepted and quietly treated as something
  // else. Anything unrecognised means the whole branch, which is the widest
  // honest answer.
  return value === "turn" ? "turn" : "branch";
}

export async function handleEngDiff(req: Request, res: Response): Promise<void> {
  const auth = await verifyAuth(req.headers.authorization);
  if (!auth) {
    res.status(401).json({ error: "invalid_token" });
    return;
  }

  const runId = typeof req.query?.runId === "string" ? req.query.runId : "";
  if (!runId || !isSafePathSegment(runId)) {
    res.status(400).json({ error: "invalid_payload", detail: "runId required" });
    return;
  }
  const scope = parseScope(req.query?.scope);

  const encKey = process.env.CONNECTOR_ENC_KEY;
  if (!encKey) {
    logger.error("engDiff: CONNECTOR_ENC_KEY absent");
    res.status(500).json({ error: "misconfigured", detail: "CONNECTOR_ENC_KEY absent" });
    return;
  }

  let snap: FirebaseFirestore.DocumentSnapshot;
  let token: string | null;
  try {
    snap = await admin.firestore().doc(`companies/${auth.uid}/engRuns/${runId}`).get();
    token = await loadGitHubToken(auth.uid, encKey);
  } catch (err) {
    logger.error("engDiff: lookup failed", safeErrorDetail(err));
    res.status(503).json({ error: "lookup_failed" });
    return;
  }
  if (!snap.exists) {
    res.status(404).json({ error: "no_such_run" });
    return;
  }
  if (!token) {
    res.status(409).json({ error: "github_not_connected" });
    return;
  }

  const run = (snap.data() ?? {}) as RunDoc;
  const parsed = run.repo ? parseRepoUrl(run.repo) : null;
  if (!parsed || !run.branch || !run.baseBranch) {
    res.status(422).json({ error: "run_not_diffable" });
    return;
  }

  // `turn` wants the base at the start of the last turn. Nothing writes
  // `lastTurnBaseSha` yet, so it falls back to the branch base and SAYS SO.
  // Silently widening would show the founder changes from earlier turns as if
  // they were this turn's — a wrong answer wearing the right label.
  const wantsTurn = scope === "turn";
  const turnBase = typeof run.lastTurnBaseSha === "string" ? run.lastTurnBaseSha : "";
  const scopeFellBack = wantsTurn && !turnBase;
  const base = wantsTurn && turnBase ? turnBase : run.baseBranch;

  try {
    const payload = await compare(token, parsed.owner, parsed.repo, base, run.branch);
    res.status(200).json({ ...parseCompare(payload), scope, scopeFellBack } satisfies DiffResponse);
  } catch (err) {
    // Never the body: a compare error can echo the request, and the request
    // carries the token.
    logger.error("engDiff: compare failed", safeErrorDetail(err));
    res.status(503).json({ error: "diff_unavailable" });
  }
}

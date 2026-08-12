//
// What happens after the founder reads the diff: open a PR, and tell them
// whether there is something to click.
//
// `engShip` OPENS A PULL REQUEST. It does not merge. The button says "Ship
// this" and that is the right words for a founder — but merging someone's
// default branch from a button, on a diff they may have skim-read, is not a
// thing to build before there is a review pane people trust. The label and
// the action can converge later; shipping the merge first cannot be undone.
//
import { Request } from "firebase-functions/v2/https";
import { Response } from "express";
import * as admin from "firebase-admin";
import * as logger from "firebase-functions/logger";
import { verifyAuth } from "../auth";
import { isSafePathSegment, safeErrorDetail } from "./engClient";
import { loadGitHubToken, parseRepoUrl } from "./engRepo";
import { openPR, latestPreview, hasDeployTarget } from "./engGitHub";

/** Why there is no preview link. A closed set — the client renders each differently. */
export type NoPreviewReason = "no_deploy_target" | "pending" | "failed";

interface RunDoc {
  repo?: string;
  branch?: string;
  baseBranch?: string;
  ask?: string;
  prNumber?: number;
  prUrl?: string;
}

/**
 * Load the caller's run, or send the response that says why not.
 *
 * Addressed under the caller's own uid, which is what makes another founder's
 * runId simply not resolve — there is no ownership check to forget, because
 * the path cannot name someone else's document.
 */
async function loadRun(
  uid: string,
  req: Request,
  res: Response
): Promise<{ runId: string; run: RunDoc; token: string } | null> {
  const runId =
    typeof req.body?.runId === "string"
      ? req.body.runId
      : typeof req.query?.runId === "string"
        ? req.query.runId
        : "";
  // Straight into a Firestore path below; a slash-bearing value makes
  // `db.doc(...)` throw synchronously on an odd segment count. Same rule as
  // engStream/engSendTurn/engWebhook.
  if (!runId || !isSafePathSegment(runId)) {
    res.status(400).json({ error: "invalid_payload", detail: "runId required" });
    return null;
  }

  const encKey = process.env.CONNECTOR_ENC_KEY;
  if (!encKey) {
    logger.error("engShip: CONNECTOR_ENC_KEY absent");
    res.status(500).json({ error: "misconfigured", detail: "CONNECTOR_ENC_KEY absent" });
    return null;
  }

  let snap: FirebaseFirestore.DocumentSnapshot;
  let token: string | null;
  try {
    snap = await admin.firestore().doc(`companies/${uid}/engRuns/${runId}`).get();
    token = await loadGitHubToken(uid, encKey);
  } catch (err) {
    logger.error("engShip: lookup failed", safeErrorDetail(err));
    res.status(503).json({ error: "lookup_failed" });
    return null;
  }

  if (!snap.exists) {
    res.status(404).json({ error: "no_such_run" });
    return null;
  }
  if (!token) {
    res.status(409).json({ error: "github_not_connected" });
    return null;
  }
  return { runId, run: (snap.data() ?? {}) as RunDoc, token };
}

export async function handleEngShip(req: Request, res: Response): Promise<void> {
  if (req.method !== "POST") {
    res.status(405).json({ error: "method_not_allowed" });
    return;
  }
  const auth = await verifyAuth(req.headers.authorization);
  if (!auth) {
    res.status(401).json({ error: "invalid_token" });
    return;
  }

  const loaded = await loadRun(auth.uid, req, res);
  if (!loaded) return;
  const { runId, run, token } = loaded;

  // Already shipped. Return the existing PR rather than opening a second one
  // for the same branch — GitHub would reject the duplicate anyway, but with
  // a 422 the founder cannot act on, and a second tap on a slow button must
  // not read as a failure.
  if (typeof run.prNumber === "number") {
    res.status(200).json({ prNumber: run.prNumber, prUrl: run.prUrl ?? "" });
    return;
  }

  const parsed = run.repo ? parseRepoUrl(run.repo) : null;
  if (!parsed || !run.branch || !run.baseBranch) {
    // A run recorded without the fields engStartRun writes. Not the founder's
    // mistake and not retryable by them.
    logger.error("engShip: run is missing repo/branch/baseBranch", { runId });
    res.status(422).json({ error: "run_not_shippable" });
    return;
  }

  let pr: Awaited<ReturnType<typeof openPR>>;
  try {
    pr = await openPR(
      token,
      parsed.owner,
      parsed.repo,
      run.branch,
      run.baseBranch,
      run.ask?.slice(0, 72) || "Changes from Codepet",
      "Opened by Codepet's engineering agent."
    );
  } catch (err) {
    logger.error("engShip: openPR failed", safeErrorDetail(err));
    res.status(503).json({ error: "github_unavailable" });
    return;
  }

  try {
    await admin
      .firestore()
      .doc(`companies/${auth.uid}/engRuns/${runId}`)
      .set({ prNumber: pr.number, prUrl: pr.url }, { merge: true });
  } catch (err) {
    // The PR EXISTS. Recording it failed, which means a second Ship would try
    // to open it again — so hand the founder the URL now rather than a bare
    // 503 that hides a pull request they already have.
    logger.error("engShip: pr write failed", safeErrorDetail(err));
    res.status(503).json({ error: "pr_write_failed", prNumber: pr.number, prUrl: pr.url });
    return;
  }

  res.status(200).json({ prNumber: pr.number, prUrl: pr.url });
}

export async function handleEngPreview(req: Request, res: Response): Promise<void> {
  const auth = await verifyAuth(req.headers.authorization);
  if (!auth) {
    res.status(401).json({ error: "invalid_token" });
    return;
  }

  const loaded = await loadRun(auth.uid, req, res);
  if (!loaded) return;
  const { run, token } = loaded;

  const parsed = run.repo ? parseRepoUrl(run.repo) : null;
  if (!parsed || !run.branch) {
    res.status(422).json({ error: "run_not_shippable" });
    return;
  }

  try {
    const preview = await latestPreview(token, parsed.owner, parsed.repo, run.branch);
    if (preview) {
      res.status(200).json({ url: preview.url, state: preview.state });
      return;
    }
    // No successful preview. WHICH kind of no matters: "install Vercel" and
    // "wait a moment" are different things to tell a founder, and a single
    // null cannot tell them apart. This second call is what separates them.
    const target = await hasDeployTarget(token, parsed.owner, parsed.repo, run.branch);
    res.status(200).json({
      url: null,
      reason: (target ? "pending" : "no_deploy_target") satisfies NoPreviewReason
    });
  } catch (err) {
    logger.error("engPreview: github call failed", safeErrorDetail(err));
    res.status(503).json({ error: "github_unavailable" });
  }
}

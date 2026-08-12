//
// Repo onboarding: what a founder hits before their first engineering run.
//
// `engStartRun` answers 409 `no_repo_linked` when nothing is linked, and the
// client turns that into connect-or-create. These are the two handlers behind
// those choices.
//
// `firebase-functions/v2/https` exports Request but NOT Response — importing
// both from it is a TS2305. Every existing handler here takes Response from
// express; match them.
import { Request } from "firebase-functions/v2/https";
import { Response } from "express";
import * as logger from "firebase-functions/logger";
import { verifyAuth } from "../auth";
import { safeErrorDetail } from "./engClient";
import { loadGitHubToken, writeRepoLink, parseRepoUrl } from "./engRepo";
import { listRepos, getDefaultBranch } from "./engGitHub";

/**
 * `owner/repo`, and nothing that could be anything else.
 *
 * Both halves are interpolated into a GitHub API path. GitHub's own rules are
 * narrower than this, but the property that matters is that neither half can
 * carry a `/`, a `.`, or whitespace — so no value accepted here can traverse
 * out of `/repos/{owner}/{repo}`.
 */
const FULL_NAME = /^[A-Za-z0-9][A-Za-z0-9._-]*\/[A-Za-z0-9][A-Za-z0-9._-]*$/;

export function parseFullName(value: unknown): { owner: string; repo: string } | null {
  if (typeof value !== "string" || !FULL_NAME.test(value)) return null;
  if (value.includes("..")) return null;
  const [owner, repo] = value.split("/");
  return { owner, repo };
}

/** The token, or the response that says why there isn't one. Null means handled. */
async function requireToken(uid: string, res: Response): Promise<string | null> {
  const encKey = process.env.CONNECTOR_ENC_KEY;
  if (!encKey) {
    logger.error("engRepoHandlers: CONNECTOR_ENC_KEY absent");
    res.status(500).json({ error: "misconfigured", detail: "CONNECTOR_ENC_KEY absent" });
    return null;
  }
  let token: string | null;
  try {
    token = await loadGitHubToken(uid, encKey);
  } catch (err) {
    logger.error("engRepoHandlers: connector lookup failed", safeErrorDetail(err));
    res.status(503).json({ error: "connector_lookup_failed" });
    return null;
  }
  if (!token) {
    // Distinct from an empty list on purpose. "You have no repos" is a dead
    // end; this sends the founder to the GitHub connect flow, which is the
    // actual next step.
    res.status(409).json({ error: "github_not_connected" });
    return null;
  }
  return token;
}

export async function handleEngListRepos(req: Request, res: Response): Promise<void> {
  const auth = await verifyAuth(req.headers.authorization);
  if (!auth) {
    res.status(401).json({ error: "invalid_token" });
    return;
  }

  const token = await requireToken(auth.uid, res);
  if (!token) return;

  try {
    res.status(200).json({ repos: await listRepos(token) });
  } catch (err) {
    // Never the body — a GitHub error can quote the request, and the request
    // carries the token. `GitHubError` already holds only operation + status.
    logger.error("engListRepos: github call failed", safeErrorDetail(err));
    res.status(503).json({ error: "github_unavailable" });
  }
}

export async function handleEngLinkRepo(req: Request, res: Response): Promise<void> {
  if (req.method !== "POST") {
    res.status(405).json({ error: "method_not_allowed" });
    return;
  }
  const auth = await verifyAuth(req.headers.authorization);
  if (!auth) {
    res.status(401).json({ error: "invalid_token" });
    return;
  }

  const parsed = parseFullName(req.body?.fullName);
  if (!parsed) {
    res.status(400).json({ error: "invalid_payload", detail: "fullName must be owner/repo" });
    return;
  }

  const token = await requireToken(auth.uid, res);
  if (!token) return;

  let defaultBranch: string | null;
  try {
    defaultBranch = await getDefaultBranch(token, parsed.owner, parsed.repo);
  } catch (err) {
    logger.error("engLinkRepo: github call failed", safeErrorDetail(err));
    res.status(503).json({ error: "github_unavailable" });
    return;
  }

  if (!defaultBranch) {
    // Write NOTHING. `loadRepo` fails closed on a blank branch, so a
    // half-written link is indistinguishable from no link at all — the
    // founder would see "connect a repo" having just connected one, with
    // nothing anywhere explaining why.
    res.status(422).json({ error: "no_default_branch" });
    return;
  }

  const url = `https://github.com/${parsed.owner}/${parsed.repo}`;
  // Round-trips through the same parser `loadRepo` uses, so a name this
  // handler accepts can never produce a URL that one rejects.
  if (!parseRepoUrl(url)) {
    res.status(400).json({ error: "invalid_payload", detail: "fullName must be owner/repo" });
    return;
  }

  try {
    await writeRepoLink(auth.uid, url, defaultBranch);
  } catch (err) {
    logger.error("engLinkRepo: link write failed", safeErrorDetail(err));
    res.status(503).json({ error: "link_write_failed" });
    return;
  }

  res.status(200).json({ url, defaultBranch });
}

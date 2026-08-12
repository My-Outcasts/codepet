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
import * as admin from "firebase-admin";
import { loadGitHubToken, writeRepoLink, parseRepoUrl } from "./engRepo";
import { listRepos, getDefaultBranch, createRepo } from "./engGitHub";

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

/**
 * A company name → a repo name GitHub will accept.
 *
 * GitHub allows only `A-Za-z0-9._-`; anything else in a name — an apostrophe,
 * an accent, an emoji, a space — is replaced rather than dropped, so
 * "Mona's Café" becomes `mona-s-cafe` instead of `monascafe`, which is
 * still readable as the company it came from.
 *
 * Falls back to `codepet-project` rather than to an empty string: a name made
 * entirely of characters GitHub rejects (an all-emoji company name is a real
 * thing) would otherwise POST an empty name and 422 with nothing useful to
 * show the founder.
 */
export function repoSlug(companyName: unknown): string {
  const raw = typeof companyName === "string" ? companyName : "";
  const slug = raw
    .normalize("NFKD")
    // Strip combining marks so "é" contributes "e" rather than "e" + a mark
    // that the next step would turn into a dash.
    .replace(/[̀-ͯ]/g, "")
    .toLowerCase()
    .replace(/[^a-z0-9._-]+/g, "-")
    // Leading and trailing dashes are legal but ugly, and a leading dot or
    // dash is how you get a name GitHub silently treats as hidden.
    .replace(/^[-._]+|[-._]+$/g, "")
    .slice(0, 90);
  return slug || "codepet-project";
}

/** Where the founder installs the Vercel GitHub app for a repo. */
export function vercelSetupUrl(owner: string, repo: string): string {
  return `https://vercel.com/new/git/github/${owner}/${repo}`;
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

export async function handleEngCreateRepo(req: Request, res: Response): Promise<void> {
  if (req.method !== "POST") {
    res.status(405).json({ error: "method_not_allowed" });
    return;
  }
  const auth = await verifyAuth(req.headers.authorization);
  if (!auth) {
    res.status(401).json({ error: "invalid_token" });
    return;
  }

  const token = await requireToken(auth.uid, res);
  if (!token) return;

  // A caller-supplied name is still slugged. GitHub would reject most of what
  // a founder might type, and a 422 from GitHub is not something they can act
  // on; the same normalisation that handles a company name handles this.
  let name = typeof req.body?.name === "string" && req.body.name.trim()
    ? repoSlug(req.body.name)
    : "";
  let description = "Built with Codepet";
  if (!name) {
    let company: FirebaseFirestore.DocumentData = {};
    try {
      company = (await admin.firestore().doc(`companies/${auth.uid}`).get()).data() ?? {};
    } catch (err) {
      // Not fatal: the fallback slug is a usable repo name. Losing the
      // founder's company name is worth far less than losing the run.
      logger.warn("engCreateRepo: company lookup failed", safeErrorDetail(err));
    }
    name = repoSlug(company.name);
    if (typeof company.brief === "string" && company.brief.trim()) {
      description = company.brief.trim().slice(0, 200);
    }
  }

  let created: Awaited<ReturnType<typeof createRepo>>;
  try {
    created = await createRepo(token, name, description);
  } catch (err) {
    logger.error("engCreateRepo: github call failed", safeErrorDetail(err));
    res.status(503).json({ error: "github_unavailable" });
    return;
  }

  const parsed = parseRepoUrl(created.url);
  if (!parsed) {
    // GitHub returned a URL our own parser rejects. Report the repo — it
    // exists now — rather than swallowing it.
    logger.error("engCreateRepo: created repo has an unparseable url");
    res.status(502).json({ error: "unexpected_repo_url", createdRepoUrl: created.url });
    return;
  }

  try {
    await writeRepoLink(auth.uid, created.url, created.defaultBranch);
  } catch (err) {
    // The repo EXISTS on GitHub and is not linked here. Returning a bare 503
    // would leave the founder to click "Create one for me" again and end up
    // with a second empty repo. Hand back the URL so the client can offer to
    // link the one that was just made.
    logger.error("engCreateRepo: link write failed", safeErrorDetail(err));
    res.status(503).json({ error: "link_write_failed", createdRepoUrl: created.url });
    return;
  }

  res.status(200).json({
    url: created.url,
    defaultBranch: created.defaultBranch,
    // Returned, not opened for them: installing the Vercel app is the
    // founder's decision on their own account, and Codepet holds no Vercel
    // credential. Without it there is simply no preview, which the Review
    // pane says plainly rather than hiding.
    vercelSetupUrl: vercelSetupUrl(parsed.owner, parsed.repo)
  });
}

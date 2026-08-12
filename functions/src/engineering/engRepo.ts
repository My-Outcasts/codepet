//
// Which repo an engineering run works on, and the token that reaches it.
//
// The token is read here and handed to the session's `github_repository`
// resource — it is never written into a prompt, a system message, or an
// event. Managed Agents injects it into git traffic *after* the request
// leaves the sandbox, so nothing running in the container can read it.
import * as admin from "firebase-admin";
import { openToken, type SealedToken } from "../oauth/githubOAuthCore";

/** Where the repo is mounted in every session container. */
export const MOUNT_PATH = "/workspace/repo";

export interface RepoLink {
  url: string;
  owner: string;
  repo: string;
  defaultBranch: string;
  token: string;
}

/**
 * The repo link. Deliberately holds NO credential.
 *
 * It used to carry its own `sealed` copy of the GitHub token, which meant the
 * token lived in two documents: here and `connectors/github`. Two copies is
 * two things to rotate and two things to leak — and worse, a founder who
 * disconnected GitHub would keep running against the stale copy, with nothing
 * anywhere indicating why. A `sealed` field left here by the old shape is
 * ignored, not preferred.
 */
interface RepoDoc {
  url?: string;
  defaultBranch?: string;
}

const GITHUB_URL = /^https:\/\/github\.com\/([^/\s?#]+)\/([^/\s?#]+?)(?:\.git)?\/?$/;

export function parseRepoUrl(url: string): { owner: string; repo: string } | null {
  const m = GITHUB_URL.exec(url.trim());
  if (!m) return null;
  return { owner: m[1], repo: m[2] };
}

/**
 * One branch per run, namespaced so a founder can tell at a glance which
 * branches on their repo are ours. Derived from the run id rather than the
 * ask, so a retry lands on the same branch instead of forking a new one.
 */
export function branchName(runId: string): string {
  return `codepet/run-${runId}`;
}

/**
 * The founder's linked repo, or null when they have not connected one.
 *
 * Unlike `loadConnectors`, this does NOT fail open. A chat turn without a
 * connector is a slightly worse answer; an engineering run without a repo
 * has nothing to work on, and starting one anyway would burn credits to
 * produce nothing. Missing defaultBranch is unresolved, not guessed; a wrong
 * branch name in a run wastes credits on an obscure git error. The caller
 * turns null into the connect-or-create prompt.
 */
export async function loadRepo(uid: string, encKey: string): Promise<RepoLink | null> {
  const db = admin.firestore();
  const snap = await db.doc(`companies/${uid}/engineering/repo`).get();
  if (!snap.exists) return null;

  const data = snap.data() as RepoDoc;
  if (
    typeof data.url !== "string" ||
    !data.url ||
    typeof data.defaultBranch !== "string" ||
    !data.defaultBranch.trim()
  )
    return null;

  const parsed = parseRepoUrl(data.url);
  if (!parsed) return null;

  // The token comes from the connector the OAuth callback writes, and from
  // nowhere else. A linked repo with no connected GitHub account is "connect
  // a repo", not a run against whatever credential happens to be lying around.
  const connectorSnap = await db.doc(`companies/${uid}/connectors/github`).get();
  const sealed = (connectorSnap.data() as { sealed?: SealedToken } | undefined)?.sealed;
  if (!sealed) return null;

  let token: string;
  try {
    token = openToken(sealed, encKey);
  } catch {
    // A tampered or unreadable blob. Never log the error — it can echo
    // ciphertext. Treat it as "no repo linked" so the founder is asked to
    // reconnect rather than shown a decryption failure.
    return null;
  }

  return {
    url: data.url,
    owner: parsed.owner,
    repo: parsed.repo,
    defaultBranch: data.defaultBranch.trim(),
    token
  };
}

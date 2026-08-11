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

interface RepoDoc {
  url?: string;
  defaultBranch?: string;
  sealed?: SealedToken;
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
  const snap = await admin.firestore().doc(`companies/${uid}/engineering/repo`).get();
  if (!snap.exists) return null;

  const data = snap.data() as RepoDoc;
  if (
    !data.url ||
    !data.sealed ||
    typeof data.defaultBranch !== "string" ||
    !data.defaultBranch.trim()
  )
    return null;

  const parsed = parseRepoUrl(data.url);
  if (!parsed) return null;

  let token: string;
  try {
    token = openToken(data.sealed, encKey);
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
    defaultBranch: data.defaultBranch,
    token
  };
}

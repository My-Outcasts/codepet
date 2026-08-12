//
// Every GitHub REST call Engineering mode makes, in one module.
//
// One module because this is the only place a founder's GitHub token is held
// in memory, which turns "can this leak?" into a question about one file.
// Nothing here returns, throws, or logs a value derived from a response body:
// a 4xx from GitHub can quote the request back, and the request carries the
// token in its Authorization header.
//
const API = "https://api.github.com";

/** GitHub's own ceiling for a single page; we never paginate past one. */
const PER_PAGE = 100;

/**
 * How many deployments deep to look for a usable preview. Vercel creates one
 * per push, so the newest few cover "the deploy after the failed deploy"
 * without an unbounded walk on a busy branch.
 */
const PREVIEW_LOOKBACK = 3;

export interface RepoChoice {
  fullName: string;
  url: string;
  defaultBranch: string;
  isPrivate: boolean;
  pushedAt: string;
}

export interface PullRequestRef {
  number: number;
  url: string;
}

export interface PreviewRef {
  url: string;
  state: string;
}

/**
 * An error that names the operation and the status, and carries nothing from
 * the response.
 *
 * A plain `throw new Error(await res.text())` is the obvious thing to write
 * and the one that leaks: GitHub's 401/403 bodies quote the request that
 * produced them.
 */
export class GitHubError extends Error {
  readonly status: number;
  constructor(operation: string, status: number) {
    super(`github ${operation} failed with ${status}`);
    this.name = "GitHubError";
    this.status = status;
  }
}

async function call(
  operation: string,
  token: string,
  path: string,
  init?: { method?: string; body?: unknown }
): Promise<unknown> {
  const response = await fetch(`${API}${path}`, {
    method: init?.method ?? "GET",
    headers: {
      Authorization: `Bearer ${token}`,
      Accept: "application/vnd.github+json",
      "X-GitHub-Api-Version": "2022-11-28",
      ...(init?.body ? { "Content-Type": "application/json" } : {})
    },
    ...(init?.body ? { body: JSON.stringify(init.body) } : {})
  });
  if (!response.ok) throw new GitHubError(operation, response.status);
  return response.json();
}

function str(v: unknown): string {
  return typeof v === "string" ? v : "";
}

function toRepoChoice(raw: unknown): RepoChoice | null {
  if (typeof raw !== "object" || raw === null) return null;
  const r = raw as Record<string, unknown>;
  const fullName = str(r.full_name);
  const defaultBranch = str(r.default_branch);
  // Both are required downstream: `fullName` addresses every later call, and
  // `loadRepo` fails closed without a branch. A repo missing either is
  // dropped from the list rather than offered as a choice that cannot work.
  if (!fullName || !defaultBranch) return null;
  return {
    fullName,
    url: str(r.html_url) || `https://github.com/${fullName}`,
    defaultBranch,
    isPrivate: r.private === true,
    pushedAt: str(r.pushed_at)
  };
}

/**
 * Repos the founder can push to, most recently pushed first.
 *
 * `affiliation` excludes repos they can only read — offering one would produce
 * a run that does all the work and fails at the push.
 */
export async function listRepos(token: string): Promise<RepoChoice[]> {
  const raw = await call(
    "listRepos",
    token,
    `/user/repos?per_page=${PER_PAGE}&sort=pushed&direction=desc&affiliation=owner,collaborator,organization_member`
  );
  if (!Array.isArray(raw)) return [];
  return raw.map(toRepoChoice).filter((r): r is RepoChoice => r !== null);
}

/**
 * Create a private repo with an initial commit.
 *
 * `auto_init` is not a nicety: a repo with no commits has no default branch,
 * and `loadRepo` fails closed on a link with a blank one. Creating an empty
 * repo would produce a link that resolves to "connect a repo" the moment it
 * is written.
 */
export async function createRepo(
  token: string,
  name: string,
  description: string
): Promise<RepoChoice> {
  const raw = await call("createRepo", token, "/user/repos", {
    method: "POST",
    body: { name, description, private: true, auto_init: true }
  });
  const choice = toRepoChoice(raw);
  if (!choice) throw new GitHubError("createRepo", 502);
  return choice;
}

export async function getDefaultBranch(
  token: string,
  owner: string,
  repo: string
): Promise<string | null> {
  const raw = await call("getDefaultBranch", token, `/repos/${owner}/${repo}`);
  const branch = str((raw as Record<string, unknown> | null)?.default_branch);
  return branch || null;
}

export async function openPR(
  token: string,
  owner: string,
  repo: string,
  head: string,
  base: string,
  title: string,
  body: string
): Promise<PullRequestRef> {
  const raw = (await call("openPR", token, `/repos/${owner}/${repo}/pulls`, {
    method: "POST",
    body: { head, base, title, body }
  })) as Record<string, unknown> | null;
  const number = raw?.number;
  if (typeof number !== "number") throw new GitHubError("openPR", 502);
  return { number, url: str(raw?.html_url) };
}

/**
 * The newest SUCCESSFUL preview URL for a ref, or null.
 *
 * Read from GitHub Deployments rather than from Vercel's API. When the Vercel
 * GitHub app is installed it publishes each preview as a Deployment with
 * `environment: "Preview"` and a status carrying `environment_url` — so the
 * `repo` scope we already hold is enough, and Codepet never stores a Vercel
 * credential. It also works unchanged for Netlify and Cloudflare Pages, which
 * publish the same shape.
 *
 * Two calls, because that is the API: deployments and their statuses are
 * separate resources. Newest-first, first success wins — a failed redeploy
 * after a good one must not replace a working link with a dead one.
 *
 * Null is not an error. A run that finishes before its deploy does is the
 * ordinary case; the caller distinguishes "no deploy target" from "pending".
 */
export async function latestPreview(
  token: string,
  owner: string,
  repo: string,
  ref: string
): Promise<PreviewRef | null> {
  const deployments = await call(
    "listDeployments",
    token,
    `/repos/${owner}/${repo}/deployments?ref=${encodeURIComponent(ref)}&environment=Preview&per_page=${PREVIEW_LOOKBACK}`
  );
  if (!Array.isArray(deployments) || deployments.length === 0) return null;

  for (const d of deployments.slice(0, PREVIEW_LOOKBACK)) {
    const id = (d as Record<string, unknown> | null)?.id;
    if (typeof id !== "number") continue;
    const statuses = await call(
      "listDeploymentStatuses",
      token,
      `/repos/${owner}/${repo}/deployments/${id}/statuses?per_page=${PER_PAGE}`
    );
    if (!Array.isArray(statuses)) continue;
    for (const s of statuses) {
      const st = s as Record<string, unknown>;
      const url = str(st.environment_url);
      if (st.state === "success" && url) return { url, state: "success" };
    }
  }
  return null;
}

/**
 * Whether ANY deployment exists for a ref, regardless of state.
 *
 * This is what separates "install Vercel" from "wait a moment", and those are
 * different things to tell a founder. `latestPreview` returning null cannot
 * distinguish them on its own.
 */
export async function hasDeployTarget(
  token: string,
  owner: string,
  repo: string,
  ref: string
): Promise<boolean> {
  const deployments = await call(
    "listDeployments",
    token,
    `/repos/${owner}/${repo}/deployments?ref=${encodeURIComponent(ref)}&per_page=1`
  );
  return Array.isArray(deployments) && deployments.length > 0;
}

/**
 * The raw `base...head` compare payload, for `parseCompare` to shape.
 *
 * The diff comes from GitHub rather than from parsing what the agent said it
 * did: the narration is a claim, `base...head` is the fact. It also yields all
 * three review scopes from one call, because each is just a different base.
 */
export async function compare(
  token: string,
  owner: string,
  repo: string,
  base: string,
  head: string
): Promise<unknown> {
  // Encoded per segment: a branch name legitimately contains `/`
  // (`codepet/run-x`), and the `...` between the two must stay literal.
  const range = `${encodeURIComponent(base)}...${encodeURIComponent(head)}`;
  return call("compare", token, `/repos/${owner}/${repo}/compare/${range}`);
}

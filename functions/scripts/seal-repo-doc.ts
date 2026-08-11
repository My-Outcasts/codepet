/**
 * Builds the `companies/{uid}/engineering/repo` document by hand, for the one
 * window before Plan 2's connect-a-repo flow writes it automatically.
 *
 * Everything `loadRepo` (`src/engineering/engRepo.ts`) requires, produced in
 * one step so none of the three fields can be forgotten:
 *
 *   cd functions
 *   REPO_URL=https://github.com/owner/repo \
 *   GITHUB_TOKEN="$(awk -F= '/^SPIKE_GITHUB_TOKEN=/{sub(/^SPIKE_GITHUB_TOKEN=/,"");print}' local.env)" \
 *   CONNECTOR_ENC_KEY="$(firebase functions:secrets:access CONNECTOR_ENC_KEY)" \
 *   npx ts-node --compilerOptions '{"module":"commonjs"}' scripts/seal-repo-doc.ts
 *
 * `defaultBranch` is read from the GitHub API rather than assumed. `loadRepo`
 * fails CLOSED without it — a doc missing the field resolves to `null`,
 * identical to no doc at all, and the founder is told to connect a repo. It
 * does not guess `"main"`, deliberately: a repo whose real default is
 * `master` would mount a branch that does not exist and die inside a paid run.
 *
 * Reads every credential from the environment, never from argv — a value in
 * argv lands in shell history and in `ps` output for the life of the process.
 *
 * Prints the sealed object, which is ciphertext and safe to paste. It never
 * prints the token or the encryption key. The round-trip check below opens
 * what it just sealed and compares, so a wrong CONNECTOR_ENC_KEY fails here
 * rather than as an opaque 409 "connect a repo" after the doc is already
 * written.
 */
import { sealToken, openToken } from "../src/oauth/githubOAuthCore";

function required(name: string): string {
  const value = process.env[name];
  if (!value) throw new Error(`${name} required — see the header of this file`);
  return value;
}

/** The same shape `parseRepoUrl` accepts, checked here so a typo fails early. */
function parseOwnerRepo(url: string): { owner: string; repo: string } {
  const match = /^https:\/\/github\.com\/([^/\s?#]+)\/([^/\s?#]+?)(?:\.git)?\/?$/.exec(url);
  if (!match) throw new Error(`REPO_URL is not a plain GitHub repo URL: ${url}`);
  return { owner: match[1], repo: match[2] };
}

async function main(): Promise<void> {
  const repoUrl = required("REPO_URL");
  const githubToken = required("GITHUB_TOKEN");
  const encKey = required("CONNECTOR_ENC_KEY");
  const { owner, repo } = parseOwnerRepo(repoUrl);

  const response = await fetch(`https://api.github.com/repos/${owner}/${repo}`, {
    headers: { Authorization: `Bearer ${githubToken}`, Accept: "application/vnd.github+json" }
  });
  if (!response.ok) {
    // Status only: a 401/403 body can echo request context, and the token is
    // in the request that produced it.
    throw new Error(
      `GitHub returned ${response.status} for ${owner}/${repo} — ` +
        `check the URL and that the token can see this repo`
    );
  }
  const { default_branch: defaultBranch } = (await response.json()) as { default_branch?: string };
  if (!defaultBranch) throw new Error("GitHub did not report a default_branch for this repo");

  const sealed = sealToken(githubToken, encKey);
  if (openToken(sealed, encKey) !== githubToken) {
    throw new Error("round-trip failed — the sealed token does not open back to the original");
  }

  console.log("Paste these three fields into companies/<uid>/engineering/repo\n");
  console.log(JSON.stringify({ url: repoUrl, defaultBranch, sealed }, null, 2));
}

main().catch((err) => {
  console.error(err instanceof Error ? err.message : String(err));
  process.exit(1);
});

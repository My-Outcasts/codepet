/**
 * Builds the `companies/{uid}/engineering/repo` document by hand, for the one
 * window before Plan 2's connect-a-repo flow writes it automatically.
 *
 * Both fields `loadRepo` (`src/engineering/engRepo.ts`) requires, produced in
 * one step so neither can be forgotten:
 *
 *   cd functions
 *   REPO_URL=https://github.com/owner/repo \
 *   GITHUB_TOKEN="$(awk -F= '/^SPIKE_GITHUB_TOKEN=/{sub(/^SPIKE_GITHUB_TOKEN=/,"");print}' local.env)" \
 *   npx ts-node --compilerOptions '{"module":"commonjs"}' scripts/seal-repo-doc.ts
 *
 * NO LONGER SEALS ANYTHING, despite the name. It used to emit a `sealed`
 * token for this document, which put the founder's GitHub credential in two
 * places at once — here and `connectors/github`. `loadRepo` now reads the
 * token from the connector alone, so this document holds no secret, and the
 * script needs no CONNECTOR_ENC_KEY. The name is kept because the runbook
 * references `npm run seal:repo`; renaming both is churn for its own sake.
 *
 * `GITHUB_TOKEN` is still required, but only to ASK GitHub for the repo's
 * default branch — it is never written anywhere.
 *
 * `defaultBranch` is read from the API rather than assumed. `loadRepo` fails
 * CLOSED without it — a doc missing the field resolves to `null`, identical
 * to no doc at all, and the founder is told to connect a repo. It does not
 * guess `"main"`, deliberately: a repo whose real default is `master` would
 * mount a branch that does not exist and die inside a paid run.
 *
 * Reads every credential from the environment, never from argv — a value in
 * argv lands in shell history and in `ps` output for the life of the process.
 */

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

  console.log("Paste these two fields into companies/<uid>/engineering/repo\n");
  console.log(JSON.stringify({ url: repoUrl, defaultBranch }, null, 2));
  console.log(
    "\nNo token here any more. `loadRepo` reads it from " +
      "companies/<uid>/connectors/github, which the GitHub OAuth callback\n" +
      "writes — one credential, one home. If that document does not exist, " +
      "connect GitHub first; a linked repo without\na connected account " +
      "resolves to 'connect a repo' rather than running on a stale copy."
  );
}

main().catch((err) => {
  console.error(err instanceof Error ? err.message : String(err));
  process.exit(1);
});

# Runbook: standing up the engineering backend

Task 10 splits into a scriptable half (two scripts + npm wiring, already
committed) and a human-gated half that needs live credentials, console
access, and a founder's Firestore document. This is the human-gated half —
the exact steps, in order, with the command for each and what a correct
result looks like.

Nothing in this document should be run by an agent unattended: every step
either spends real Anthropic credits, deploys to production, or requires
clicking through a console UI to obtain a secret that is shown exactly once.

---

## ⚠ Two things that have already cost this project real time

**Never name a local secrets file `.env` inside `functions/`.** `firebase
deploy` loads every `.env*` file it finds as ordinary env vars. A plain
`.env` collides with the handlers' `secrets: [...]` declarations (several
handlers declare `ANTHROPIC_API_KEY`, `ANTHROPIC_WEBHOOK_SIGNING_KEY`,
`CONNECTOR_ENC_KEY`, etc.) and the deploy fails outright with a 400.
- Deployed env vars go in **`functions/.env.devpet-8f4b1`** (the
  project-suffixed file firebase-functions v2 reads at deploy for project
  `devpet-8f4b1`) — this is the correct, deployed-side location, not the
  banned one.
- Local-only values go in **`functions/local.env`**, which is gitignored and
  never read by `firebase deploy`.

**Deploy scoped only** — `firebase deploy --only functions:a,functions:b,…`,
never a blanket `firebase deploy --only functions` or `firebase deploy`.
This repo has a second checkout that used to deploy to the same Firebase
project; a deploy from a branch that is behind `main` silently **deletes**
every function that exists in production but not in the branch's export set.
Before every deploy in this runbook:

```bash
cd ~/Developer/codepet/functions   # or this worktree's functions/
firebase functions:list
```

and confirm the set of functions you are about to export is a **superset**
of what `functions:list` shows as live. If it isn't, stop and find out why
before deploying anything.

---

## Step 1 — Provision the agent and environment

Scriptable, already committed as `functions/scripts/provision-eng-agent.ts`
(`npm run provision:eng`). A human still has to run it, because it needs a
real `ANTHROPIC_API_KEY` and its output has to be pasted into two files by
hand.

```bash
cd ~/Developer/codepet/functions
ANTHROPIC_API_KEY="$(grep ANTHROPIC_API_KEY local.env | cut -d= -f2-)" npm run provision:eng
```

**Correct result:** exactly three `KEY=value` lines on stdout, nothing else:

```
ENG_ENVIRONMENT_ID=env_...
ENG_AGENT_ID=agent_...
ENG_AGENT_VERSION=1
```

If it throws instead, the ids were never created — nothing partial to clean
up.

**Where the three ids go — both files, so local runs and deployed functions
agree:**

```bash
printf 'ENG_ENVIRONMENT_ID=env_...\nENG_AGENT_ID=agent_...\nENG_AGENT_VERSION=1\n' >> functions/local.env
printf 'ENG_ENVIRONMENT_ID=env_...\nENG_AGENT_ID=agent_...\nENG_AGENT_VERSION=1\n' >> functions/.env.devpet-8f4b1
```

(Substitute the real values printed above — don't literally append the
`...` placeholders.)

Re-running `provision:eng` does **not** update the agent in place — it
creates a second agent and a second environment with their own ids. Treat
this as truly one-time per environment; if you need to change the agent's
config later, do it through `client.beta.agents.update(...)`, or provision a
new one and cut the ids over deliberately, not by re-running this script.

---

## Step 2 — Deploy the four functions, scoped

The deployed `engStartRun` needs `ENG_AGENT_ID` / `ENG_AGENT_VERSION` /
`ENG_ENVIRONMENT_ID` from Step 1 already in `.env.devpet-8f4b1` before this
deploy, or every run will 500 with `misconfigured`.

```bash
cd ~/Developer/codepet
firebase functions:list      # confirm the export set below is a superset of this
firebase deploy --only functions:engStartRun,functions:engStream,functions:engSendTurn,functions:engWebhook
```

**Correct result:** the CLI reports all four functions deployed
successfully. `engWebhook` is live at this point but has no signing key yet
— that's fine, nothing calls it until Step 3 registers the endpoint.

---

## Step 3 — Register the webhook endpoint

Human-only: this happens in the Anthropic Console, and the secret it
produces is shown exactly once.

1. Anthropic Console → **Manage → Webhooks** → add endpoint:
   `https://us-central1-devpet-8f4b1.cloudfunctions.net/engWebhook`
2. Subscribe it to `session.status_idled` and `session.status_terminated`
   only — `engWebhook` (`functions/src/engineering/engWebhook.ts`) ignores
   every other event type with a 204, so subscribing to more just adds noise
   the handler discards.
3. Copy the `whsec_...` signing secret shown on the creation screen. **It is
   shown once.** If you navigate away without copying it, the only recovery
   is deleting the endpoint and creating a new one — there is no "reveal
   secret" button to come back to.

Set it for deployed functions and redeploy just the webhook handler:

```bash
printf 'ANTHROPIC_WEBHOOK_SIGNING_KEY=whsec_...\n' >> functions/.env.devpet-8f4b1
firebase functions:list      # re-confirm before every deploy, scoped or not
firebase deploy --only functions:engWebhook
```

**Correct result:** the console shows the endpoint as active. There is
nothing to curl to confirm this in isolation — it proves itself in Step 5,
when a real run's `status_idled`/`status_terminated` event lands and the run
doc's `status` field moves off `"running"`.

---

## Step 4 — Seed a repo link

Human-only: this is exactly the document Plan 2 (repo onboarding, not part
of this task) will eventually write automatically. For now, create it by
hand in Firestore at:

```
companies/<your-uid>/engineering/repo
```

**Required fields** — `loadRepo` (`functions/src/engineering/engRepo.ts`)
checks all three and returns `null` — silently, no thrown error — if any is
missing, which `engStartRun` turns into a 409 asking the founder to connect
a repo:

| field | shape | source |
|---|---|---|
| `url` | `"https://github.com/<owner>/<repo>"` | the scratch repo from Task 1 |
| `sealed` | `{ iv, tag, ciphertext }` (all base64 strings) | `sealToken(plaintext, CONNECTOR_ENC_KEY)` in `functions/src/oauth/githubOAuthCore.ts` |
| `defaultBranch` | plain string, e.g. `"main"` | `GET /repos/{owner}/{repo}` on the GitHub API → `default_branch` field |

**`defaultBranch` is the field most likely to be forgotten, and skipping it
does not fail loudly.** `loadRepo` fails **closed** without it: a doc
missing `defaultBranch` (or with a blank one) resolves to `null`, exactly
the same as no doc at all, and the founder sees "connect a repo" — it does
**not** guess `"main"`. A repo whose real default branch is `master` would,
under a guessed `"main"`, mount a `checkout: { branch: "main" }` that
doesn't exist and die with an obscure git error *inside a paid run*. Read
the real value from the GitHub API once, at seed time, rather than assuming.

To get a `sealed` value without the (not-yet-built) connect UI: run the
already-deployed `githubOAuthStart` / `githubOAuthCallback` flow for the
scratch repo's account, which writes a sealed token to
`companies/<uid>/connectors/github` — then either copy that document's
`sealed` object into the new `engineering/repo` doc, or call `sealToken`
directly against a personal access token scoped to the scratch repo, using
the same `CONNECTOR_ENC_KEY` the deployed functions use (find it in
`functions/local.env`, or wherever it's stored for this project's Secret
Manager).

**Correct result:** the document exists with all three fields set, matches
the table above, and `defaultBranch` is the repo's *actual* default branch,
not an assumption.

---

## Step 5 — Run the live verification

Scriptable, already committed as `functions/scripts/verify-eng-run.ts`
(`npm run verify:eng`). A human still runs it, because it spends real
credits against the real deployed backend and a real repo.

```bash
cd ~/Developer/codepet/functions
npm run token                      # prints an ID_TOKEN to stdout
ID_TOKEN=<paste> npm run verify:eng
```

(`ID_TOKEN` is read from the environment on purpose — never pass it as a
`--` argument. A token on the command line lands in shell history and in
`ps` output for as long as the process runs; a value read from
`process.env` does not.)

**Correct result — the sequence a healthy run produces:**

1. `runId: <id>` printed immediately after `engStartRun` responds.
2. A stream of `event: step` frames, each naming a real file the agent is
   touching (reads, edits, greps — see `toExecStep` in
   `functions/src/engineering/engEvents.ts` for what a step frame contains).
3. `event: approval` at least once, when the agent wants to run `bash` — the
   one tool in the provisioned agent's toolset with `always_ask`, per Step 1.
   Nothing auto-approves this; a real run stops here until something answers
   it. `verify-eng-run.ts` doesn't answer it either — it only tails and
   prints, so a run that has real bash work to do will sit at this frame.
4. `event: done` once the session reaches a terminal state
   (`session.status_terminated`, or `session.status_idle` whose stop reason
   isn't `requires_action`).

Then confirm the webhook actually fired — this is the one thing the stream
itself can't prove, since `engStream` only relays live events and the
billing/status write happens out-of-band in `engWebhook`:

- In Firestore, `companies/<uid>/engRuns/<runId>.status` should have moved
  to `"reviewing"` (or `"budgetReached"` / `"failed"` depending on how the
  run actually ended — see `statusFor` in
  `functions/src/engineering/engWebhook.ts`).
- `creditsSpent` on that same doc should be **non-zero**.

If the stream produces `event: done` but the Firestore doc is still stuck at
`status: "running"` with `creditsSpent: 0`, the webhook did not fire —
recheck Step 3 (endpoint URL, subscribed events, or the signing key actually
landing in `.env.devpet-8f4b1` before the `engWebhook` redeploy).

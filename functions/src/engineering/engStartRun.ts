//
// Start an engineering run: resolve the repo, size the budget from the
// founder's credits, create a Managed Agents session with the repo mounted,
// and record it. Returns as soon as the session exists — the transcript
// arrives over engStream, and the outcome is durable via engWebhook even if
// nobody connects.
import { Request } from "firebase-functions/v2/https";
import { Response } from "express";
import * as admin from "firebase-admin";
import * as logger from "firebase-functions/logger";
import type Anthropic from "@anthropic-ai/sdk";
import { verifyAuth } from "../auth";
import { creditsToBudget, type SessionBudget } from "./engBudget";
import { readBalance } from "./engBalance";
import { loadRepo, branchName, MOUNT_PATH, type RepoLink } from "./engRepo";
import {
  getEngClient,
  safeErrorDetail,
  ENG_AGENT_ID_ENV,
  ENG_AGENT_VERSION_ENV,
  ENG_ENVIRONMENT_ID_ENV,
  ENG_MODEL,
  type RunStatus
} from "./engClient";

// Aliased to the exact SDK param shapes `sessions.create` checks `SessionParams`
// against below (no cast) — narrower than the SDK's own field types where we
// only ever send one variant (a single GitHub-repo resource, a single
// user.message initial event), so a future change that drifts from what the
// API accepts fails to compile here instead of failing at Anthropic's edge.
type AgentWithOverrides = Anthropic.Beta.Sessions.BetaManagedAgentsAgentWithOverridesParams;
type GitHubRepoResource = Anthropic.Beta.Sessions.BetaManagedAgentsGitHubRepositoryResourceParams;
type UserMessageEventParams = Anthropic.Beta.Sessions.BetaManagedAgentsUserMessageEventParams;

export interface SessionParams {
  agent: AgentWithOverrides;
  environment_id: string;
  title: string;
  resources: GitHubRepoResource[];
  budget: SessionBudget;
  initial_events: UserMessageEventParams[];
  // Carries the run's identity on the session itself. When only the
  // post-create Firestore update fails, the run doc still gets
  // `reconcileNeeded: true` and `sessionId` (see handleEngStartRun below),
  // and a reconciler can query Firestore for that. This session metadata
  // is what would be left if BOTH follow-up writes fail: the doc stays at
  // `status: "starting"` with no `sessionId` and no flag, and this field is
  // the only surviving pointer to the run. No component in this codebase
  // currently reads session metadata to reconcile from it — that is a real,
  // known gap, not something this field closes by existing.
  metadata: { runId: string; uid: string };
}

function systemFor(repo: RepoLink, brief: string): string {
  return [
    "You are the engineering department of a founder's company.",
    `Their repository is mounted at ${MOUNT_PATH}; its default branch is ${repo.defaultBranch}.`,
    "",
    "Work on a branch, never on the default branch. Run the project's own tests",
    "before you report success, and say plainly when something fails rather than",
    "describing an intention as a result.",
    "",
    "The person reading your messages is a founder, not necessarily an engineer.",
    "Lead with what changed and what it means for their product; keep the",
    "implementation detail after that, for whoever wants it.",
    brief ? `\nAbout the company:\n${brief}` : ""
  ].join("\n");
}

/**
 * Pure: everything the session-create call needs.
 *
 * Split out from the handler because the security-relevant invariant lives
 * here — the GitHub token appears in the repo resource and nowhere else. A
 * test asserts that by serialising the params with resources removed.
 */
export function buildSessionParams(args: {
  agentId: string;
  agentVersion: number;
  environmentId: string;
  repo: RepoLink;
  credits: number;
  ask: string;
  brief: string;
  metadata: { runId: string; uid: string };
}): SessionParams {
  return {
    // Overrides, not a bare id: the brief is per-founder, and versioning an
    // agent per user would be a new immutable object on every brief edit.
    // The version is pinned so an agent update mid-run cannot change how a
    // session already in flight behaves.
    agent: {
      type: "agent_with_overrides",
      id: args.agentId,
      version: args.agentVersion,
      system: systemFor(args.repo, args.brief),
      model: ENG_MODEL
    },
    environment_id: args.environmentId,
    title: args.ask.slice(0, 80),
    resources: [
      {
        type: "github_repository",
        url: args.repo.url,
        authorization_token: args.repo.token,
        mount_path: MOUNT_PATH,
        checkout: { type: "branch", name: args.repo.defaultBranch }
      }
    ],
    budget: creditsToBudget(args.credits),
    // Seeding the kickoff here means the session is created already running.
    // Creating it idle and then sending would be two round trips and a window
    // where a founder sees a run that exists but is doing nothing.
    initial_events: [{ type: "user.message", content: [{ type: "text", text: args.ask }] }],
    metadata: args.metadata
  };
}

export async function handleEngStartRun(req: Request, res: Response): Promise<void> {
  if (req.method !== "POST") {
    res.status(405).json({ error: "method_not_allowed" });
    return;
  }
  const auth = await verifyAuth(req.headers.authorization);
  if (!auth) {
    res.status(401).json({ error: "invalid_token" });
    return;
  }

  const ask = typeof req.body?.ask === "string" ? req.body.ask.trim() : "";
  if (!ask) {
    res.status(400).json({ error: "invalid_payload", detail: "ask required" });
    return;
  }

  const encKey = process.env.CONNECTOR_ENC_KEY;
  if (!encKey) {
    // A deploy misconfiguration, not a per-request fault — no `err` to
    // inspect, so this is just a fixed, named message rather than
    // `safeErrorDetail`. Before Finding 5, every exit in this file logged
    // nothing at all, so a run that failed for exactly this reason produced
    // a 500 with nothing anywhere pointing at the missing env var.
    logger.error("engStartRun: CONNECTOR_ENC_KEY absent");
    res.status(500).json({ error: "misconfigured", detail: "CONNECTOR_ENC_KEY absent" });
    return;
  }

  let repo: RepoLink | null;
  try {
    repo = await loadRepo(auth.uid, encKey);
  } catch (err) {
    // Only a Firestore read fault reaches here. `loadRepo` swallows a decrypt
    // failure and returns null, so a corrupted token surfaces as 409 below —
    // "connect a repo" — which is the right outcome, since no retry will fix
    // it. Don't widen this catch to cover decryption; that case never arrives.
    //
    // 503 must not be mistakable for 409 (no repo linked) or 402 (no credits):
    // the client renders both of those as an offer to connect or upgrade, and a
    // storage outage is neither — it is ours, and it is retryable. Never echo
    // the error to the client; `safeErrorDetail` (see `engClient.ts`) is what
    // keeps the log itself content-free too.
    logger.error("engStartRun: repo lookup failed", safeErrorDetail(err));
    res.status(503).json({ error: "repo_lookup_failed" });
    return;
  }
  if (!repo) {
    // Not an error — the client renders connect-or-create from this.
    res.status(409).json({ error: "no_repo_linked" });
    return;
  }

  const db = admin.firestore();
  let company: FirebaseFirestore.DocumentData;
  let credits: number;
  try {
    // Two documents now, and only `brief` still comes from the company doc.
    // The balance moved to a write-denied subcollection: `companies/{uid}`'s
    // `allow update` guards ownership and nothing else, so a founder could
    // edit `credits` there — and this number becomes the session's
    // platform-enforced spend cap. See `engBalance.ts`.
    const companySnap = await db.doc(`companies/${auth.uid}`).get();
    company = companySnap.data() ?? {};
    // Inside the same try: a balance read that throws must produce this
    // handler's 503, not an unhandled rejection.
    credits = await readBalance(auth.uid);
  } catch (err) {
    // Same reasoning as the repo-lookup catch above: distinct from 409/402,
    // and the error itself never leaves this scope — only the two
    // content-free fields `safeErrorDetail` allows.
    logger.error("engStartRun: company lookup failed", safeErrorDetail(err));
    res.status(503).json({ error: "company_lookup_failed" });
    return;
  }
  // `readBalance` already collapses a missing document, NaN, Infinity and a
  // string to 0 — this is the honest 402 for a founder who is genuinely out,
  // and the belt against a corrupted balance starting a one-cent run that
  // dies at its budget a second later. engBudget guards the same thing again.
  if (credits <= 0) {
    res.status(402).json({ error: "no_credits" });
    return;
  }

  const agentId = process.env[ENG_AGENT_ID_ENV];
  const agentVersion = Number(process.env[ENG_AGENT_VERSION_ENV]);
  const environmentId = process.env[ENG_ENVIRONMENT_ID_ENV];
  if (!agentId || !environmentId || !Number.isFinite(agentVersion)) {
    // Another deploy misconfiguration, no `err` involved — naming which of
    // the three env vars is missing/malformed is itself content-free (it's
    // our own config shape, not anything a founder supplied) and is exactly
    // the diagnostic signal that was absent before Finding 5.
    logger.error("engStartRun: engineering agent not provisioned", {
      hasAgentId: Boolean(agentId),
      hasEnvironmentId: Boolean(environmentId),
      agentVersionIsFinite: Number.isFinite(agentVersion)
    });
    res.status(500).json({ error: "misconfigured", detail: "engineering agent not provisioned" });
    return;
  }

  // The run record is created BEFORE the remote call, not after. The remote
  // session starts billing against its budget the moment it exists; if we
  // created it first and wrote the record second, a failed write would
  // orphan a billing session with nothing pointing at it, and because the
  // original code never awaited/handled that write, the rejection would go
  // unhandled and the client would simply hang. Creating the record first
  // means a founder can never see credits spent on a run that isn't tracked
  // — and because this write is itself guarded below, a failure here is
  // caught before any session (and any billing) exists at all.
  const runRef = db.collection(`companies/${auth.uid}/engRuns`).doc();
  try {
    await runRef.set({
      ask,
      repo: repo.url,
      branch: branchName(runRef.id),
      baseBranch: repo.defaultBranch,
      status: "starting" as RunStatus,
      creditsSpent: 0,
      createdAt: admin.firestore.FieldValue.serverTimestamp()
    });
  } catch (err) {
    // Nothing has been created or billed yet, so there is nothing to roll
    // back — just fail into a defined response instead of an unhandled
    // rejection (the hang this file exists to avoid), distinct from 409/402
    // for the same reason as the read guards above.
    logger.error("engStartRun: run create failed", safeErrorDetail(err));
    res.status(503).json({ error: "run_create_failed" });
    return;
  }

  const params = buildSessionParams({
    agentId,
    agentVersion,
    environmentId,
    repo,
    credits,
    ask,
    brief: typeof company.brief === "string" ? company.brief : "",
    // See the `metadata` field doc on SessionParams above for what this
    // does and does not cover.
    metadata: { runId: runRef.id, uid: auth.uid }
  });

  let sessionId: string;
  try {
    const session = await getEngClient().beta.sessions.create(params);
    sessionId = session.id;
  } catch (err) {
    // Never put `err` itself — or String(err), or a stringification of it —
    // anywhere the client or a log can see it. Not because the SDK's error
    // carries the request we made (`APIError` exposes `status`, RESPONSE
    // headers, the response body, and `requestID` — never the request or
    // its headers; see `safeErrorDetail`'s doc comment in `engClient.ts`).
    // The real risk is the response BODY: a 400 from `sessions.create` can
    // echo back the resource it rejected, and the resource we just sent
    // embeds the founder's decrypted GitHub token
    // (`authorization_token`). `safeErrorDetail` is the one place allowed
    // to look at `err` at all, and it only ever returns two named,
    // content-free fields — never `.error`, `.message`, or the object
    // itself.
    logger.error("engStartRun: session create failed", safeErrorDetail(err));
    try {
      await runRef.update({ status: "failed" as RunStatus });
    } catch {
      // Best-effort: if this also fails, the doc is stuck at "starting",
      // which is the pre-existing (and separately understood) failure mode
      // for a Firestore outage, not something this fix needs to solve.
    }
    res.status(502).json({ error: "session_create_failed" });
    return;
  }

  try {
    await runRef.update({ sessionId, status: "running" as RunStatus });
  } catch {
    // The session exists and is billing; this write just didn't land. Don't
    // hang the request over it — the client still gets its runId. Record
    // the failure as a field a reconciler can query for, not a log line.
    //
    // This IS recoverable, but only up to here: if the fallback write below
    // also succeeds, the doc carries `reconcileNeeded: true` and
    // `sessionId`, and a reconciler can query Firestore for exactly that.
    try {
      await runRef.update({ reconcileNeeded: true, sessionId });
    } catch {
      // Both updates failed. The doc is left at status:"starting" with no
      // sessionId and no reconcileNeeded flag — nothing on the document
      // points a reconciler at this run. The session's own metadata
      // (runId/uid, see SessionParams above) is the only surviving pointer,
      // but no component in this codebase reads session metadata to
      // reconcile from it today. That is a known, unclosed gap: whoever
      // builds the reconciler needs a path that lists/queries sessions
      // directly, not just Firestore documents, or this case is silently
      // unrecoverable.
    }
  }

  res.status(200).json({ runId: runRef.id, sessionId });
}

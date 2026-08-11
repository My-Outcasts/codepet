//
// Start an engineering run: resolve the repo, size the budget from the
// founder's credits, create a Managed Agents session with the repo mounted,
// and record it. Returns as soon as the session exists — the transcript
// arrives over engStream, and the outcome is durable via engWebhook even if
// nobody connects.
import { Request } from "firebase-functions/v2/https";
import { Response } from "express";
import * as admin from "firebase-admin";
import { verifyAuth } from "../auth";
import { creditsToBudget, type SessionBudget } from "./engBudget";
import { loadRepo, branchName, MOUNT_PATH, type RepoLink } from "./engRepo";
import {
  getEngClient,
  ENG_AGENT_ID_ENV,
  ENG_AGENT_VERSION_ENV,
  ENG_ENVIRONMENT_ID_ENV,
  ENG_MODEL
} from "./engClient";

export interface SessionParams {
  agent: {
    type: "agent_with_overrides";
    id: string;
    version: number;
    system: string;
    model: string;
  };
  environment_id: string;
  title: string;
  resources: Array<Record<string, unknown>>;
  budget: SessionBudget;
  initial_events: Array<{ type: string; content: Array<{ type: "text"; text: string }> }>;
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
    initial_events: [{ type: "user.message", content: [{ type: "text", text: args.ask }] }]
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
    res.status(500).json({ error: "misconfigured", detail: "CONNECTOR_ENC_KEY absent" });
    return;
  }

  const repo = await loadRepo(auth.uid, encKey);
  if (!repo) {
    // Not an error — the client renders connect-or-create from this.
    res.status(409).json({ error: "no_repo_linked" });
    return;
  }

  const db = admin.firestore();
  const companySnap = await db.doc(`companies/${auth.uid}`).get();
  const company = companySnap.data() ?? {};
  // `Number.isFinite`, not `typeof === "number"`: `typeof NaN === "number"` is
  // true, and `NaN <= 0` is false, so a corrupted balance field would sail past
  // a naive check and start a run. engBudget guards this too — the belt here is
  // so a founder with a broken balance gets an honest 402 rather than a one-cent
  // run that dies at its budget a second later.
  const credits = Number.isFinite(company.credits) ? (company.credits as number) : 0;
  if (credits <= 0) {
    res.status(402).json({ error: "no_credits" });
    return;
  }

  const agentId = process.env[ENG_AGENT_ID_ENV];
  const agentVersion = Number(process.env[ENG_AGENT_VERSION_ENV]);
  const environmentId = process.env[ENG_ENVIRONMENT_ID_ENV];
  if (!agentId || !environmentId || !Number.isFinite(agentVersion)) {
    res.status(500).json({ error: "misconfigured", detail: "engineering agent not provisioned" });
    return;
  }

  const runRef = db.collection(`companies/${auth.uid}/engRuns`).doc();
  const params = buildSessionParams({
    agentId,
    agentVersion,
    environmentId,
    repo,
    credits,
    ask,
    brief: typeof company.brief === "string" ? company.brief : ""
  });

  let sessionId: string;
  try {
    const session = await getEngClient().beta.sessions.create(params as never);
    sessionId = session.id;
  } catch (err) {
    res.status(502).json({ error: "session_create_failed", detail: String(err) });
    return;
  }

  await runRef.set({
    sessionId,
    ask,
    repo: repo.url,
    branch: branchName(runRef.id),
    baseBranch: repo.defaultBranch,
    status: "running",
    creditsSpent: 0,
    createdAt: admin.firestore.FieldValue.serverTimestamp()
  });

  res.status(200).json({ runId: runRef.id, sessionId });
}

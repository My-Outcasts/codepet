import { onRequest } from "firebase-functions/v2/https";
import { setGlobalOptions } from "firebase-functions/v2";
import * as admin from "firebase-admin";
import { handleSummarizeTurn } from "./summarizeTurn";
import { handleSummarizeSession } from "./summarizeSession";
import { handleChatSession } from "./chat";
import { handleGenerateGuidance } from "./generateGuidance";
import { handleGeneratePlan } from "./generatePlan";
import { handleDistillReference } from "./distillReference";
import { handleSynthesizeBrief } from "./synthesizeBrief";
import { handleRevenueCatWebhook } from "./revenueCatWebhook";
import { handleExtractKnowledge } from "./extractKnowledge";
import { handleGenerateDictionary } from "./generateDictionary";
import { handleVirtualCompanyRun } from "./company/virtualCompany";
// Consolidated in from the Murror/CodePet-Clean checkout, which until now was a
// second, competing source for this same Firebase codebase ("default" on
// devpet-8f4b1). Two sources meant a deploy from either one offered to delete
// the other's functions, so the Virtual Company backend could never ship. This
// repo is now the only source.
import { handleScaffoldRoadmap } from "./scaffoldRoadmap";
import { handleEnrichBrief } from "./enrichBrief";
import { handleCompanyChat } from "./companyChat";
import { handleRunTask } from "./runTask";
import { handleGenerateRoadmap } from "./generateRoadmap";
import { handleExtractDecisions } from "./extractDecisions";
import { handleGithubOAuthStart, handleGithubOAuthCallback } from "./oauth/githubOAuth";
import { handleEngStartRun } from "./engineering/engStartRun";
import { handleEngStream } from "./engineering/engStream";
import {
  handleEngListRepos,
  handleEngLinkRepo,
  handleEngCreateRepo
} from "./engineering/engRepoHandlers";
import { handleEngShip, handleEngPreview } from "./engineering/engShip";
import { handleEngWebhook } from "./engineering/engWebhook";
import { handleEngSendTurn } from "./engineering/engSendTurn";

admin.initializeApp();
setGlobalOptions({ region: "us-central1", maxInstances: 10 });

// minInstances: 1 keeps a single warm container alive so the first
// summarize call after idle doesn't pay a 5–30s cold-start penalty.
// Cost: ~$5–8 / month per warm instance. Applied only to summarizeTurn —
// chatSession streams so cold start is masked, and summarizeSession fires
// less frequently.
export const summarizeTurn = onRequest(
  {
    cors: false,
    secrets: ["ANTHROPIC_API_KEY"],
    minInstances: 1
  },
  handleSummarizeTurn
);

export const summarizeSession = onRequest(
  {
    cors: false,
    secrets: ["ANTHROPIC_API_KEY"]
  },
  handleSummarizeSession
);

export const chatSession = onRequest(
  {
    cors: false,
    secrets: ["ANTHROPIC_API_KEY"]
  },
  handleChatSession
);

export const scaffoldRoadmap = onRequest(
  {
    cors: false,
    secrets: ["ANTHROPIC_API_KEY"]
  },
  handleScaffoldRoadmap
);

export const enrichBrief = onRequest(
  {
    cors: false,
    secrets: ["ANTHROPIC_API_KEY"]
  },
  handleEnrichBrief
);

// CONNECTOR_ENC_KEY opens the founder's stored connector tokens so Claude can
// reach their MCP servers. Absent, chat still runs — just without connectors.
export const companyChat = onRequest(
  {
    cors: false,
    secrets: ["ANTHROPIC_API_KEY", "CONNECTOR_ENC_KEY"]
  },
  handleCompanyChat
);

// The GitHub connector's consent round-trip. `githubOAuthCallback` is reached by
// a browser redirect from GitHub, not by the app, so it is deliberately NOT
// authenticated — the signed `state` minted by `githubOAuthStart` is what proves
// which founder the callback belongs to.
export const githubOAuthStart = onRequest(
  {
    cors: false,
    secrets: ["GITHUB_OAUTH_CLIENT_ID", "CONNECTOR_ENC_KEY"]
  },
  handleGithubOAuthStart
);

export const githubOAuthCallback = onRequest(
  {
    cors: false,
    secrets: ["GITHUB_OAUTH_CLIENT_ID", "GITHUB_OAUTH_CLIENT_SECRET", "CONNECTOR_ENC_KEY"]
  },
  handleGithubOAuthCallback
);

export const runTask = onRequest(
  {
    cors: false,
    secrets: ["ANTHROPIC_API_KEY"]
  },
  handleRunTask
);

// The engineering coding agent. CONNECTOR_ENC_KEY opens the founder's stored
// GitHub token so the session can mount their repo; the token is handed to the
// session resource and never enters the container.
export const engStartRun = onRequest(
  {
    cors: false,
    secrets: ["ANTHROPIC_API_KEY", "CONNECTOR_ENC_KEY"]
  },
  handleEngStartRun
);

// Long-lived SSE. timeoutSeconds is the v2 maximum (60 min); a run longer
// than that survives because engWebhook records the outcome independently.
export const engStream = onRequest(
  {
    cors: false,
    secrets: ["ANTHROPIC_API_KEY"],
    timeoutSeconds: 3600
  },
  handleEngStream
);

// Reached by Anthropic, not by the app, so it is deliberately NOT
// authenticated — the HMAC signature verified inside the handler is what
// proves the caller. Mirrors githubOAuthCallback and revenueCatWebhook.
export const engWebhook = onRequest(
  {
    cors: false,
    secrets: ["ANTHROPIC_API_KEY", "ANTHROPIC_WEBHOOK_SIGNING_KEY"]
  },
  handleEngWebhook
);

// Everything the founder sends into a live session: a follow-up, a tool
// approval, or a stop.
// Repo onboarding: what a founder hits before their first run. Both need
// CONNECTOR_ENC_KEY to open the GitHub token the OAuth callback sealed; they
// do not touch Anthropic, so they do not declare ANTHROPIC_API_KEY.
export const engListRepos = onRequest(
  {
    cors: false,
    secrets: ["CONNECTOR_ENC_KEY"]
  },
  handleEngListRepos
);

export const engLinkRepo = onRequest(
  {
    cors: false,
    secrets: ["CONNECTOR_ENC_KEY"]
  },
  handleEngLinkRepo
);

export const engCreateRepo = onRequest(
  {
    cors: false,
    secrets: ["CONNECTOR_ENC_KEY"]
  },
  handleEngCreateRepo
);

// What happens after the diff. engShip opens a PULL REQUEST — it does not
// merge; see the header of engShip.ts for why the label and the action differ.
export const engShip = onRequest(
  {
    cors: false,
    secrets: ["CONNECTOR_ENC_KEY"]
  },
  handleEngShip
);

export const engPreview = onRequest(
  {
    cors: false,
    secrets: ["CONNECTOR_ENC_KEY"]
  },
  handleEngPreview
);

export const engSendTurn = onRequest(
  {
    cors: false,
    secrets: ["ANTHROPIC_API_KEY"]
  },
  handleEngSendTurn
);

export const generateRoadmap = onRequest(
  {
    cors: false,
    secrets: ["ANTHROPIC_API_KEY"]
  },
  handleGenerateRoadmap
);

export const extractDecisions = onRequest(
  {
    cors: false,
    secrets: ["ANTHROPIC_API_KEY"]
  },
  handleExtractDecisions
);

export const generateGuidance = onRequest(
  {
    cors: false,
    secrets: ["ANTHROPIC_API_KEY"]
  },
  handleGenerateGuidance
);

export const generatePlan = onRequest(
  {
    cors: false,
    secrets: ["ANTHROPIC_API_KEY"]
  },
  handleGeneratePlan
);

export const distillReference = onRequest(
  {
    cors: false,
    secrets: ["ANTHROPIC_API_KEY"]
  },
  handleDistillReference
);

export const synthesizeBrief = onRequest(
  {
    cors: false,
    secrets: ["ANTHROPIC_API_KEY"]
  },
  handleSynthesizeBrief
);

// RevenueCat -> Firestore entitlements bridge. No declared secret so it can
// deploy inert before RevenueCat is connected; reads REVENUECAT_WEBHOOK_TOKEN
// from env at runtime (rejects all requests until that is set).
export const revenueCatWebhook = onRequest(
  {
    cors: false
  },
  handleRevenueCatWebhook
);

export const extractKnowledge = onRequest(
  {
    cors: false,
    secrets: ["ANTHROPIC_API_KEY"]
  },
  handleExtractKnowledge
);

// Project-aware Dictionary: detected terms from the user's own code → plain,
// pet-voiced cards. Free in beta; per-term server cache (dictionary_cache,
// 30-day TTL) keeps repeat opens cheap.
export const generateDictionary = onRequest(
  {
    cors: false,
    secrets: ["ANTHROPIC_API_KEY"]
  },
  handleGenerateDictionary
);

// Virtual Company: 4 agents analyse a founder's decision independently, surface
// where they disagree, negotiate under a 2-round cap, then synthesise a brief.
// Streams SSE — see docs/superpowers/specs/virtual-company-sse-contract.md for
// the event contract the client consumes.
//
// timeoutSeconds is raised because a full multi_agent run makes up to 8 model
// calls across five phases (intake, 2 positions in parallel, up to 4
// negotiation turns, a red team pass, synthesis). The default 60s would cut a
// legitimate run off mid-phase.
export const virtualCompanyRun = onRequest(
  {
    cors: false,
    secrets: ["ANTHROPIC_API_KEY"],
    timeoutSeconds: 540
  },
  handleVirtualCompanyRun
);

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

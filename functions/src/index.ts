import { onRequest } from "firebase-functions/v2/https";
import { setGlobalOptions } from "firebase-functions/v2";
import * as admin from "firebase-admin";
import { handleRevenueCatWebhook } from "./revenueCatWebhook";
import { handleCapabilities } from "./capabilities";
import { handleGithubOAuthStart, handleGithubOAuthCallback } from "./oauth/githubOAuth";
import {
  handleEngListRepos,
  handleEngLinkRepo,
  handleEngCreateRepo
} from "./engineering/engRepoHandlers";
import { handleEngShip, handleEngPreview } from "./engineering/engShip";
import { handleEngDiff } from "./engineering/engDiff";

admin.initializeApp();
setGlobalOptions({ region: "us-central1", maxInstances: 10 });

// Which skills the backend implements, so the Environment tab can tell a built
// item from an unbuilt one. Unauthenticated by design — a static constant with
// no founder data, read on first paint before a token necessarily exists.
export const capabilities = onRequest({ cors: false }, handleCapabilities);

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

// Repo onboarding: what a founder hits before their first run. Both need
// CONNECTOR_ENC_KEY to open the GitHub token the OAuth callback sealed; they
// do not touch Anthropic, so they do not declare ANTHROPIC_API_KEY — which is
// why they outlived the run itself.
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

// The diff the Review pane renders. base...head from GitHub, because the
// agent's narration is a claim and the compare is the fact.
export const engDiff = onRequest(
  {
    cors: false,
    secrets: ["CONNECTOR_ENC_KEY"]
  },
  handleEngDiff
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

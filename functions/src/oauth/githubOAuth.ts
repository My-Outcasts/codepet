// The two HTTP endpoints of the GitHub connector's consent round-trip.
//
//   app → githubOAuthStart (authenticated)   → { authorizeUrl }
//   app → ASWebAuthenticationSession(authorizeUrl)
//   GitHub → githubOAuthCallback (browser)   → stores the token
//                                            → 302 codepet://oauth/callback
//
// The final redirect to the custom scheme is what lets
// `ASWebAuthenticationSession` close itself: GitHub will only redirect to an
// http(s) callback, so the browser has to land here first and then be handed
// back to the app.
import type { Request } from "firebase-functions/v2/https";
import type { Response } from "express";
import * as admin from "firebase-admin";
import { verifyAuth } from "../auth";
import {
  signState,
  verifyState,
  buildAuthorizeUrl,
  exchangeCode,
  sealToken,
  GITHUB_MCP_URL
} from "./githubOAuthCore";

/** Where GitHub sends the browser back. Must match the OAuth app's registered callback exactly. */
export function redirectUri(): string {
  return (
    process.env.GITHUB_OAUTH_REDIRECT_URI ??
    "https://us-central1-devpet-8f4b1.cloudfunctions.net/githubOAuthCallback"
  );
}

/** Where the browser is sent once we're done, so the app's session closes. */
function appReturn(status: "ok" | "error", reason?: string): string {
  const q = new URLSearchParams({ provider: "github", status });
  if (reason) q.set("reason", reason);
  return `codepet://oauth/callback?${q.toString()}`;
}

function requiredSecret(name: string): string {
  const v = process.env[name];
  if (!v) throw new Error(`${name} not set`);
  return v;
}

/**
 * Hands the app a consent URL for the signed-in founder. Authenticated, because
 * the `state` it mints is what binds the eventual callback to this uid — an
 * unauthenticated caller could otherwise mint a state for someone else.
 */
export async function handleGithubOAuthStart(req: Request, res: Response): Promise<void> {
  const auth = await verifyAuth(req.headers.authorization);
  if (!auth) {
    res.status(401).json({ error: "invalid_token" });
    return;
  }
  try {
    const state = signState(auth.uid, requiredSecret("CONNECTOR_ENC_KEY"));
    const url = buildAuthorizeUrl(requiredSecret("GITHUB_OAUTH_CLIENT_ID"), redirectUri(), state);
    res.status(200).json({ authorizeUrl: url });
  } catch (err) {
    console.error("[githubOAuthStart]", err instanceof Error ? err.message : err);
    res.status(500).json({ error: "oauth_not_configured" });
  }
}

/**
 * The browser redirect from GitHub. Every exit is a 302 back into the app rather
 * than an error page — the founder is looking at a browser window they did not
 * choose to open, so the app is the only sane place to report what happened.
 */
export async function handleGithubOAuthCallback(req: Request, res: Response): Promise<void> {
  const code = typeof req.query.code === "string" ? req.query.code : "";
  const state = typeof req.query.state === "string" ? req.query.state : "";

  // The founder pressed Cancel on GitHub's consent screen.
  if (typeof req.query.error === "string" && req.query.error) {
    res.redirect(302, appReturn("error", "denied"));
    return;
  }
  if (!code || !state) {
    res.redirect(302, appReturn("error", "missing_params"));
    return;
  }

  try {
    const encKey = requiredSecret("CONNECTOR_ENC_KEY");
    const claims = verifyState(state, encKey);
    if (!claims) {
      res.redirect(302, appReturn("error", "bad_state"));
      return;
    }

    const token = await exchangeCode({
      code,
      clientId: requiredSecret("GITHUB_OAUTH_CLIENT_ID"),
      clientSecret: requiredSecret("GITHUB_OAUTH_CLIENT_SECRET"),
      redirectUri: redirectUri()
    });

    // Two documents, because they have two different audiences.
    //
    //   connectors/github       sealed token — closed to every client (rules deny
    //                           read outright); only the chat CF opens it.
    //   connectorStatus/github  no secrets — what the Environment surface renders
    //                           to answer "is GitHub connected?" without the
    //                           token ever being client-readable.
    //
    // One batch so the UI can never show "connected" for a token that failed to
    // land, or hide a token that did.
    const db = admin.firestore();
    const now = admin.firestore.FieldValue.serverTimestamp();
    const batch = db.batch();

    batch.set(
      db.doc(`companies/${claims.uid}/connectors/github`),
      {
        provider: "github",
        // Stored beside the token so the chat CF builds `mcp_servers` from one
        // read, with no hardcoded URL to drift.
        mcpUrl: GITHUB_MCP_URL,
        tokenType: token.tokenType,
        sealed: sealToken(token.accessToken, encKey),
        updatedAt: now
      },
      { merge: true }
    );

    batch.set(
      db.doc(`companies/${claims.uid}/connectorStatus/github`),
      { provider: "github", connected: true, scope: token.scope, connectedAt: now },
      { merge: true }
    );

    await batch.commit();

    res.redirect(302, appReturn("ok"));
  } catch (err) {
    // Never echo the failure to the browser: it can carry GitHub's response body.
    console.error("[githubOAuthCallback]", err instanceof Error ? err.message : err);
    res.redirect(302, appReturn("error", "exchange_failed"));
  }
}

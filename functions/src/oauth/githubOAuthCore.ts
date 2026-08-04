// Pure logic for the GitHub OAuth connector — no firebase/express imports, so it
// can be unit-tested without the emulator (same split as companyChatCore.ts).
//
// Why a signed `state` and no PKCE: the token exchange happens in the Cloud
// Function, which holds the client secret, so this is a *confidential* client.
// PKCE exists to protect public clients that cannot keep a secret; here it would
// add moving parts without adding protection. What we do need is CSRF defence and
// a way to know *which* user a browser redirect belongs to — the callback arrives
// with no Authorization header — and a signed, expiring state carries both.
import { createHmac, timingSafeEqual, randomBytes, createCipheriv, createDecipheriv } from "crypto";

/** GitHub's hosted MCP server — the endpoint Claude will call with the token. */
export const GITHUB_MCP_URL = "https://api.githubcopilot.com/mcp/";

/**
 * Scopes requested at consent. Deliberately narrow: `read:user` identifies the
 * account in the UI, `repo` is what GitHub's MCP server needs to see issues and
 * pull requests on private repositories. Tighten to `public_repo` if private
 * access is ever dropped — widening later costs a re-consent, so start small.
 */
export const GITHUB_SCOPES = ["read:user", "repo"] as const;

/** A state is only good for one consent round-trip. */
export const STATE_TTL_MS = 10 * 60 * 1000;

export interface StatePayload {
  uid: string;
  nonce: string;
  exp: number;
}

function b64url(buf: Buffer): string {
  return buf.toString("base64").replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

function fromB64url(s: string): Buffer {
  return Buffer.from(s.replace(/-/g, "+").replace(/_/g, "/"), "base64");
}

/** `<base64url(payload)>.<base64url(hmac)>` — opaque to the browser, verifiable by us. */
export function signState(uid: string, secret: string, now = Date.now()): string {
  const payload: StatePayload = { uid, nonce: b64url(randomBytes(16)), exp: now + STATE_TTL_MS };
  const body = b64url(Buffer.from(JSON.stringify(payload), "utf8"));
  const mac = b64url(createHmac("sha256", secret).update(body).digest());
  return `${body}.${mac}`;
}

/**
 * Returns the payload, or null for anything that isn't a state we issued and that
 * is still valid. Null is deliberately undifferentiated — a caller that told the
 * browser *why* verification failed would be an oracle.
 */
export function verifyState(state: string, secret: string, now = Date.now()): StatePayload | null {
  const parts = state.split(".");
  if (parts.length !== 2) return null;
  const [body, mac] = parts;

  const expected = createHmac("sha256", secret).update(body).digest();
  const given = fromB64url(mac);
  // Compare in constant time, and only when the lengths already match —
  // timingSafeEqual throws on a length mismatch rather than returning false.
  if (given.length !== expected.length) return null;
  if (!timingSafeEqual(given, expected)) return null;

  let parsed: StatePayload;
  try {
    parsed = JSON.parse(fromB64url(body).toString("utf8")) as StatePayload;
  } catch {
    return null;
  }
  if (typeof parsed.uid !== "string" || !parsed.uid) return null;
  if (typeof parsed.exp !== "number" || parsed.exp <= now) return null;
  return parsed;
}

export function buildAuthorizeUrl(clientId: string, redirectUri: string, state: string): string {
  const q = new URLSearchParams({
    client_id: clientId,
    redirect_uri: redirectUri,
    scope: GITHUB_SCOPES.join(" "),
    state,
    allow_signup: "false"
  });
  return `https://github.com/login/oauth/authorize?${q.toString()}`;
}

// ---------------------------------------------------------------------------
// Token at rest
// ---------------------------------------------------------------------------

export interface SealedToken {
  iv: string;
  tag: string;
  ciphertext: string;
}

function keyFrom(secret: string): Buffer {
  const key = Buffer.from(secret, "base64");
  if (key.length !== 32) {
    throw new Error("CONNECTOR_ENC_KEY must be 32 bytes, base64-encoded");
  }
  return key;
}

/**
 * AES-256-GCM. GCM rather than CBC so the stored blob is tamper-evident: a
 * modified ciphertext fails the tag check on open instead of decrypting to
 * plausible garbage that we would then send to GitHub as a bearer token.
 */
export function sealToken(plaintext: string, secret: string): SealedToken {
  const iv = randomBytes(12);
  const cipher = createCipheriv("aes-256-gcm", keyFrom(secret), iv);
  const ct = Buffer.concat([cipher.update(plaintext, "utf8"), cipher.final()]);
  return {
    iv: iv.toString("base64"),
    tag: cipher.getAuthTag().toString("base64"),
    ciphertext: ct.toString("base64")
  };
}

export function openToken(sealed: SealedToken, secret: string): string {
  const decipher = createDecipheriv("aes-256-gcm", keyFrom(secret), Buffer.from(sealed.iv, "base64"));
  decipher.setAuthTag(Buffer.from(sealed.tag, "base64"));
  return Buffer.concat([
    decipher.update(Buffer.from(sealed.ciphertext, "base64")),
    decipher.final()
  ]).toString("utf8");
}

// ---------------------------------------------------------------------------
// Token exchange
// ---------------------------------------------------------------------------

export interface ExchangeResult {
  accessToken: string;
  scope: string;
  tokenType: string;
}

/**
 * Swap the consent `code` for a token. GitHub answers 200 with an `error` field
 * on failure rather than a non-2xx status, so the body is checked, not the status.
 */
export async function exchangeCode(params: {
  code: string;
  clientId: string;
  clientSecret: string;
  redirectUri: string;
  fetchImpl?: typeof fetch;
}): Promise<ExchangeResult> {
  const doFetch = params.fetchImpl ?? fetch;
  const res = await doFetch("https://github.com/login/oauth/access_token", {
    method: "POST",
    headers: { "content-type": "application/json", accept: "application/json" },
    body: JSON.stringify({
      client_id: params.clientId,
      client_secret: params.clientSecret,
      code: params.code,
      redirect_uri: params.redirectUri
    })
  });

  const body = (await res.json()) as Record<string, string>;
  if (body.error || !body.access_token) {
    // Surface GitHub's own code, never the secret or the raw body.
    throw new Error(`github_oauth_exchange_failed:${body.error ?? "no_access_token"}`);
  }
  return {
    accessToken: body.access_token,
    scope: body.scope ?? "",
    tokenType: body.token_type ?? "bearer"
  };
}

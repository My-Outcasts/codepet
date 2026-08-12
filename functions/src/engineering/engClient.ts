//
// One Anthropic client for every engineering handler, built lazily so the
// module can be imported by tests that never touch the network.
import Anthropic from "@anthropic-ai/sdk";

/**
 * The model engineering runs use. Spec §11 leaves Opus 5 vs. Sonnet 5 open
 * as a margin decision — this constant is the single place that changes.
 */
export const ENG_MODEL = "claude-opus-5";

/** Set at deploy from the agent created by `scripts/provision-eng-agent.ts`. */
export const ENG_AGENT_ID_ENV = "ENG_AGENT_ID";
export const ENG_AGENT_VERSION_ENV = "ENG_AGENT_VERSION";
export const ENG_ENVIRONMENT_ID_ENV = "ENG_ENVIRONMENT_ID";

/**
 * Every value any engineering handler writes to an `engRuns/{id}.status`
 * field, in one place. `engStartRun` writes `starting`/`running`/`failed`;
 * `engWebhook` (durable-outcome handler) additionally writes
 * `reviewing`/`budgetReached`. Both handlers import this rather than each
 * declaring their own string literals, so the two vocabularies cannot drift
 * apart the way they would if each handler typed its own union.
 */
export type RunStatus = "starting" | "running" | "reviewing" | "budgetReached" | "failed";

let client: Anthropic | null = null;

export function getEngClient(): Anthropic {
  if (!client) client = new Anthropic({ apiKey: process.env.ANTHROPIC_API_KEY });
  return client;
}

/**
 * A path segment is safe to interpolate into a Firestore document path only
 * when it cannot contain a "/" — which either makes `db.doc(...)` throw
 * synchronously (an odd resulting segment count) or silently redirects the
 * operation to a different, caller-influenced document within the same
 * project (an even segment count, no throw at all) — and is not Firestore's
 * own reserved `__…__` document-id form, which addresses metadata Firestore
 * treats specially, never an ordinary application document.
 *
 * Lives here, rather than being exported from whichever engineering handler
 * defined it first, because this module is the one every handler already
 * imports (`getEngClient`) — so no handler needs to import a sibling
 * handler just to reuse this rule.
 */
export function isSafePathSegment(value: string): boolean {
  return value.length > 0 && !value.includes("/") && !/^__.*__$/.test(value);
}

/**
 * Content-free fields only: an error's constructor name, an HTTP status if
 * the SDK error exposes one (Anthropic's `APIError.status`), and — since Aug
 * 12 2026 — the envelope's `error.type`, but ONLY when it matches
 * `KNOWN_ERROR_TYPES` below. Never the error object, its `message`, or a
 * stringification.
 *
 * This is deliberately narrower than it needs to be for the actual SDK error
 * shape (see below), not because the shape is dangerous but because naming
 * exactly these fields is what keeps every call site honest — there is no
 * broader "safe subset" to reach for when a future field looks tempting to
 * add. `APIError` exposes `status`, the RESPONSE headers, the response body
 * (`error`), and `requestID` — never the request or its headers, so this is
 * not about hiding a bearer token the SDK's own error type might carry
 * (it doesn't carry one). The real risk lives in the response BODY: a 400
 * from `sessions.create` can echo back the invalid resource it rejected,
 * and that resource is where this codebase's own GitHub token lives
 * (`authorization_token`, set in `engStartRun.ts`). Never log the error
 * object itself, or any field pulled from `.error`/`.message`/a
 * stringification of it — only the two named fields below.
 *
 * Lives here, not in whichever handler defined it first (`engStream.ts`),
 * because `engStartRun.ts` needs it too and this module is the one every
 * engineering handler already imports.
 */
/**
 * The only values `safeErrorDetail` will ever emit for `errorType`.
 *
 * An ALLOWLIST, not a shape check, and that distinction is the whole point.
 * `error.type` is a closed enum in Anthropic's error envelope today, but the
 * field sits inside the response BODY — the same body the doc comment above
 * explains can echo back the rejected resource, GitHub token included. A
 * passthrough would be one API change away from logging free text from
 * inside that body. Matching against a fixed list means an unrecognised
 * value is dropped, not logged, whatever it contains.
 */
const KNOWN_ERROR_TYPES = new Set([
  "invalid_request_error",
  "authentication_error",
  "billing_error",
  "permission_error",
  "not_found_error",
  "request_too_large",
  "rate_limit_error",
  "api_error",
  "overloaded_error",
  "timeout_error"
]);

/**
 * Content-free fields only: an error's constructor name, an HTTP status if
 * the SDK error exposes one (Anthropic's `APIError.status`), and the
 * envelope's error type when it is one this codebase already knows.
 *
 * The type earns its place because status alone is not actionable. A 400
 * from `sessions.create` is "you are out of credits", "the agent id is
 * wrong", and "the repo could not be mounted" all at once, and the founder
 * sees a bare 502 either way — the operator needs to know which. `400` plus
 * `billing_error` is a fix; `400` alone cost an hour of reproducing the call
 * against the live API to find out it was billing.
 */
export function safeErrorDetail(err: unknown): {
  name?: string;
  status?: number;
  errorType?: string;
} {
  const detail: { name?: string; status?: number; errorType?: string } = {};
  if (err instanceof Error) detail.name = err.name;
  const status = (err as { status?: unknown } | null)?.status;
  if (typeof status === "number") detail.status = status;
  const errorType = (err as { error?: { error?: { type?: unknown } } } | null)?.error?.error?.type;
  if (typeof errorType === "string" && KNOWN_ERROR_TYPES.has(errorType)) {
    detail.errorType = errorType;
  }
  return detail;
}
